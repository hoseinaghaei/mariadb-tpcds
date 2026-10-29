"""Controlled Q57 SF4 index and rewrite investigation."""
import argparse, datetime, hashlib, json, pathlib, re, statistics, subprocess, time

p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','indexes','screen','refine','refine2','confirm','fixture','finish']);args=p.parse_args()
out=pathlib.Path('/results/q57-study');out.mkdir(exist_ok=True)
cli=['mariadb','--socket=/data/mysql.sock','-uroot','--batch','--skip-column-names','--raw','tpcds']
preamble="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original=pathlib.Path('/project/queries/mariadb/query57.sql').read_text(encoding='utf-8-sig')
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
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'indexes':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode(),'date_bounds':sql('SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE (d_year=2000 OR (d_year=1999 AND d_moy=12) OR (d_year=2001 AND d_moy=1))').decode()},indent=2))
    plan('original',original)
    pair({'original':original},'reference167')
    plan('original',original,True); print('Baseline and actual plan saved.',flush=True)

index_defs={'idx_nf_q57_catalog_cover':('catalog_sales','cs_sold_date_sk,cs_item_sk,cs_call_center_sk,cs_sales_price'),'idx_nf_q57_item_cover':('item','i_item_sk,i_category,i_brand')}
def visibility(names):
    for name,(table,cols) in index_defs.items():
        if sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}' LIMIT 1").strip():
            sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))
if args.mode=='indexes':
    for name,(table,cols) in index_defs.items():
        print(f'Testing {name} ({cols}): covering catalog or item reads',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        start=time.perf_counter();sql(f'SET SESSION max_statement_time=1800; CREATE INDEX {name} ON {table} ({cols})',1900);sql(f'ANALYZE TABLE {table}')
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'table':table,'columns':cols,'bytes':size,'build_seconds':time.perf_counter()-start},indent=2));visibility([])
    for label,names in [('catalog_cover',['idx_nf_q57_catalog_cover']),('both_cover',list(index_defs))]:
        visibility(names);pair({label:original},label);plan(label,original)
    visibility([])

monthly='''SELECT i_category,i_brand,cc_name,d_year,d_moy,SUM(cs_sales_price) sum_sales
FROM catalog_sales JOIN date_dim ON cs_sold_date_sk=d_date_sk
JOIN item ON cs_item_sk=i_item_sk JOIN call_center ON cs_call_center_sk=cc_call_center_sk
WHERE (d_year=2000 OR (d_year=1999 AND d_moy=12) OR (d_year=2001 AND d_moy=1))
AND i_category IS NOT NULL AND i_brand IS NOT NULL AND cc_name IS NOT NULL
GROUP BY i_category,i_brand,cc_name,d_year,d_moy'''
window_tail='''), scored AS (
SELECT i_brand,d_year,d_moy,AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year) avg_monthly_sales,
sum_sales,LAG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) psum,
LEAD(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) nsum,
LAG(1) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) has_prev,
LEAD(1) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) has_next FROM monthly)
SELECT i_brand,d_year,d_moy,avg_monthly_sales,sum_sales,psum,nsum FROM scored
WHERE d_year=2000 AND avg_monthly_sales>0 AND has_prev=1 AND has_next=1
AND CASE WHEN avg_monthly_sales>0 THEN ABS(sum_sales-avg_monthly_sales)/avg_monthly_sales ELSE NULL END>0.1
ORDER BY sum_sales-avg_monthly_sales,psum LIMIT 100;'''
window='WITH monthly AS ('+monthly+window_tail
window_range=window.replace('WHERE (d_year=2000','WHERE cs_sold_date_sk BETWEEN 2451514 AND 2451941 AND (d_year=2000')
date_first=window_range.replace('SELECT i_category','SELECT /*+ JOIN_PREFIX(date_dim, catalog_sales) */ i_category',1)
preagg='''WITH fact_month AS (
SELECT cs_item_sk,cs_call_center_sk,d_year,d_moy,SUM(cs_sales_price) sales FROM catalog_sales
JOIN date_dim ON cs_sold_date_sk=d_date_sk
WHERE (d_year=2000 OR (d_year=1999 AND d_moy=12) OR (d_year=2001 AND d_moy=1))
GROUP BY cs_item_sk,cs_call_center_sk,d_year,d_moy), monthly AS (
SELECT i_category,i_brand,cc_name,d_year,d_moy,SUM(sales) sum_sales FROM fact_month
JOIN item ON cs_item_sk=i_item_sk JOIN call_center ON cs_call_center_sk=cc_call_center_sk
WHERE i_category IS NOT NULL AND i_brand IS NOT NULL AND cc_name IS NOT NULL
GROUP BY i_category,i_brand,cc_name,d_year,d_moy'''+window_tail
original_range=original.replace('cs_sold_date_sk = d_date_sk','cs_sold_date_sk = d_date_sk AND cs_sold_date_sk BETWEEN 2451514 AND 2451941')
historical=pathlib.Path('/project/queries/optimized/Nafiz/tier5/q57/query57_BEST.sql').read_text(encoding='utf-8-sig')
candidates={'safe_window':window,'window_range':window_range,'date_first':date_first,'preaggregate_keys':preagg,'original_range':original_range,'historical_window':historical}
if args.mode=='screen':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    for profile,names in [('reference167',[]),('catalog_cover',['idx_nf_q57_catalog_cover']),('both_cover',list(index_defs))]:
        visibility(names)
        for label,q in candidates.items():print(f'Testing {profile} {label}: monthly windows / date access / late dimensions',flush=True);measure(profile+'__'+label,q,profile)
    visibility([])

