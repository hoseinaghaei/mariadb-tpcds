"""Controlled Q33 SF4 index and rewrite investigation."""
import argparse, datetime, hashlib, json, pathlib, re, statistics, subprocess, time

p=argparse.ArgumentParser();p.add_argument('mode',choices=['inspect','indexes','screen','refine','refine2','confirm','fixture','finish']);args=p.parse_args()
out=pathlib.Path('/results/q33-study');out.mkdir(exist_ok=True)
cli=['mariadb','--socket=/data/mysql.sock','-uroot','--batch','--skip-column-names','--raw','tpcds']
preamble="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original=pathlib.Path('/project/queries/mariadb/query33.sql').read_text(encoding='utf-8-sig')
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
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'indexes':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode(),'date_bounds':sql('SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year=2000 AND d_moy=7').decode()},indent=2))
    print(plan('original',original),flush=True)
    pair({'original':original},'reference167')
    print(plan('original',original,True),flush=True)

index_defs={'idx_nf_q33_item_cover':('item','i_item_sk,i_manufact_id'),'idx_nf_q33_book_manufact':('item','i_category,i_manufact_id')}
def visibility(names):
    for name,(table,cols) in index_defs.items():
        if sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}' LIMIT 1").strip():
            sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))
if args.mode=='indexes':
    for name,(table,cols) in index_defs.items():
        print(f'Testing {name} ({cols}): covering item/manufacturer access',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        start=time.perf_counter();sql(f'CREATE INDEX {name} ON {table} ({cols})');sql('ANALYZE TABLE item')
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'columns':cols,'build_seconds':time.perf_counter()-start,'bytes':size},indent=2));visibility([])
    for label,names in [('item_cover',['idx_nf_q33_item_cover']),('book_cover',['idx_nf_q33_book_manufact']),('both_cover',list(index_defs))]:
        visibility(names);pair({label:original},label);plan(label,original)
    visibility([])

channels=[('store_sales','ss','ss_addr_sk'),('catalog_sales','cs','cs_bill_addr_sk'),('web_sales','ws','ws_bill_addr_sk')]
date_range=original
for table,prefix,addr in channels:date_range=date_range.replace(f'{prefix}_sold_date_sk         = d_date_sk',f'{prefix}_sold_date_sk = d_date_sk AND {prefix}_sold_date_sk BETWEEN 2451727 AND 2451757')
book_cte="book_manufacturers AS (SELECT DISTINCT i_manufact_id FROM item WHERE i_category='Books')"
branches=[];rawbranches=[];prebranches=[]
for table,prefix,addr in channels:
    common=f'''FROM {table} f JOIN date_dim d ON f.{prefix}_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.{addr}=a.ca_address_sk
WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5'''
    rawbranches.append(f'SELECT f.{prefix}_item_sk AS item_sk,f.{prefix}_ext_sales_price AS sales '+common)
    prebranches.append(f'SELECT f.{prefix}_item_sk AS item_sk,SUM(f.{prefix}_ext_sales_price) AS sales '+common+f' GROUP BY f.{prefix}_item_sk')
    branches.append(f'''SELECT i.i_manufact_id,SUM(f.{prefix}_ext_sales_price) total_sales
FROM {table} f JOIN date_dim d ON f.{prefix}_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.{addr}=a.ca_address_sk JOIN item i ON f.{prefix}_item_sk=i.i_item_sk
JOIN book_manufacturers b ON b.i_manufact_id=i.i_manufact_id
WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5 GROUP BY i.i_manufact_id''')
flat='WITH '+book_cte+', channel_sales AS ('+'\nUNION ALL\n'.join(rawbranches)+''')
SELECT i.i_manufact_id,SUM(f.sales) total_sales FROM channel_sales f
JOIN item i ON f.item_sk=i.i_item_sk JOIN book_manufacturers b ON b.i_manufact_id=i.i_manufact_id
GROUP BY i.i_manufact_id ORDER BY total_sales LIMIT 100;'''
preagg=flat.replace('\nUNION ALL\n'.join(rawbranches),'\nUNION ALL\n'.join(prebranches))
shared='WITH '+book_cte+', channel_totals AS ('+'\nUNION ALL\n'.join(branches)+') SELECT i_manufact_id,SUM(total_sales) total_sales FROM channel_totals GROUP BY i_manufact_id ORDER BY total_sales LIMIT 100;'
late_book='WITH channel_totals AS ('+'\nUNION ALL\n'.join(branches).replace('JOIN book_manufacturers b ON b.i_manufact_id=i.i_manufact_id','')+') SELECT i_manufact_id,SUM(total_sales) total_sales FROM channel_totals WHERE i_manufact_id IN (SELECT i_manufact_id FROM item WHERE i_category=\'Books\') GROUP BY i_manufact_id ORDER BY total_sales LIMIT 100;'
candidates={'date_range':date_range,'shared_books':shared,'union_first':flat,'preaggregate_items':preagg,'late_books':late_book}
if args.mode=='screen':
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    for profile,names in [('reference167',[]),('both_cover',list(index_defs))]:
        visibility(names);pair({profile+'__'+label:q for label,q in candidates.items()},profile)
    visibility([])
    for label,q in candidates.items():plan(label,q)

