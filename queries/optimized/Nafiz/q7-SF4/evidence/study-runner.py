"""Q7 SF4 controlled experiments; invoked inside the prepared Docker container."""
import argparse, datetime, hashlib, json, pathlib, statistics, subprocess, time

P = argparse.ArgumentParser()
P.add_argument('mode', choices=['inspect', 'indexes', 'itemindex', 'screen', 'refscreen', 'itemscreen', 'confirm', 'finish'])
P.add_argument('--output', default='/results/q7-study')
args = P.parse_args()
out = pathlib.Path(args.output); out.mkdir(parents=True, exist_ok=True)
cli = ['mariadb', '--socket=/data/mysql.sock', '-uroot', '--batch', '--skip-column-names', '--raw', 'tpcds']
preamble = "SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT'); SET SESSION max_statement_time=120;\n"
original = pathlib.Path('/project/queries/mariadb/query7.sql').read_text()

def sql(text, timeout=150):
    p = subprocess.run(cli, input=(preamble+text).encode(), capture_output=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError(p.stderr.decode())
    return p.stdout

def plan(label, query, analyze=False):
    value = sql(('ANALYZE' if analyze else 'EXPLAIN')+' FORMAT=JSON '+query)
    (out/(label+('.analyze.json' if analyze else '.explain.json'))).write_bytes(value)
    return value.decode()

records = json.loads((out/'runs.json').read_text()) if (out/'runs.json').exists() else []
def measure(label, query, profile, warmup=False):
    start=time.perf_counter(); value=sql(query); elapsed=time.perf_counter()-start
    reference=out/'original.out'
    if not reference.exists(): reference.write_bytes(value)
    assert value == reference.read_bytes(), f'Result mismatch: {label}'
    row={'label':label,'profile':profile,'warmup':warmup,'seconds':elapsed,'output_sha256':hashlib.sha256(value).hexdigest(),'sql_sha256':hashlib.sha256(query.encode()).hexdigest(),'rows':len(value.splitlines())}
    records.append(row); (out/'runs.json').write_text(json.dumps(records,indent=2))
    print(f'{label}: {elapsed:.6f}s, {row["rows"]} rows, EXACT MATCH'+(' (warmup)' if warmup else ''),flush=True)
    return elapsed

def pair(candidates, profile, repeats=3):
    for label, query in candidates.items(): measure(label,query,profile,True)
    for i in range(repeats):
        items=list(candidates.items())
        if i%2: items.reverse()
        for label,query in items: measure(label,query,profile)

if args.mode=='inspect':
    from reference_indexes import verify_indexes
    assert verify_indexes()==167
    assert sql('SELECT @@innodb_buffer_pool_size').strip()==b'8589934592'
    assert pathlib.Path('/data/tpcds-data/.scale').read_text().strip()=='4:10'
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    (out/'metadata.json').write_text(json.dumps({'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scale':4,'seed':10,'settings':sql('SHOW VARIABLES').decode(),'indexes_before':sql("SELECT table_name,index_name,seq_in_index,column_name,ignored FROM information_schema.statistics WHERE table_schema='tpcds' ORDER BY table_name,index_name,seq_in_index").decode()},indent=2))
    print(plan('original',original),flush=True)
    pair({'original':original},'reference167')
    print(plan('original',original,True),flush=True)

index_defs = {
 'idx_nf_q7_demo_cover': 'ss_cdemo_sk,ss_sold_date_sk,ss_item_sk,ss_promo_sk,ss_quantity,ss_list_price,ss_coupon_amt,ss_sales_price',
 'idx_nf_q7_date_cover': 'ss_sold_date_sk,ss_cdemo_sk,ss_item_sk,ss_promo_sk,ss_quantity,ss_list_price,ss_coupon_amt,ss_sales_price',
}
if args.mode=='indexes':
    for name, columns in index_defs.items():
        print(f'Testing {name}: covering sales index, column order {columns}',flush=True)
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='store_sales' AND index_name='{name}'").strip()
        started=time.perf_counter()
        sql(f'SET SESSION max_statement_time=1800; CREATE INDEX {name} ON store_sales ({columns})',1900)
        build_seconds=time.perf_counter()-started
        sql('ANALYZE TABLE store_sales')
        size=sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='store_sales' AND index_name='{name}' AND stat_name='size'").decode().strip()
        (out/(name+'.json')).write_text(json.dumps({'columns':columns,'build_seconds':build_seconds,'bytes':int(size)},indent=2))
        plan(name,original)
        pair({name:original},name)
        sql(f'ALTER TABLE store_sales ALTER INDEX {name} IGNORED')
    pair({'original_recheck':original},'reference167_extra_ignored')

range_query=original.replace('d_year = 1998','d_year = 1998 AND ss_sold_date_sk BETWEEN 2450815 AND 2451179')
no_date=range_query.replace('date_dim, ','').replace('ss_sold_date_sk = d_date_sk and','').replace('d_year = 1998 AND ','')
itemfirst=range_query.replace('select ', 'select STRAIGHT_JOIN ',1).replace('store_sales, customer_demographics, date_dim, item, promotion','item FORCE INDEX (idx_nf_q7_item_id), store_sales FORCE INDEX (idx_nf_q7_item_cover), customer_demographics, date_dim, promotion')
index_defs['idx_nf_q7_item_cover']='ss_item_sk,ss_sold_date_sk,ss_cdemo_sk,ss_promo_sk,ss_quantity,ss_list_price,ss_coupon_amt,ss_sales_price'

if args.mode=='itemindex':
    print('Testing ordered item access: LIMIT 100 may stop after 100 complete item groups.',flush=True)
    for table,name,cols in [('item','idx_nf_q7_item_id','i_item_id'),('store_sales','idx_nf_q7_item_cover',index_defs['idx_nf_q7_item_cover'])]:
        assert not sql(f"SELECT 1 FROM information_schema.statistics WHERE table_schema='tpcds' AND table_name='{table}' AND index_name='{name}'").strip()
        started=time.perf_counter(); sql(f'SET SESSION max_statement_time=1800; CREATE INDEX {name} ON {table} ({cols})',1900)
        size=int(sql(f"SELECT stat_value*@@innodb_page_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' AND table_name='{table}' AND index_name='{name}' AND stat_name='size'").strip())
        (out/(name+'.json')).write_text(json.dumps({'columns':cols,'build_seconds':time.perf_counter()-started,'bytes':size},indent=2))
        sql(f'ANALYZE TABLE {table}')
    pair({'item_index_only':original,'item_ordered_range':itemfirst},'item_cover_and_item_id')
    print(plan('item_ordered_range',itemfirst,True),flush=True)
    sql('ALTER TABLE store_sales ALTER INDEX idx_nf_q7_item_cover IGNORED; ALTER TABLE item ALTER INDEX idx_nf_q7_item_id IGNORED')

if args.mode=='screen':
    sql('ALTER TABLE store_sales ALTER INDEX idx_nf_q7_demo_cover NOT IGNORED')
    candidates={
      'index_only':original,
      'date_range':range_query,
      'no_date_join':no_date,
      'range_no_bka':'SET SESSION join_cache_level=0;\n'+range_query,
      'range_demo_first':range_query.replace('select ', 'select STRAIGHT_JOIN ',1).replace('store_sales, customer_demographics, date_dim, item, promotion','customer_demographics, store_sales, date_dim, promotion, item'),
      'semijoin': '''SELECT i_item_id, AVG(ss_quantity) agg1, AVG(ss_list_price) agg2, AVG(ss_coupon_amt) agg3, AVG(ss_sales_price) agg4
FROM store_sales JOIN item ON ss_item_sk=i_item_sk
WHERE ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year=1998)
AND ss_sold_date_sk BETWEEN 2450815 AND 2451179
AND ss_cdemo_sk IN (SELECT cd_demo_sk FROM customer_demographics WHERE cd_gender='F' AND cd_marital_status='S' AND cd_education_status='Unknown')
AND ss_promo_sk IN (SELECT p_promo_sk FROM promotion WHERE p_channel_email='N' OR p_channel_event='N')
GROUP BY i_item_id ORDER BY i_item_id LIMIT 100;''',
    }
    (out/'candidates.json').write_text(json.dumps(candidates,indent=2))
    pair(candidates,'demo_cover',3)
    for label,query in candidates.items():
        if not query.startswith('SET'): plan(label,query)

def visibility(names):
    for table,name in [('store_sales',n) for n in index_defs]+[('item','idx_nf_q7_item_id')]:
        sql(f'ALTER TABLE {table} ALTER INDEX {name} '+('NOT IGNORED' if name in names else 'IGNORED'))

if args.mode=='refscreen':
    visibility([])
    candidates={'reference_range':range_query,
                'previous_sf1_best':pathlib.Path('/project/queries/optimized/Nafiz/tier4/q7/query7_BEST.sql').read_text(encoding='utf-8-sig')}
    pair(candidates,'reference167_extra_ignored')
    for label,q in candidates.items(): plan(label,q)

if args.mode=='finish':
    from reference_indexes import expected_indexes, actual_indexes, verify_indexes
    expected=expected_indexes(); actual,ignored=actual_indexes()
    owned={('store_sales',name):(1,tuple(columns.split(','))) for name,columns in index_defs.items()}
    owned[('item','idx_nf_q7_item_id')]=(1,('i_item_id',))
    assert set(actual)-set(expected)==set(owned), 'Unexpected experimental indexes; refusing cleanup'
    assert all(actual[k]==v for k,v in owned.items()), 'Experiment index definitions changed'
    assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    for table,name in owned:
        print(f'Removing experiment-owned index {table}.{name}; preserving every reference index',flush=True)
        sql(f'DROP INDEX {name} ON {table}')
    sql('ANALYZE TABLE store_sales,item')
    assert verify_indexes()==167
    (out/'restoration.json').write_text(json.dumps({'reference_secondary_indexes':167,'ignored_indexes':0,'removed_only_experiment_owned_indexes':[list(k) for k in owned],'completed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2))
    print('Shared reference profile restored: 167 secondary indexes, none ignored.',flush=True)

if args.mode=='itemscreen':
    visibility(['idx_nf_q7_item_cover','idx_nf_q7_item_id'])
    candidates={
      'ordered_no_range':itemfirst.replace(' AND ss_sold_date_sk BETWEEN 2450815 AND 2451179',''),
      'ordered_range':itemfirst,
      'ordered_no_date':itemfirst.replace('date_dim, ','').replace('ss_sold_date_sk = d_date_sk and','').replace('d_year = 1998 AND ',''),
      'ordered_no_force':itemfirst.replace(' FORCE INDEX (idx_nf_q7_item_cover)','').replace(' FORCE INDEX (idx_nf_q7_item_id)',''),
      'ordered_no_straight':itemfirst.replace('STRAIGHT_JOIN ',''),
      'ordered_no_bka':'SET SESSION join_cache_level=0;\n'+itemfirst,
      'ordered_promo_first':itemfirst.replace('customer_demographics, date_dim, promotion','promotion, customer_demographics, date_dim'),
    }
    (out/'item-candidates.json').write_text(json.dumps(candidates,indent=2))
    pair(candidates,'item_cover_and_item_id',5)
    for label,q in candidates.items():
        if not q.startswith('SET'): plan(label,q)

if args.mode=='confirm':
    choices={
      'final_original':(original,[]),
      'final_range':(range_query,[]),
      'final_demo_cover':(original,['idx_nf_q7_demo_cover']),
      'final_ordered':(itemfirst.replace(' AND ss_sold_date_sk BETWEEN 2450815 AND 2451179',''),['idx_nf_q7_item_cover','idx_nf_q7_item_id']),
      'final_ordered_range':(itemfirst,['idx_nf_q7_item_cover','idx_nf_q7_item_id']),
      'control_original_item_profile':(original,['idx_nf_q7_item_cover','idx_nf_q7_item_id']),
    }
    (out/'final-candidates.json').write_text(json.dumps({k:{'sql':v[0],'active_extra_indexes':v[1]} for k,v in choices.items()},indent=2))
    for label,(q,names) in choices.items():
        visibility(names); print(f'Confirming {label}, active experimental indexes: {names}',flush=True)
        measure(label,q,'reference167+'+','.join(names),True)
    for i in range(5):
        items=list(choices.items())
        if i%2: items.reverse()
        for label,(q,names) in items:
            visibility(names); measure(label,q,'reference167+'+','.join(names))
    visibility(['idx_nf_q7_item_cover','idx_nf_q7_item_id'])
    for label in ['final_ordered','final_ordered_range','control_original_item_profile']:
        plan(label,choices[label][0],True)
    # Complete group results as well as the original ordered LIMIT 100.
    full_outputs={}
    for label in ['final_original','final_ordered_range']:
        q=choices[label][0].replace('limit 100','').replace('LIMIT 100','')
        full_outputs[label]=sql(q)
        (out/(label+'.full.out')).write_bytes(full_outputs[label])
    assert len(set(full_outputs.values()))==1, 'Full group output mismatch'
    (out/'validation.json').write_text(json.dumps({'limit100_exact':True,'full_group_exact':True,'full_group_rows':len(full_outputs['final_original'].splitlines()),'full_group_sha256':hashlib.sha256(full_outputs['final_original']).hexdigest()},indent=2))
    visibility([])
