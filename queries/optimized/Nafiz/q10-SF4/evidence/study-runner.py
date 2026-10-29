"""Controlled Q10 SF4 index and rewrite investigation."""
import argparse, datetime, hashlib, json, pathlib, re, statistics, subprocess, time

p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','indexes','screen','refine','refine2','confirm','fixture','finish']);args=p.parse_args()
out=pathlib.Path('/results/q10-study');out.mkdir(exist_ok=True)
cli=['mariadb','--socket=/data/mysql.sock','-uroot','--batch','--skip-column-names','--raw','tpcds']
preamble="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original=pathlib.Path('/project/queries/mariadb/query10.sql').read_text(encoding='utf-8-sig')
records=json.loads((out/'runs.json').read_text()) if (out/'runs.json').exists() else []
def sql(q,timeout=150):
    proc=subprocess.run(cli,input=(preamble+q).encode(),capture_output=True,timeout=timeout)
    if proc.returncode: raise RuntimeError(proc.stderr.decode())
    return proc.stdout
def plan(label,q,analyze=False):
    value=sql(('ANALYZE' if analyze else 'EXPLAIN')+' FORMAT=JSON '+q)
    (out/(label+('.analyze.json' if analyze else '.explain.json'))).write_bytes(value)
    return value.decode()
def measure(label,q,profile,warmup=False):
    started=time.perf_counter();value=sql(q);elapsed=time.perf_counter()-started
    if not (out/'original.out').exists():(out/'original.out').write_bytes(value)
    assert value==(out/'original.out').read_bytes(),f'Output mismatch {label}'
    row={'label':label,'profile':profile,'warmup':warmup,'seconds':elapsed,'rows':len(value.splitlines()),'output_sha256':hashlib.sha256(value).hexdigest(),'sql_sha256':hashlib.sha256(q.encode()).hexdigest()}
    records.append(row);(out/'runs.json').write_text(json.dumps(records,indent=2))
    print(f'{label}: {elapsed:.6f}s; {row["rows"]} rows; exact match'+(' (warmup)' if warmup else ''),flush=True)
def pair(choices,profile,repeats=3):
    for name,q in choices.items():print(f'Testing {name} on {profile}',flush=True);measure(name,q,profile,True)
    for i in range(repeats):
        items=list(choices.items())
        if i%2:items.reverse()
        for name,q in items:measure(name,q,profile)

if args.mode=='inspect':
    from reference_indexes import verify_indexes
    assert verify_indexes()==167
    assert sql('SELECT @@innodb_buffer_pool_size').strip()==b'8589934592'
    assert pathlib.Path('/data/tpcds-data/.scale').read_text().strip()=='4:10'
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'indexes':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode(),'date_bounds':sql('SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year=2001 AND d_moy BETWEEN 4 AND 7').decode()},indent=2))
    print(plan('original',original),flush=True)
    pair({'original':original},'reference167')
    print(plan('original',original,True),flush=True)

index_defs={'idx_nf_q10_county':('customer_address','ca_county'),'idx_nf_q10_addr_demo':('customer','c_current_addr_sk,c_current_cdemo_sk')}
def visibility(names):
    for name,(table,cols) in index_defs.items():
        if sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}' LIMIT 1").strip():
            sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))
if args.mode=='indexes':
    for name,(table,cols) in index_defs.items():
        print(f'Testing index {name} ({cols}): county-first covering access',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        start=time.perf_counter();sql(f'CREATE INDEX {name} ON {table} ({cols})');sql(f'ANALYZE TABLE {table}')
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'table':table,'columns':cols,'build_seconds':time.perf_counter()-start,'bytes':size},indent=2));visibility([])
    for label,names in [('county_index',['idx_nf_q10_county']),('county_cover',list(index_defs))]:
        visibility(names);plan(label,original);pair({label:original},label)
    visibility([])

range_query=original
for fact in ['ss','ws','cs']:
    range_query=range_query.replace(f'{fact}_sold_date_sk = d_date_sk',f'{fact}_sold_date_sk = d_date_sk AND {fact}_sold_date_sk BETWEEN 2452001 AND 2452122')
