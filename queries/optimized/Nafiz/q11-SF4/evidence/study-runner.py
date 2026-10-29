"""Controlled Q11 SF4 index and rewrite investigation."""
import argparse, datetime, hashlib, json, pathlib, re, statistics, subprocess, time

p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','indexes','screen','refine','refine2','confirm','fixture','finish']);args=p.parse_args()
out=pathlib.Path('/results/q11-study');out.mkdir(exist_ok=True)
cli=['mariadb','--socket=/data/mysql.sock','-uroot','--batch','--skip-column-names','--raw','tpcds']
preamble="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original=pathlib.Path('/project/queries/mariadb/query11.sql').read_text(encoding='utf-8-sig')
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
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'indexes':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode(),'date_bounds':sql('SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year IN (2001,2002)').decode()},indent=2))
    plan('original',original)
    pair({'original':original},'reference167')
    plan('original',original,True); print('Baseline and actual plan saved.',flush=True)

index_defs={'idx_nf_q11_ss_cover':('store_sales','ss_sold_date_sk,ss_customer_sk,ss_ext_list_price,ss_ext_discount_amt'),'idx_nf_q11_ws_cover':('web_sales','ws_sold_date_sk,ws_bill_customer_sk,ws_ext_list_price,ws_ext_discount_amt')}
def visibility(names):
    for name,(table,cols) in index_defs.items():
        if sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}' LIMIT 1").strip():
            sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))
if args.mode=='indexes':
    for name,(table,cols) in index_defs.items():
        print(f'Testing {name}: cover dates, customer key and both revenue inputs',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        start=time.perf_counter();sql(f'SET SESSION max_statement_time=1800;CREATE INDEX {name} ON {table} ({cols})',1900);sql(f'ANALYZE TABLE {table}')
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'table':table,'columns':cols,'bytes':size,'build_seconds':time.perf_counter()-start},indent=2));visibility([])
    for label,names in [('store_cover',['idx_nf_q11_ss_cover']),('both_cover',list(index_defs))]:
        visibility(names);pair({label:original},label);plan(label,original)
    visibility([])

year_filter=original.replace('ss_sold_date_sk = d_date_sk','ss_sold_date_sk = d_date_sk AND d_year IN (2001,2002)').replace('ws_sold_date_sk = d_date_sk','ws_sold_date_sk = d_date_sk AND d_year IN (2001,2002)')
narrow=year_filter
for field in ['c_preferred_cust_flag customer_preferred_cust_flag','c_birth_country customer_birth_country','c_email_address customer_email_address']:
    narrow=narrow.replace('       ,'+field+'\n','')
tail=original[original.rfind('select',0,original.index('t_s_secyear.customer_id')):]
attrs=['c_customer_id','c_first_name','c_last_name','c_preferred_cust_flag','c_birth_country','c_login','c_email_address']
aliases=['customer_id','customer_first_name','customer_last_name','customer_preferred_cust_flag','customer_birth_country','customer_login','customer_email_address']
projection=','.join(f'c.{a} {b}' for a,b in zip(attrs,aliases))
branches=[]
for table,prefix,customer in [('store_sales','ss','ss_customer_sk'),('web_sales','ws','ws_bill_customer_sk')]:
    branches.append(f'''SELECT f.{customer} customer_sk,d.d_year dyear,SUM(f.{prefix}_ext_list_price-f.{prefix}_ext_discount_amt) amount,'{prefix[0]}' sale_type
FROM {table} f JOIN date_dim d ON f.{prefix}_sold_date_sk=d.d_date_sk
WHERE d.d_year IN (2001,2002) GROUP BY f.{customer},d.d_year''')
late='WITH fact_totals AS ('+'\nUNION ALL\n'.join(branches)+f'''), year_total AS (
SELECT {projection},f.dyear,SUM(f.amount) year_total,f.sale_type FROM fact_totals f JOIN customer c ON c.c_customer_sk=f.customer_sk
GROUP BY {','.join('c.'+a for a in attrs)},f.dyear,f.sale_type)
'''+tail
late_range=late
for table,prefix,customer in [('store_sales','ss','ss_customer_sk'),('web_sales','ws','ws_bill_customer_sk')]:
    late_range=late_range.replace(f'f.{prefix}_sold_date_sk=d.d_date_sk',f'f.{prefix}_sold_date_sk=d.d_date_sk AND f.{prefix}_sold_date_sk BETWEEN 2451911 AND 2452640')
