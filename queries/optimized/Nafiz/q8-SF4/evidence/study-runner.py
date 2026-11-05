"""Controlled Q8 SF4 index and rewrite investigation."""
import argparse, datetime, hashlib, json, pathlib, re, statistics, subprocess, time

p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','indexes','screen','refine','confirm','fixture','finish']);args=p.parse_args()
out=pathlib.Path('/results/q8-study');out.mkdir(exist_ok=True)
cli=['mariadb','--socket=/data/mysql.sock','-uroot','--batch','--skip-column-names','--raw','tpcds']
preamble="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original=pathlib.Path('/project/queries/mariadb/query8.sql').read_text(encoding='utf-8-sig')
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
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'indexes':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode(),'date_bounds':sql('SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year=2000 AND d_qoy=2').decode()},indent=2))
    print(plan('original',original),flush=True)
    pair({'original':original},'reference167')
    print(plan('original',original,True),flush=True)

index_defs={
 'idx_nf_q8_pref_addr':('customer','c_preferred_cust_flag,c_current_addr_sk'),
 'idx_nf_q8_addr_pref':('customer','c_current_addr_sk,c_preferred_cust_flag'),
 'idx_nf_q8_zip_cover':('customer_address','ca_zip'),
}
def visibility(names):
    for name,(table,cols) in index_defs.items():
        if sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}' LIMIT 1").strip():
            sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))

if args.mode=='indexes':
    for name,(table,cols) in index_defs.items():
        print(f'Testing index {name} ({cols}): cover preferred-customer / address work',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        start=time.perf_counter();sql(f'CREATE INDEX {name} ON {table} ({cols})')
        sql(f'ANALYZE TABLE {table}')
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'table':table,'columns':cols,'build_seconds':time.perf_counter()-start,'bytes':size},indent=2))
        visibility([])
    profiles={'preferred_cover':['idx_nf_q8_pref_addr'],'address_cover':['idx_nf_q8_addr_pref','idx_nf_q8_zip_cover'],'all_cover':list(index_defs)}
    for label,names in profiles.items():
        visibility(names);plan(label,original);pair({label:original},label)
    visibility([])

ziplist=re.search(r'WHERE substr\(ca_zip,1,5\) IN \((.*?)\)\s*intersect',original,re.S|re.I).group(1)
inner=original[original.index('(select ca_zip'):original.rindex(' V1')].strip()
range_query=original.replace('d_qoy = 2 and d_year = 2000','d_qoy = 2 and d_year = 2000 AND ss_sold_date_sk BETWEEN 2451636 AND 2451726')
early=f'''SELECT STRAIGHT_JOIN s_store_name, SUM(ss_net_profit)
FROM {inner} V1, store, date_dim, store_sales
WHERE SUBSTR(s_zip,1,2)=SUBSTR(V1.ca_zip,1,2)
AND ss_store_sk=s_store_sk AND ss_sold_date_sk=d_date_sk
AND d_qoy=2 AND d_year=2000
GROUP BY s_store_name ORDER BY s_store_name LIMIT 100;'''
eligible=f'''SELECT DISTINCT SUBSTR(a.ca_zip,1,5) AS ca_zip
FROM customer_address a JOIN customer c ON a.ca_address_sk=c.c_current_addr_sk
WHERE c.c_preferred_cust_flag='Y' AND SUBSTR(a.ca_zip,1,5) IN ({ziplist})
GROUP BY a.ca_zip HAVING COUNT(*)>10'''
simplified=f'''WITH eligible AS ({eligible})
SELECT STRAIGHT_JOIN s_store_name, SUM(ss_net_profit)
FROM eligible V1, store, date_dim, store_sales
WHERE SUBSTR(s_zip,1,2)=SUBSTR(V1.ca_zip,1,2)
AND ss_store_sk=s_store_sk AND ss_sold_date_sk=d_date_sk
AND d_qoy=2 AND d_year=2000
GROUP BY s_store_name ORDER BY s_store_name LIMIT 100;'''
weighted=f'''WITH eligible AS ({eligible}), zip_counts AS (
SELECT SUBSTR(ca_zip,1,2) prefix, COUNT(*) zip_count FROM eligible GROUP BY SUBSTR(ca_zip,1,2))
SELECT STRAIGHT_JOIN s_store_name, SUM(ss_net_profit*zip_count)
FROM zip_counts z, store, date_dim, store_sales
WHERE SUBSTR(s_zip,1,2)=z.prefix
AND ss_store_sk=s_store_sk AND ss_sold_date_sk=d_date_sk
AND d_qoy=2 AND d_year=2000
GROUP BY s_store_name ORDER BY s_store_name LIMIT 100;'''
candidates={'date_range':range_query,'zip_store_first':early,'filtered_group':simplified,'weighted_prefix':weighted,
 'filtered_range':simplified.replace('d_qoy=2 AND d_year=2000','d_qoy=2 AND d_year=2000 AND ss_sold_date_sk BETWEEN 2451636 AND 2451726'),
 'filtered_no_order_hint':simplified.replace('STRAIGHT_JOIN ',''),
 'filtered_address_first':simplified.replace('SELECT DISTINCT SUBSTR','SELECT DISTINCT STRAIGHT_JOIN SUBSTR'),
}
if args.mode=='screen':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    for label,names in [('reference167',[]),('preferred_cover',['idx_nf_q8_pref_addr']),('address_cover',['idx_nf_q8_addr_pref','idx_nf_q8_zip_cover'])]:
        visibility(names);pair({f'{label}__{k}':v for k,v in candidates.items()},label)
    visibility([])
    for label,q in candidates.items():plan(label,q)