eligible_flat=flat.replace('WITH '+book_cte+', channel_sales AS (',"WITH "+book_cte+", eligible_items AS (SELECT i.i_item_sk,i.i_manufact_id FROM item i JOIN book_manufacturers b ON b.i_manufact_id=i.i_manufact_id GROUP BY i.i_item_sk,i.i_manufact_id), channel_sales AS (")
eligible_flat=eligible_flat.replace('JOIN item i ON f.item_sk=i.i_item_sk JOIN book_manufacturers b ON b.i_manufact_id=i.i_manufact_id','JOIN eligible_items i ON f.item_sk=i.i_item_sk')
forced_flat=flat.replace('JOIN item i ON','JOIN item i FORCE INDEX (idx_nf_q33_item_cover) ON')
forced_original=original.replace('         item\n where','         item FORCE INDEX (idx_nf_q33_item_cover)\n where')
refinements={'eligible_items':eligible_flat,'forced_union':forced_flat,'forced_original':forced_original,'union_first':flat}
global_items=flat.replace(')\nSELECT i.i_manufact_id,SUM(f.sales)', '), item_sales AS (SELECT item_sk,SUM(sales) sales FROM channel_sales GROUP BY item_sk)\nSELECT i.i_manufact_id,SUM(f.sales)').replace('FROM channel_sales f\nJOIN item','FROM item_sales f\nJOIN item')
refinements.update({'global_item_totals':global_items,'union_no_cache':"SET @q33_cache=@@join_cache_level;SET SESSION join_cache_level=0;\n"+flat+'\nSET SESSION join_cache_level=@q33_cache;'})
if args.mode=='refine':
    (out/'refinements.json').write_text(json.dumps(refinements,indent=2))
    for profile,names in [('item_cover',['idx_nf_q33_item_cover']),('both_cover',list(index_defs))]:
        visibility(names);pair({profile+'__'+k:v for k,v in refinements.items()},profile,5)
        for k,q in refinements.items():plan(profile+'__'+k,q,True)
    visibility([]);pair({'reference__eligible_items':eligible_flat,'reference__union_first':flat},'reference167',5)

if args.mode=='refine2':
    (out/'refinements.json').write_text(json.dumps(refinements,indent=2))
    visibility([]);pair({'global_item_totals':global_items,'union_no_cache':refinements['union_no_cache'],'union_reference':flat},'reference167',7)
    plan('global_item_totals',global_items,True)