oldpivot=pathlib.Path('/project/queries/optimized/Nafiz/tier5/q11/query11_BEST.sql').read_text(encoding='utf-8-sig')
def split_off(q):return "SET @q11_switch=@@optimizer_switch; SET SESSION optimizer_switch='split_materialized=off';\n"+q+'\nSET SESSION optimizer_switch=@q11_switch;'
candidates={'year_filter':year_filter,'narrow_years':narrow,'late_customer':late,'late_customer_range':late_range,'original_split_off':split_off(original),'late_split_off':split_off(late),'historical_pivot':oldpivot,'historical_pivot_split_off':split_off(oldpivot)}
if args.mode=='screen':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    profile='both_cover';visibility(list(index_defs))
    # One exploratory pass first; only promising approaches receive repeated trials.
    for label,q in candidates.items():print(f'Testing {label}: selective years, materialization or late dimension lookup',flush=True);measure(label,q,profile)
    visibility([])

if args.mode=='fixture':
    setup='''CREATE TEMPORARY TABLE customer (c_customer_sk BIGINT PRIMARY KEY,c_customer_id VARCHAR(16),c_first_name VARCHAR(20),c_last_name VARCHAR(20),c_preferred_cust_flag CHAR(1),c_birth_country VARCHAR(20),c_login VARCHAR(20),c_email_address VARCHAR(50));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT);
CREATE TEMPORARY TABLE store_sales (ss_customer_sk BIGINT,ss_sold_date_sk BIGINT,ss_ext_list_price DECIMAL(9,2),ss_ext_discount_amt DECIMAL(9,2));
CREATE TEMPORARY TABLE web_sales (ws_bill_customer_sk BIGINT,ws_sold_date_sk BIGINT,ws_ext_list_price DECIMAL(9,2),ws_ext_discount_amt DECIMAL(9,2));
INSERT INTO date_dim VALUES (2451911,2001),(2452275,2001),(2452276,2002),(2452640,2002),(2451545,2000);
'''
    customers=[]
    for k in range(1,14):
        ident=f'C{k:03d}';first=f'First{k}';login=f'login{k}';preferred='Y';country='Country'
        if k in (6,7):ident='DUP'
        if k in (8,9):ident='DUP2';first='Same';login='same';preferred='Y' if k==8 else 'N'
        customers.append(f"({k},'{ident}','{first}','Last','{preferred}','{country}','{login}','email{k}')")
    setup+='INSERT INTO customer VALUES '+','.join(customers)+';\n'
    store=[];web=[]
    totals={1:(100,110,100,150),2:(100,200,100,150),3:(0,110,100,150),4:(100,110,-1,150),5:(100,None,100,150),6:(100,100,100,200),7:(50,100,100,150),8:(100,100,100,200),9:(50,100,100,150),10:(100,110,100,None),11:('NULL',110,100,150),12:(None,110,100,150),13:(30000,10000,30000,10000.01)}
    for k,(s1,s2,w1,w2) in totals.items():
        for target,value,date in [(store,s1,2451911),(store,s2,2452276),(web,w1,2451911),(web,w2,2452276)]:
            if value is not None:target.append(f'({k},{date},{value},0)')
    store += ['(12,2452000,100,0)','(999,2451911,999,0)','(1,2451545,999,0)','(1,2452276,NULL,0)']
    # Preserve the net amount while checking duplicate purchases and discounts.
    store.remove('(1,2451911,100,0)');store+=['(1,2451911,60,10)','(1,2451911,60,10)']
    setup+='INSERT INTO store_sales VALUES '+','.join(store)+';\nINSERT INTO web_sales VALUES '+','.join(web)+';\n'
    reference=sql(setup+original);assert b'C001\t' in reference and b'C002\t' not in reference and b'DUP\t' in reference
    checks=[]
    cases=dict(candidates)
    if (out/'refinements.json').exists():cases.update(json.loads((out/'refinements.json').read_text()))
    for label,q in cases.items():
        value=sql(setup+q);same=value==reference
        if label.startswith('historical_pivot'):assert not same,'Duplicate customer-ID fixture should expose pivot grouping assumption'
        else:assert same,f'Fixture mismatch {label}: {value!r} vs {reference!r}'
        checks.append({'label':label,'exact_match':same,'reason':'Pivot loses original cross-group combinations when business IDs repeat' if not same else 'Matched original'})
    (out/'nonempty-fixture.sql').write_text(setup+original);(out/'nonempty-fixture.out').write_bytes(reference);(out/'fixture-validation.json').write_text(json.dumps(checks,indent=2))
    print('Fixture: safe rewrites match; historical pivot fails duplicate-business-ID semantics. Original grouping and ratio expressions retained.',flush=True)