nodate=pathlib.Path('/project/queries/optimized/Nafiz/tier4/q10/query10_BEST.sql').read_text(encoding='utf-8-sig')
county_first=original.replace('select  ','select STRAIGHT_JOIN ',1).replace('customer c,customer_address ca,customer_demographics','customer_address ca,customer c,customer_demographics')
county_range=range_query.replace('select  ','select STRAIGHT_JOIN ',1).replace('customer c,customer_address ca,customer_demographics','customer_address ca,customer c,customer_demographics')
candidates={'date_ranges':range_query,'county_first':county_first,'county_ranges':county_range,'previous_nodate':nodate,
 'correlated':"SET SESSION optimizer_switch='exists_to_in=off';\n"+original,
 'correlated_ranges':"SET SESSION optimizer_switch='exists_to_in=off';\n"+range_query,
 'swap_web_catalog':original.replace('from web_sales,date_dim','from catalog_sales,date_dim').replace('c.c_customer_sk = ws_bill_customer_sk','c.c_customer_sk = cs_ship_customer_sk').replace('ws_sold_date_sk = d_date_sk','cs_sold_date_sk = d_date_sk',1),
}
# Swap whole OR branches, rather than changing channel keys.
start=original.index('   (exists');end=original.index(' group by')
branches=original[start:end];split=branches.index(' or ')
first=branches[len('   ('):split].strip();second=branches[split+4:].strip();second=second[:-1]
candidates['swap_web_catalog']=original[:start]+'   ('+second+' OR '+first+')\n'+original[end:]
if args.mode=='screen':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    for profile,names in [('reference167',[]),('county_index',['idx_nf_q10_county']),('county_cover',list(index_defs))]:
        visibility(names);pair({profile+'__'+label:q for label,q in candidates.items()},profile)
    visibility([])
    for label,q in candidates.items():
        if not q.startswith('SET'):plan(label,q)

def union_channels(q):
    begin=q.index('   (exists');finish=q.index(' group by')
    channel=''' EXISTS (SELECT 1 FROM web_sales w JOIN date_dim d ON w.ws_sold_date_sk=d.d_date_sk
WHERE w.ws_bill_customer_sk=c.c_customer_sk AND d.d_year=2001 AND d.d_moy BETWEEN 4 AND 7
AND w.ws_sold_date_sk BETWEEN 2452001 AND 2452122
UNION ALL
SELECT 1 FROM catalog_sales k JOIN date_dim d ON k.cs_sold_date_sk=d.d_date_sk
WHERE k.cs_ship_customer_sk=c.c_customer_sk AND d.d_year=2001 AND d.d_moy BETWEEN 4 AND 7
AND k.cs_sold_date_sk BETWEEN 2452001 AND 2452122)\n'''
    return q[:begin]+channel+q[finish:]
unionq=union_channels(county_range)
union_noorder=union_channels(range_query)
unioncor="SET SESSION optimizer_switch='exists_to_in=off';\n"+union_noorder
refinements={'union_exists':unionq,'union_no_order':union_noorder,'union_correlated':unioncor,
 'county_range':county_range,
 'in_dates':county_range.replace('ss_sold_date_sk = d_date_sk AND ss_sold_date_sk BETWEEN 2452001 AND 2452122','ss_sold_date_sk = d_date_sk AND ss_sold_date_sk BETWEEN 2452001 AND 2452122')}
del refinements['in_dates']
def channel_first(q):
    s=q.index('  exists');o=q.index('   (exists');g=q.index(' group by')
    store=q[s:o].strip();assert store.endswith('and');store=store[:-3].strip()
    return q[:s]+q[o:g].strip()+' AND\n '+store+'\n'+q[g:]
chanfirst=channel_first(county_range)
refinements.update({'channel_first':chanfirst,'channel_first_no_bka':"SET @q10_saved_cache=@@join_cache_level; SET SESSION join_cache_level=0;\n"+chanfirst+'\nSET SESSION join_cache_level=@q10_saved_cache;', 'channel_first_union':channel_first(county_range)})
del refinements['channel_first_union']
if args.mode=='refine':
    (out/'refinements.json').write_text(json.dumps(refinements,indent=2))
    for profile,names in [('county_index',['idx_nf_q10_county']),('county_cover',list(index_defs))]:
        visibility(names);pair({profile+'__'+label:q for label,q in refinements.items()},profile,5)
        for label,q in refinements.items():
            if not q.startswith('SET'):plan(profile+'__'+label,q,True)
    visibility([])

if args.mode=='refine2':
    (out/'refinements.json').write_text(json.dumps(refinements,indent=2))
    visibility(['idx_nf_q10_county'])
    pair({name:refinements[name] for name in ['county_range','channel_first','channel_first_no_bka']},'county_index',7)
    plan('channel_first',chanfirst,True)
    visibility([])