if args.mode=='fixture':
    setup='''CREATE TEMPORARY TABLE item (i_item_sk BIGINT PRIMARY KEY,i_manufact_id INT,i_category VARCHAR(20),KEY idx_nf_q33_item_cover(i_item_sk,i_manufact_id));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT,d_moy INT);
CREATE TEMPORARY TABLE customer_address (ca_address_sk BIGINT PRIMARY KEY,ca_gmt_offset DECIMAL(5,2));
CREATE TEMPORARY TABLE store_sales (ss_item_sk BIGINT,ss_sold_date_sk BIGINT,ss_addr_sk BIGINT,ss_ext_sales_price DECIMAL(7,2));
CREATE TEMPORARY TABLE catalog_sales (cs_item_sk BIGINT,cs_sold_date_sk BIGINT,cs_bill_addr_sk BIGINT,cs_ext_sales_price DECIMAL(7,2));
CREATE TEMPORARY TABLE web_sales (ws_item_sk BIGINT,ws_sold_date_sk BIGINT,ws_bill_addr_sk BIGINT,ws_ext_sales_price DECIMAL(7,2));
INSERT INTO item VALUES (1,10,'Books'),(2,10,'Music'),(3,10,'Books'),(4,20,'Music'),(5,30,'Books'),(6,NULL,'Books'),(7,40,'Books'),(8,50,'Books');
INSERT INTO date_dim VALUES (2451727,2000,7),(2451757,2000,7),(2451726,2000,6),(2451758,2000,8),(999,2001,7);
INSERT INTO customer_address VALUES (1,-5),(2,-4),(3,NULL);
INSERT INTO store_sales VALUES (1,2451727,1,10.00),(2,2451727,1,5.00),(2,2451727,1,5.00),(4,2451727,1,999.00),(5,2451727,1,NULL),(6,2451727,1,999.00),(7,2451727,1,1.00),(8,2451727,1,0.00),(1,2451726,1,999.00),(1,2451727,2,999.00),(1,2451730,1,999.00),(999,2451727,1,999.00),(1,2451727,999,999.00);
INSERT INTO catalog_sales VALUES (2,2451757,1,7.00),(3,2451757,1,2.00),(5,2451757,1,NULL),(7,2451757,1,-1.00),(1,2451758,1,999.00),(1,NULL,1,999.00);
INSERT INTO web_sales VALUES (1,2451727,1,-3.00),(7,2451727,1,2.00),(1,999,1,999.00),(1,2451727,3,999.00);
'''
    reference=sql(setup+original);assert reference==b'30\tNULL\n50\t0.00\n40\t2.00\n10\t26.00\n',reference
    checks=[]
    for label,q in {**candidates,**refinements}.items():
        result=sql(setup+q);assert result==reference,f'Fixture mismatch {label}: {result!r}'
        checks.append({'label':label,'exact_match':True,'rows':4,'sha256':hashlib.sha256(result).hexdigest()})
    (out/'nonempty-fixture.sql').write_text(setup+original);(out/'nonempty-fixture.out').write_bytes(reference);(out/'fixture-validation.json').write_text(json.dumps(checks,indent=2))
    print('All Q33 candidate fixtures passed: manufacturer membership, non-Book products, duplicate sales, NULLs, missing joins, dates and all channels.',flush=True)

if args.mode=='confirm':
    visibility([])
    choices={'final_original':original,'final_late_books':late_book,'final_union_first':flat}
    (out/'final-candidates.json').write_text(json.dumps(choices,indent=2))
    pair(choices,'reference167',7)
    all_results={}
    for label,q in choices.items():
        plan(label,q,True)
        full=re.sub(r'order\s+by\s+total_sales\s+limit\s+100\s*;', 'ORDER BY i_manufact_id;',q,flags=re.I)
        assert full!=q
        value=sql(full);all_results[label]=value;(out/(label+'.full.out')).write_bytes(value)
    assert len(set(all_results.values()))==1,'Full manufacturer totals differ'
    (out/'validation.json').write_text(json.dumps({'sf4_exact_ordered_limit100':True,'rows':100,'full_manufacturer_totals_exact':True,'full_rows':len(all_results['final_original'].splitlines()),'full_output_order':'i_manufact_id for complete comparison','output_sha256':hashlib.sha256((out/'original.out').read_bytes()).hexdigest(),'nonempty_fixture_passed':True},indent=2))

if args.mode=='finish':
    from reference_indexes import expected_indexes,actual_indexes,verify_indexes
    expected=expected_indexes();actual,ignored=actual_indexes();owned={(table,name):(1,tuple(cols.split(','))) for name,(table,cols) in index_defs.items()}
    assert set(actual)-set(expected)==set(owned) and all(actual[k]==v for k,v in owned.items())
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE item');assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned]},indent=2))
    print('Shared reference profile restored; Q33 BEST needs no additional indexes.',flush=True)