if args.mode=='fixture':
    setup='''CREATE TEMPORARY TABLE item (i_item_sk BIGINT PRIMARY KEY,i_category VARCHAR(20),i_brand VARCHAR(20));
CREATE TEMPORARY TABLE call_center (cc_call_center_sk BIGINT PRIMARY KEY,cc_name VARCHAR(20));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT,d_moy INT);
CREATE TEMPORARY TABLE catalog_sales (cs_item_sk BIGINT,cs_sold_date_sk BIGINT,cs_call_center_sk BIGINT,cs_sales_price DECIMAL(7,2));
INSERT INTO item VALUES (1,'Books','Brand'),(2,'Books','Brand'),(3,NULL,'Null category'),(4,'Books',NULL),(5,'Books','Null center'),(6,'Books','Zero average');
INSERT INTO call_center VALUES (1,'Center'),(2,'Center'),(3,NULL);
INSERT INTO date_dim VALUES (2451514,1999,12),(2451545,2000,1),(2451605,2000,3),(2451636,2000,4),(2451880,2000,12),(2451911,2001,1),(2451484,1999,11),(2451942,2001,2);
INSERT INTO catalog_sales VALUES (1,2451514,1,10),(1,2451545,1,80),(1,2451545,1,20),(2,2451545,2,5),(1,2451605,1,NULL),(1,2451636,1,1),(1,2451880,1,0),(1,2451911,1,20),(1,2451484,1,999),(1,2451942,1,999),(1,2451700,1,999),(999,2451545,1,999),(1,2451545,999,999);
'''
    for item,cc in [(3,1),(4,1),(5,3),(6,1)]:
        values=[0,0,0,0] if item==6 else [10,100,1,20]
        for day,amount in zip([2451514,2451545,2451636,2451911],values):setup+=f'INSERT INTO catalog_sales VALUES ({item},{day},{cc},{amount});\n'
    reference=sql(setup+original);lines=[line.split(b'\t') for line in reference.splitlines()]
    assert len(lines)==3 and any(r[2]==b'1' and r[6]==b'NULL' for r in lines) and any(r[2]==b'4' and r[5]==b'NULL' for r in lines),reference
    checks=[]
    cases=dict(candidates)
    if (out/'refinements.json').exists():cases.update(json.loads((out/'refinements.json').read_text()))
    for label,q in cases.items():
        value=sql(setup+q);same=value==reference
        if label=='historical_window':assert not same,'Historical NULL-neighbor filtering should fail this fixture'
        else:assert same,f'Fixture mismatch {label}: {value!r} vs {reference!r}'
        checks.append({'label':label,'exact_match':same,'reason':'Historical window discards existing neighbors with NULL sales and lacks NULL-key exclusion' if not same else 'Matched original'})
    (out/'nonempty-fixture.sql').write_text(setup+original);(out/'nonempty-fixture.out').write_bytes(reference);(out/'fixture-validation.json').write_text(json.dumps(checks,indent=2))
    print('Fixture passed for safe rewrites; historical NULL-neighbor assumption exposed.',flush=True)