if args.mode=='fixture':
    setup='''CREATE TEMPORARY TABLE customer_address (ca_address_sk BIGINT PRIMARY KEY,ca_county VARCHAR(50));
CREATE TEMPORARY TABLE customer (c_customer_sk BIGINT PRIMARY KEY,c_current_addr_sk BIGINT,c_current_cdemo_sk BIGINT);
CREATE TEMPORARY TABLE customer_demographics (cd_demo_sk BIGINT PRIMARY KEY,cd_gender CHAR(1),cd_marital_status CHAR(1),cd_education_status VARCHAR(20),cd_purchase_estimate INT,cd_credit_rating VARCHAR(10),cd_dep_count INT,cd_dep_employed_count INT,cd_dep_college_count INT);
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT,d_moy INT);
CREATE TEMPORARY TABLE store_sales (ss_customer_sk BIGINT,ss_sold_date_sk BIGINT);
CREATE TEMPORARY TABLE web_sales (ws_bill_customer_sk BIGINT,ws_sold_date_sk BIGINT);
CREATE TEMPORARY TABLE catalog_sales (cs_ship_customer_sk BIGINT,cs_bill_customer_sk BIGINT,cs_sold_date_sk BIGINT);
INSERT INTO customer_address VALUES (1,'Madison County'),(2,'Wallowa County'),(3,'Calhoun County'),(4,'Broadwater County'),(5,'McCone County'),(6,'Other County');
INSERT INTO customer_demographics VALUES (1,'F','S','College',100,'Good',0,0,0),(2,'M','M','Unknown',200,'Low',1,0,0);
INSERT INTO date_dim VALUES (2452001,2001,4),(2452122,2001,7),(2452000,2001,3),(2452123,2001,8),(999,2002,4);
INSERT INTO customer VALUES (1,1,1),(2,2,1),(3,3,2),(4,4,2),(5,5,2),(6,6,2),(7,1,2),(8,1,2),(9,1,999),(10,999,2),(11,1,2),(12,1,2),(13,1,NULL),(14,1,2),(15,1,1),(16,1,1),(17,1,2);
INSERT INTO store_sales VALUES (1,2452001),(1,2452001),(2,2452001),(3,2452001),(4,2452001),(6,2452001),(7,2452000),(8,2452002),(9,2452001),(10,2452001),(11,2452001),(12,2452001),(13,2452001),(14,2452001),(15,2452001),(16,999),(17,2452001),(NULL,2452001);
INSERT INTO web_sales VALUES (1,2452001),(1,2452001),(3,2452122),(5,2452001),(6,2452001),(7,2452000),(8,2452002),(9,2452001),(10,2452001),(13,2452001),(14,NULL),(16,999),(17,2452001),(NULL,2452001);
INSERT INTO catalog_sales VALUES (2,999,2452122),(2,999,2452122),(3,999,2452001),(999,11,2452001),(15,999,2452122),(NULL,12,2452001);
'''
    reference=sql(setup+original)
    lines=[row.split(b'\t') for row in reference.splitlines()]
    assert len(lines)==2 and [int(row[3]) for row in lines]==[3,2],reference
    checks=[]
    for label,q in {**candidates,**refinements}.items():
        value=sql(setup+q);same=value==reference
        if label=='previous_nodate':assert not same,'Missing-date fixture should expose join-removal assumption'
        else:assert same,f'Fixture mismatch {label}: {value!r} vs {reference!r}'
        checks.append({'label':label,'exact_match':same,'reason':'Date join removal admits an orphan date key' if not same else 'Matched original'})
    (out/'nonempty-fixture.sql').write_text(setup+original);(out/'nonempty-fixture.out').write_bytes(reference)
    (out/'fixture-validation.json').write_text(json.dumps(checks,indent=2))
    print('Fixture passed for all retained-capable rewrites; historical no-date variant rejected because it includes missing date keys.',flush=True)

if args.mode=='confirm':
    choices={'final_original':(original,[]),'final_county_first':(county_first,[]),'final_county_index':(original,['idx_nf_q10_county']),'final_county_ranges':(county_range,['idx_nf_q10_county'])}
    (out/'final-candidates.json').write_text(json.dumps({label:{'sql':q,'active_extra_indexes':names} for label,(q,names) in choices.items()},indent=2))
    for label,(q,names) in choices.items():visibility(names);measure(label,q,'reference167+'+','.join(names),True)
    for i in range(7):
        items=list(choices.items())
        if i%2:items.reverse()
        for label,(q,names) in items:visibility(names);measure(label,q,'reference167+'+','.join(names))
    full={}
    for label in ['final_original','final_county_ranges']:
        q,names=choices[label];visibility(names)
        value=sql(re.sub(r'limit\s+100\s*;', ';',q,flags=re.I));full[label]=value;(out/(label+'.full.out')).write_bytes(value)
        plan(label,q,True)
    assert len(set(full.values()))==1 and full['final_original']==(out/'original.out').read_bytes()
    checks=json.loads((out/'fixture-validation.json').read_text());assert all(r['exact_match'] for r in checks if r['label']!='previous_nodate')
    (out/'validation.json').write_text(json.dumps({'sf4_exact':True,'sf4_rows':len(full['final_original'].splitlines()),'full_group_exact':True,'fixture_passed_retained':True,'historical_nodate_rejected':True,'output_sha256':hashlib.sha256(full['final_original']).hexdigest()},indent=2));visibility([])

if args.mode=='finish':
    from reference_indexes import expected_indexes,actual_indexes,verify_indexes
    expected=expected_indexes();actual,ignored=actual_indexes();owned={(table,name):(1,tuple(cols.split(','))) for name,(table,cols) in index_defs.items()}
    assert set(actual)-set(expected)==set(owned) and all(actual[k]==v for k,v in owned.items())
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE customer,customer_address');assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned]},indent=2))
    print('Shared reference restored: 167 visible secondary indexes.',flush=True)

