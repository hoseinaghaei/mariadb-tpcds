"""Controlled Q74 SF4 index and rewrite investigation."""
import argparse, datetime, hashlib, json, pathlib, re, statistics, subprocess, time

p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','indexes','screen','refine','refine2','guard_index','confirm','fixture','finish']);args=p.parse_args()
out=pathlib.Path('/results/q74-study');out.mkdir(exist_ok=True)
cli=['mariadb','--socket=/data/mysql.sock','-uroot','--batch','--skip-column-names','--raw','tpcds']
preamble="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original=pathlib.Path('/project/queries/mariadb/query74.sql').read_text(encoding='utf-8-sig')
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
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'indexes':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode(),'date_bounds':sql('SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year IN (1999,2000)').decode()},indent=2))
    plan('original',original)
    pair({'original':original},'reference167')
    plan('original',original,True); print('Baseline and actual plan saved.',flush=True)

index_defs={'idx_nf_q74_ss_top':('store_sales','ss_customer_sk,ss_net_paid,ss_sold_date_sk'),'idx_nf_q74_ws_top':('web_sales','ws_bill_customer_sk,ws_net_paid,ws_sold_date_sk'),'idx_nf_q74_customer_order':('customer','c_first_name,c_customer_id,c_last_name'),'idx_nf_q74_customer_id':('customer','c_customer_id')}
def visibility(names):
    for name,(table,cols) in index_defs.items():
        if sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}' LIMIT 1").strip():sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))
if args.mode=='indexes':
    for name,(table,cols) in index_defs.items():
        print(f'Testing {name} ({cols}): customer maxima / output ordering',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        start=time.perf_counter();sql(f'SET SESSION max_statement_time=1800;CREATE INDEX {name} ON {table} ({cols})',1900);sql(f'ANALYZE TABLE {table}')
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'table':table,'columns':cols,'bytes':size,'build_seconds':time.perf_counter()-start},indent=2));visibility([])
    visibility(list(index_defs));pair({'index_only':original},'ordered_covering');plan('index_only',original);visibility([])