avg_frame=window.replace('AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year)', 'AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year ORDER BY d_moy ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)')
preagg_range=preagg.replace('WHERE (d_year=2000','WHERE cs_sold_date_sk BETWEEN 2451514 AND 2451941 AND (d_year=2000')
preagg_frame=preagg.replace('AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year)', 'AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year ORDER BY d_moy ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)')
refinements={'safe_window':window,'preaggregate_keys':preagg,'preaggregate_range':preagg_range,'aligned_window_frame':avg_frame,'preaggregate_frame':preagg_frame}
if args.mode=='refine':
    (out/'refinements.json').write_text(json.dumps(refinements,indent=2))
    for profile,names in [('reference167',[]),('catalog_cover',['idx_nf_q57_catalog_cover'])]:
        visibility(names);pair({profile+'__repeat_'+label:q for label,q in refinements.items()},profile,3)
        for label,q in refinements.items():plan(profile+'__'+label,q,True)
    visibility([])

if args.mode=='confirm':
    cover=['idx_nf_q57_catalog_cover']
    choices={'final_original':(original,[]),'final_catalog_cover':(original,cover),'final_safe_window':(window,[]),'final_window_cover':(window,cover),'final_preagg_cover':(preagg,cover)}
    (out/'final-candidates.json').write_text(json.dumps({label:{'sql':q,'active_extra_indexes':names} for label,(q,names) in choices.items()},indent=2))
    for label,(q,names) in choices.items():visibility(names);measure(label,q,'reference167+'+','.join(names),True)
    for i in range(5):
        items=list(choices.items())
        if i%2:items.reverse()
        for label,(q,names) in items:visibility(names);measure(label,q,'reference167+'+','.join(names))
    full={}
    for label in ['final_original','final_safe_window','final_preagg_cover']:
        q,names=choices[label];visibility(names)
        complete=re.sub(r'order\s+by\s+sum_sales\s*-\s*avg_monthly_sales\s*,\s*psum\s+limit\s+100\s*;', 'ORDER BY i_brand,d_year,d_moy,avg_monthly_sales,sum_sales,psum,nsum;',q,flags=re.I)
        assert complete!=q
        value=sql(complete);full[label]=value;(out/(label+'.full.out')).write_bytes(value);plan(label,q,True)
    assert len(set(full.values()))==1,'Complete Q57 values/multiplicity differ'
    checks=json.loads((out/'fixture-validation.json').read_text());assert all(r['exact_match'] for r in checks if r['label']!='historical_window')
    (out/'validation.json').write_text(json.dumps({'sf4_ordered_limit100_exact':True,'rows':100,'full_canonical_exact':True,'full_rows':len(full['final_original'].splitlines()),'full_order':'all seven projected columns for tie-independent complete comparison','fixture_retained_passed':True,'historical_null_neighbor_rejected':True,'output_sha256':hashlib.sha256((out/'original.out').read_bytes()).hexdigest()},indent=2));visibility([])

if args.mode=='finish':
    from reference_indexes import expected_indexes,actual_indexes,verify_indexes
    expected=expected_indexes();actual,ignored=actual_indexes();owned={(table,name):(1,tuple(cols.split(','))) for name,(table,cols) in index_defs.items()}
    assert set(actual)-set(expected)==set(owned) and all(actual[k]==v for k,v in owned.items())
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE catalog_sales,item');assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned]},indent=2))
    print('Shared reference restored: 167 visible secondary indexes.',flush=True)