zips=re.findall(r"'([0-9]{5})'",ziplist)
like_ranges=' OR '.join(f"a.ca_zip LIKE '{z}%'" for z in sorted(set(zips)))
store_filter="EXISTS (SELECT 1 FROM store st WHERE SUBSTR(st.s_zip,1,2)=SUBSTR(a.ca_zip,1,2))"
like_query=simplified.replace("WHERE c.c_preferred_cust_flag='Y'",f"WHERE ({like_ranges}) AND c.c_preferred_cust_flag='Y'")
push_query=simplified.replace("WHERE c.c_preferred_cust_flag='Y'",f"WHERE {store_filter} AND c.c_preferred_cust_flag='Y'")
combined=like_query.replace("WHERE (",f"WHERE {store_filter} AND (",1)
refinements={'prefix_ranges':like_query,'store_pushdown':push_query,'prefix_and_store':combined,
 'prefix_ordered_address':like_query.replace('SELECT DISTINCT SUBSTR','SELECT DISTINCT STRAIGHT_JOIN SUBSTR'),
 'prefix_no_order_hint':like_query.replace('STRAIGHT_JOIN ',''),
}
if args.mode=='refine':
    visibility(['idx_nf_q8_addr_pref','idx_nf_q8_zip_cover'])
    (out/'refinements.json').write_text(json.dumps(refinements,indent=2))
    pair(refinements,'address_cover',5)
    for label,q in refinements.items():plan(label,q,True)
    visibility([])