tail_start=original.rfind('select',0,original.index('t_s_secyear.customer_id'));tail=original[tail_start:]
attrs=['c_customer_id','c_first_name','c_last_name'];aliases=['customer_id','customer_first_name','customer_last_name']
projection=','.join(f'c.{a} {b}' for a,b in zip(attrs,aliases));branches=[]
for table,prefix,customer in [('store_sales','ss','ss_customer_sk'),('web_sales','ws','ws_bill_customer_sk')]:
    branches.append(f'''SELECT f.{customer} customer_sk,d.d_year dyear,MAX(f.{prefix}_net_paid) amount,'{prefix[0]}' sale_type
FROM {table} f JOIN date_dim d ON f.{prefix}_sold_date_sk=d.d_date_sk
WHERE d.d_year IN (1999,2000) GROUP BY f.{customer},d.d_year''')
late='WITH fact_totals AS ('+'\nUNION ALL\n'.join(branches)+f'''), year_total AS (
SELECT {projection},f.dyear AS year,MAX(f.amount) year_total,f.sale_type FROM fact_totals f JOIN customer c ON c.c_customer_sk=f.customer_sk
GROUP BY {','.join('c.'+a for a in attrs)},f.dyear,f.sale_type)
'''+tail
late_range=late
for prefix in ['ss','ws']:late_range=late_range.replace(f'f.{prefix}_sold_date_sk=d.d_date_sk',f'f.{prefix}_sold_date_sk=d.d_date_sk AND f.{prefix}_sold_date_sk BETWEEN 2451180 AND 2451910')
historical=pathlib.Path('/project/queries/optimized/Nafiz/tier5/q74/query74_BEST.sql').read_text(encoding='utf-8-sig')
def maximum(prefix,year):
    table='store_sales' if prefix=='ss' else 'web_sales';customer='ss_customer_sk' if prefix=='ss' else 'ws_bill_customer_sk';index=f'idx_nf_q74_{prefix}_top'
    return f'''(SELECT STRAIGHT_JOIN f.{prefix}_net_paid FROM {table} f FORCE INDEX ({index}) JOIN date_dim d ON f.{prefix}_sold_date_sk=d.d_date_sk
WHERE f.{customer}=c.c_customer_sk AND d.d_year={year} ORDER BY f.{prefix}_net_paid DESC LIMIT 1)'''
s1,s2,w1,w2=[maximum(prefix,year) for prefix,year in [('ss',1999),('ss',2000),('ws',1999),('ws',2000)]]
guard='id_guard AS (SELECT COUNT(*)=COUNT(DISTINCT c_customer_id) ok FROM customer FORCE INDEX (idx_nf_q74_customer_order))'
fast=f'''SELECT c.c_customer_id customer_id,c.c_first_name customer_first_name,c.c_last_name customer_last_name
FROM customer c FORCE INDEX (idx_nf_q74_customer_order)
WHERE (SELECT ok FROM id_guard)=1 AND {s1}>0 AND {w1}>0
AND CASE WHEN {w1}>0 THEN {w2}/{w1} ELSE NULL END > CASE WHEN {s1}>0 THEN {s2}/{s1} ELSE NULL END
ORDER BY c.c_first_name,c.c_customer_id,c.c_last_name LIMIT 100'''
slow=tail.rstrip().rstrip(';').replace(' order by 2,1,3',' AND (SELECT ok FROM id_guard)=0\n order by 2,1,3')
guarded='WITH '+guard+', '+original[:tail_start].strip()[len('with '):]+', fast AS ('+fast+'), slow AS ('+slow+') SELECT * FROM fast UNION ALL SELECT * FROM slow ORDER BY 2,1,3 LIMIT 100;'
guarded_no_force=re.sub(r' FORCE INDEX \(idx_nf_q74_[a-z_]+\)','',guarded)
guarded_webfirst=guarded.replace(f'AND {s1}>0 AND {w1}>0',f'AND {w1}>0 AND {s1}>0')
guarded_presence=guarded.replace(f'AND {s1}>0 AND {w1}>0',f'AND {w1}>0 AND {w2} IS NOT NULL AND {s1}>0 AND {s2} IS NOT NULL')
group_guard='''id_guard AS (SELECT NOT EXISTS (SELECT 1 FROM customer FORCE INDEX (idx_nf_q74_customer_id) GROUP BY c_customer_id HAVING COUNT(*)>1 LIMIT 1)
AND NOT EXISTS (SELECT 1 FROM customer FORCE INDEX (idx_nf_q74_customer_id) WHERE c_customer_id IS NULL LIMIT 1) ok)'''
guarded_stream=guarded.replace(guard,group_guard)
guarded_stream_web=guarded_webfirst.replace(guard,group_guard)
guarded_stream_presence=guarded_presence.replace(guard,group_guard)
candidates={'late_customer':late,'late_range':late_range,'historical_pivot':historical,'guarded_ordered_max':guarded,'guarded_unforced':guarded_no_force,'guarded_webfirst':guarded_webfirst,'guarded_presence':guarded_presence,'stream_guard':guarded_stream,'stream_guard_web':guarded_stream_web,'stream_guard_presence':guarded_stream_presence}
if args.mode=='screen':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    visibility([]);pair({'reference_late':late,'reference_late_range':late_range},'reference167',1)
    visibility(list(index_defs))
    for label,q in candidates.items():print(f'Testing {label}: late aggregation or guarded indexed maxima',flush=True);measure(label,q,'ordered_covering')
    plan('guarded_ordered_max',guarded,True)
    (out/'customer-id-check.json').write_text(json.dumps({'customer_rows':int(sql('SELECT COUNT(*) FROM customer')),'distinct_customer_ids':int(sql('SELECT COUNT(DISTINCT c_customer_id) FROM customer'))},indent=2));visibility([])