if args.mode=='refine':
    visibility([])
    print('Testing late aggregation on unchanged reference indexes',flush=True)
    pair({'reference_late':late,'reference_late_range':late_range},'reference167',3)
    visibility(list(index_defs))
    pair({'repeat_late':late,'repeat_late_range':late_range,'repeat_late_split_off':split_off(late),'repeat_range_split_off':split_off(late_range)},'both_cover',3)
    (out/'refinements.json').write_text(json.dumps({'repeat_late':late,'repeat_late_range':late_range,'repeat_late_split_off':split_off(late),'repeat_range_split_off':split_off(late_range)},indent=2))
    (out/'customer-id-check.json').write_text(json.dumps({'customer_rows':int(sql('SELECT COUNT(*) FROM customer')),'distinct_customer_ids':int(sql('SELECT COUNT(DISTINCT c_customer_id) FROM customer'))},indent=2))
    visibility([])

if args.mode=='confirm':
    choices={'final_original':(original,[]),'final_store_cover':(original,['idx_nf_q11_ss_cover']),'control_both_cover':(original,list(index_defs)),'final_late_reference':(late,[]),'final_late_cover':(late,list(index_defs))}
    (out/'final-candidates.json').write_text(json.dumps({label:{'sql':q,'active_extra_indexes':names} for label,(q,names) in choices.items()},indent=2))
    for label,(q,names) in choices.items():visibility(names);measure(label,q,'reference167+'+','.join(names),True)
    for i in range(5):
        items=list(choices.items())
        if i%2:items.reverse()
        for label,(q,names) in items:visibility(names);measure(label,q,'reference167+'+','.join(names))
    full={}
    for label in ['final_original','final_late_reference','final_late_cover']:
        q,names=choices[label];visibility(names)
        value=sql(re.sub(r'limit\s+100\s*;', ';',q,flags=re.I));full[label]=value;(out/(label+'.full.out')).write_bytes(value)
        plan(label,q,True)
    assert len(set(full.values()))==1,'Full Q11 output differs'
    checks=json.loads((out/'fixture-validation.json').read_text());assert all(r['exact_match'] for r in checks if not r['label'].startswith('historical_pivot'))
    (out/'validation.json').write_text(json.dumps({'sf4_exact':True,'rows':100,'full_output_exact':True,'full_rows':len(full['final_original'].splitlines()),'fixture_retained_passed':True,'historical_pivot_duplicate_id_rejected':True,'output_sha256':hashlib.sha256((out/'original.out').read_bytes()).hexdigest()},indent=2));visibility([])

if args.mode=='finish':
    from reference_indexes import expected_indexes,actual_indexes,verify_indexes
    expected=expected_indexes();actual,ignored=actual_indexes();owned={(table,name):(1,tuple(cols.split(','))) for name,(table,cols) in index_defs.items()}
    assert set(actual)-set(expected)==set(owned) and all(actual[k]==v for k,v in owned.items())
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE store_sales,web_sales');assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned]},indent=2))
    print('Shared reference restored: 167 visible indexes.',flush=True)