if args.mode=='fixture':
    setup='''CREATE TEMPORARY TABLE customer_address (ca_address_sk BIGINT PRIMARY KEY,ca_zip CHAR(10));
CREATE TEMPORARY TABLE customer (c_current_addr_sk BIGINT,c_preferred_cust_flag CHAR(1));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_qoy INT,d_year INT);
CREATE TEMPORARY TABLE store (s_store_sk BIGINT PRIMARY KEY,s_store_name VARCHAR(50),s_zip CHAR(10));
CREATE TEMPORARY TABLE store_sales (ss_store_sk BIGINT,ss_sold_date_sk BIGINT,ss_net_profit DECIMAL(7,2));
INSERT INTO customer_address VALUES (1,'67454-0001'),(2,'67454-0002'),(3,'67625-0001'),(4,'28844-0001'),(5,'28844-0002'),(6,'95202'),(7,'29771'),(8,NULL),(9,'99999');
INSERT INTO date_dim VALUES (2451636,2,2000),(2451637,2,2000),(2451635,1,2000),(2451727,3,2000);
INSERT INTO store VALUES (1,'Alpha','67000'),(2,'Alpha','67001'),(3,'Beta','28000'),(4,'Gamma','95000'),(5,'Null profit','67002'),(6,'No sales','67003'),(7,'Wrong quarter','67004'),(8,'Absent date','67005');
INSERT INTO store_sales VALUES (1,2451636,10.25),(1,2451637,-2.00),(1,2451637,NULL),(2,2451636,3.00),(3,2451636,100.00),(4,2451636,7.00),(5,2451636,NULL),(7,2451635,999.00),(8,123,999.00),(999,2451636,999.00),(1,NULL,999.00),(1,2451727,999.00);
'''
    counts={1:11,2:11,3:12,4:6,5:6,6:10,7:0,8:15,9:20}
    values=[f"({address},'Y')" for address,count in counts.items() for i in range(count)]
    values+= ["(7,'N')"]*15+["(6,'N')"]*20+["(999,'Y')"]*15
    setup+='INSERT INTO customer VALUES '+','.join(values)+';\n'
    cases={'original':original,**candidates,**refinements}
    reference=None;results=[]
    for label,q in cases.items():
        result=sql(setup+q)
        if reference is None:reference=result
        assert result==reference,f'Nonempty fixture mismatch {label}: {result!r} vs {reference!r}'
        results.append({'label':label,'exact_match':True,'rows':len(result.splitlines()),'sha256':hashlib.sha256(result).hexdigest()})
    assert reference==b'Alpha\t22.50\nNull profit\tNULL\n',reference
    (out/'nonempty-fixture.sql').write_text(setup+'\n-- Original query\n'+original)
    (out/'nonempty-fixture.out').write_bytes(reference)
    (out/'fixture-validation.json').write_text(json.dumps(results,indent=2))
    print(f'Nonempty fixture: {len(results)} original/variants matched exactly; duplicate ZIP prefixes, raw ZIP groups, >10 threshold, NULLs and missing joins checked.',flush=True)

if args.mode=='confirm':
    pairnames=['idx_nf_q8_addr_pref','idx_nf_q8_zip_cover']
    choices={
     'final_original':(original,[]),
     'final_zip_first':(early,[]),
     'final_index_only':(original,pairnames),
     'final_filtered_address':(candidates['filtered_address_first'],[]),
     'final_filtered_cover':(simplified,pairnames),
     'final_prefix_pushdown':(combined,pairnames),
    }
    (out/'final-candidates.json').write_text(json.dumps({label:{'sql':q,'active_extra_indexes':names} for label,(q,names) in choices.items()},indent=2))
    for label,(q,names) in choices.items():visibility(names);measure(label,q,'reference167+'+','.join(names),True)
    for i in range(7):
        items=list(choices.items())
        if i%2:items.reverse()
        for label,(q,names) in items:visibility(names);measure(label,q,'reference167+'+','.join(names))
    visibility([])
    plan('final_original',original,True)
    original_zip=sql(f'SELECT ca_zip FROM {inner} V1 ORDER BY ca_zip;')
    simple_zip=sql(f'SELECT ca_zip FROM ({eligible}) e ORDER BY ca_zip;')
    assert original_zip==simple_zip
    (out/'original-eligible-zips.out').write_bytes(original_zip)
    (out/'rewritten-eligible-zips.out').write_bytes(simple_zip)
    matches=sql(f'SELECT COUNT(*) FROM ({eligible}) e JOIN store s ON SUBSTR(s.s_zip,1,2)=SUBSTR(e.ca_zip,1,2);').decode().strip()
    assert matches=='0',matches
    visibility(pairnames)
    for label in ['final_index_only','final_filtered_cover','final_prefix_pushdown']:plan(label,choices[label][0],True)
    (out/'validation.json').write_text(json.dumps({'sf4_exact_match':True,'sf4_rows':0,'eligible_zip_sets_exact':True,'eligible_zip_count':len(original_zip.splitlines()),'matching_store_zip_pairs':int(matches),'nonempty_fixture_checked':True,'fixture_variants':len(json.loads((out/'fixture-validation.json').read_text()))},indent=2))
    visibility([])

if args.mode=='finish':
    from reference_indexes import expected_indexes,actual_indexes,verify_indexes
    expected=expected_indexes();actual,ignored=actual_indexes()
    owned={(table,name):(1,tuple(cols.split(','))) for name,(table,cols) in index_defs.items()}
    assert set(actual)-set(expected)==set(owned)
    assert all(actual[k]==v for k,v in owned.items())
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE customer,customer_address');assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned]},indent=2))
    print('Restored shared reference profile: 167 secondary indexes, none ignored.',flush=True)