if args.mode=='fixture':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    setup='''CREATE TEMPORARY TABLE customer (c_customer_sk BIGINT PRIMARY KEY,c_customer_id VARCHAR(16),c_first_name VARCHAR(20),c_last_name VARCHAR(20),KEY idx_nf_q74_customer_order(c_first_name,c_customer_id,c_last_name));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT);
CREATE TEMPORARY TABLE store_sales (ss_customer_sk BIGINT,ss_sold_date_sk BIGINT,ss_net_paid DECIMAL(9,2),KEY idx_nf_q74_ss_top(ss_customer_sk,ss_net_paid,ss_sold_date_sk));
CREATE TEMPORARY TABLE web_sales (ws_bill_customer_sk BIGINT,ws_sold_date_sk BIGINT,ws_net_paid DECIMAL(9,2),KEY idx_nf_q74_ws_top(ws_bill_customer_sk,ws_net_paid,ws_sold_date_sk));
INSERT INTO date_dim VALUES (2451180,1999),(2451544,1999),(2451545,2000),(2451910,2000),(2451911,2001);
'''
    customers=[]
    for k in range(1,16):
        ident=f'C{k:03d}';first=f"'First{k}'"
        if k in (6,7):ident='DUP'
        if k in (8,9):ident='DUP2';first="'Same'"
        if k==13:first='NULL'
        customers.append(f"({k},'{ident}',{first},'Last')")
    setup+='CREATE INDEX idx_nf_q74_customer_id ON customer(c_customer_id);\nINSERT INTO customer VALUES '+','.join(customers)+';\n'
    store=[];web=[]
    totals={1:(100,200,100,300),2:(100,300,100,200),3:(0,100,100,200),4:(100,100,-1,200),5:(100,None,100,200),6:(100,100,100,200),7:(50,100,100,150),8:(100,100,100,200),9:(50,100,100,150),10:(None,100,100,200),11:('NULL',100,100,200),12:(100,100,100,'NULL'),13:(100,100,100,200),14:(100,-100,100,0),15:(30000,10000,30000,10000.01)}
    for k,(s1,s2,w1,w2) in totals.items():
        for target,value,day in [(store,s1,2451180),(store,s2,2451545),(web,w1,2451180),(web,w2,2451545)]:
            if value is not None:target.append(f'({k},{day},{value})')
    store+=['(1,2451544,100)','(1,2451180,50)','(1,2451911,999999)','(10,2451200,100)','(999,2451180,999)','(1,NULL,999)']
    setup+='INSERT INTO store_sales VALUES '+','.join(store)+';\nINSERT INTO web_sales VALUES '+','.join(web)+';\n'
    unique="UPDATE customer SET c_customer_id=CONCAT('U',c_customer_sk);\n"
    checks=[]
    for case,extra in [('duplicate_ids',''),('unique_ids',unique),('empty_unique',unique+'UPDATE store_sales SET ss_net_paid=0;\n')]:
        reference=sql(setup+extra+original)
        if case!='empty_unique':assert reference and b'NULL' in reference,reference
        else:assert reference==b''
        (out/(case+'.fixture.sql')).write_text(setup+extra+original);(out/(case+'.fixture.out')).write_bytes(reference)
        for label,q in candidates.items():
            value=sql(setup+extra+q);same=value==reference
            if case=='duplicate_ids' and label=='historical_pivot':assert not same
            else:assert same,f'Fixture mismatch {case} {label}: {value!r} vs {reference!r}'
            checks.append({'case':case,'label':label,'exact_match':same,'rows':len(value.splitlines()),'reason':'Historical pivot loses original duplicate-ID combinations' if not same else 'Matched original'})
    (out/'fixture-validation.json').write_text(json.dumps(checks,indent=2))
    print('Q74 fixtures passed for safe rewrites: unique fast path, duplicate-ID fallback, empty results, NULLs, missing years and original ratios.',flush=True)

if args.mode=='refine':
    visibility(list(index_defs))
    pair({'repeat_guarded':guarded,'repeat_unforced':guarded_no_force,'repeat_late':late,'repeat_late_range':late_range},'ordered_covering',3)
    visibility([])

if args.mode=='refine2':
    visibility(list(index_defs))
    pair({'ordered_original_checks':guarded,'web_first_checks':guarded_webfirst,'early_presence':guarded_presence},'ordered_covering',7)
    for label,q in [('web_first_checks',guarded_webfirst),('early_presence',guarded_presence)]:plan(label,q,True)
    visibility([])

if args.mode=='guard_index':
    name='idx_nf_q74_customer_id';table,cols=index_defs[name]
    assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND index_name='{name}'").strip()
    start=time.perf_counter();sql(f'CREATE INDEX {name} ON {table} ({cols})');sql('ANALYZE TABLE customer')
    size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'"))
    (out/(name+'.json')).write_text(json.dumps({'table':table,'columns':cols,'bytes':size,'build_seconds':time.perf_counter()-start},indent=2))
    visibility(list(index_defs))
    options={'base_guard':guarded,'web_first':guarded_webfirst,'stream_guard':guarded_stream,'stream_web':guarded_stream_web,'stream_presence':guarded_stream_presence}
    (out/'refinements.json').write_text(json.dumps(options,indent=2));pair(options,'ordered_covering4',7)
    for label in ['stream_guard','stream_web','stream_presence']:plan(label,options[label],True)
    visibility([])

if args.mode=='confirm':
    three=[n for n in index_defs if n!='idx_nf_q74_customer_id'];four=list(index_defs)
    choices={'final_original':(original,[]),'final_late_reference':(late,[]),'final_guarded':(guarded,three),'final_webfirst':(guarded_webfirst,three),'final_stream_guard':(guarded_stream,four),'final_stream_web':(guarded_stream_web,four),'final_stream_presence':(guarded_stream_presence,four),'control_original_full_profile':(original,four)}
    (out/'final-candidates.json').write_text(json.dumps({label:{'sql':q,'active_extra_indexes':names} for label,(q,names) in choices.items()},indent=2))
    for label,(q,names) in choices.items():visibility(names);measure(label,q,'reference167+'+','.join(names),True)
    for i in range(5):
        items=list(choices.items())
        if i%2:items.reverse()
        for label,(q,names) in items:visibility(names);measure(label,q,'reference167+'+','.join(names))
    full={}
    for label in ['final_original','final_late_reference','final_stream_presence']:
        q,names=choices[label];visibility(names)
        complete=re.sub(r'limit\s+100\b','',q,flags=re.I)
        value=sql(complete);full[label]=value;(out/(label+'.full.out')).write_bytes(value);plan(label,q,True)
    assert len(set(full.values()))==1,'Unlimited Q74 output mismatch'
    checks=json.loads((out/'fixture-validation.json').read_text());assert all(r['exact_match'] for r in checks if r['label']!='historical_pivot')
    (out/'validation.json').write_text(json.dumps({'sf4_ordered_limit100_exact':True,'rows':100,'full_ordered_exact':True,'full_rows':len(full['final_original'].splitlines()),'fixture_unique_fast_and_duplicate_fallback_passed':True,'historical_pivot_duplicate_id_rejected':True,'output_sha256':hashlib.sha256((out/'original.out').read_bytes()).hexdigest()},indent=2));visibility([])

if args.mode=='finish':
    from reference_indexes import expected_indexes,actual_indexes,verify_indexes
    expected=expected_indexes();actual,ignored=actual_indexes();owned={(table,name):(1,tuple(cols.split(','))) for name,(table,cols) in index_defs.items()}
    assert set(actual)-set(expected)==set(owned) and all(actual[k]==v for k,v in owned.items())
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE store_sales,web_sales,customer');assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned]},indent=2))
    print('Restored shared 167-index reference profile.',flush=True)

