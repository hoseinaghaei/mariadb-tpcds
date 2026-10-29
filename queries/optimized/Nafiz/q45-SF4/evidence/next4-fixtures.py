"""Session-local semantic fixtures; never modifies warehouse rows."""
import collections,hashlib,json,pathlib,re,subprocess,sys
requested=[int(sys.argv[1])] if len(sys.argv)>1 else [24,34,36,45]
sys.path.insert(0,'/setup')
sys.argv=['next4-sf4.py','library']
import importlib.util
spec=importlib.util.spec_from_file_location('study','/setup/next4-sf4.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def value(x):
    if x is None:return 'NULL'
    if isinstance(x,(int,float)):return str(x)
    return "'"+str(x).replace("'","''")+"'"
def insert(t,cols,rows):return 'INSERT INTO '+t+' ('+cols+') VALUES '+','.join('('+','.join(map(value,r))+')' for r in rows)+';\n' if rows else ''
tables={24:['store_sales','store_returns','store','item','customer','customer_address'],34:['store_sales','date_dim','store','household_demographics','customer'],36:['store_sales','date_dim','item','store'],45:['web_sales','customer','customer_address','date_dim','item']}
def fixture_sql(q,s):
    for t in sorted(tables[q],key=len,reverse=True):s=re.sub(r'\b'+t+r'\b','nf_tmp_'+t,s,flags=re.I)
    return s
def init(q):return '\n'.join(f'CREATE TEMPORARY TABLE nf_tmp_{t} LIKE tpcds.{t};' for t in tables[q])+'\n'
def data24():
    s=insert('store','s_store_sk,s_store_id,s_store_name,s_state,s_zip,s_market_id',[(1,'S1','Twin','TN','12345',10),(2,'S2','Twin','CA','12345',10),(3,'S3','Other','TN','12345',9)])
    s+=insert('customer_address','ca_address_sk,ca_address_id,ca_state,ca_zip,ca_country',[(1,'A1','TN','12345','United States'),(2,'A2','CA','12345','United States'),(3,'A3','TN','99999','United States')])
    s+=insert('customer','c_customer_sk,c_customer_id,c_last_name,c_first_name,c_current_addr_sk,c_birth_country',[(1,'C1','Alpha','A',1,'FRANCE'),(2,'C2','Alpha','A',2,'FRANCE'),(3,'C3','Low','B',1,'FRANCE'),(4,'C4','Excluded','X',1,'UNITED STATES'),(5,'C5','Null','N',1,None),(6,'C6','Wrongzip','W',3,'FRANCE')])
    s+=insert('item','i_item_sk,i_item_id,i_color,i_current_price,i_manager_id,i_units,i_size',[(1,'I1','sky',10,1,'Each','S'),(2,'I2','sky',10,1,'Each','S'),(3,'I3','slate',20,2,'Each','M'),(4,'I4','red',30,3,'Each','L'),(5,'I5','sky',None,None,None,None)])
    facts=[(1,1,1,1,600),(2,2,1,1,400),(1,3,2,2,100),(3,4,1,1,500),(4,5,1,1,1000),(1,6,3,1,10),(5,7,3,1,None),(1,8,4,1,10000),(1,9,5,1,10000),(1,10,6,1,10000),(1,11,1,3,10000),(99,12,1,1,10000),(1,13,99,1,10000),(1,14,1,99,10000),(1,15,1,1,30000)]
    s+=insert('store_sales','ss_item_sk,ss_ticket_number,ss_customer_sk,ss_store_sk,ss_ext_sales_price',facts)
    s+=insert('store_returns','sr_item_sk,sr_ticket_number',[(i,t) for i,t,c,st,p in facts if t!=15])
    return s
def data34():
    s=insert('date_dim','d_date_sk,d_date_id,d_date,d_year,d_dom',[(2450815,'D1','1998-01-01',1998,1),(2450839,'D2','1998-01-25',1998,25),(2450843,'D3','1998-01-29',1998,29),(2451910,'D4','2000-12-31',2000,28),(2452276,'D5','2002-01-01',2002,1)])
    s+=insert('store','s_store_sk,s_store_id,s_county',[(1,'S1','Williamson County'),(2,'S2','Other')])
    s+=insert('household_demographics','hd_demo_sk,hd_buy_potential,hd_vehicle_count,hd_dep_count',[(1,'>10000',2,3),(2,'Unknown',5,6),(3,'Unknown',0,5),(4,'Other',1,5),(5,'Unknown',None,5),(6,'Unknown',1,None)])
    s+=insert('customer','c_customer_sk,c_customer_id,c_last_name,c_first_name,c_salutation,c_preferred_cust_flag',[(1,'C1','Alpha','A','Mr.','Y'),(2,'C2','Beta','B','Ms.','N')])
    rows=[];sk=1
    for ticket,count,cust,date,hd,store in [(1,14,1,2450815,1,1),(2,15,1,2450815,1,1),(3,20,2,2450839,1,1),(4,21,2,2450815,1,1),(5,15,1,2450843,1,1),(6,15,1,2450815,2,1),(7,15,1,2450815,3,1),(8,15,1,2450815,4,1),(9,15,1,2450815,1,2),(10,15,99,2450815,1,1),(11,15,1,2450816,1,1),(12,15,1,2452276,1,1),(13,15,1,2451910,1,1),(14,15,1,2450815,5,1),(15,15,1,2450815,6,1)]:
        for j in range(count):rows.append((sk,ticket,cust,date,hd,store));sk+=1
    # Same ticket but different customers must stay separate groups.
    for c in [1,2]:
        for j in range(15):rows.append((sk,20,c,2450815,1,1));sk+=1
    return s+insert('store_sales','ss_item_sk,ss_ticket_number,ss_customer_sk,ss_sold_date_sk,ss_hdemo_sk,ss_store_sk',rows)
def data36():
    s=insert('date_dim','d_date_sk,d_date_id,d_date,d_year',[(2451911,'D1','2001-01-01',2001),(2452275,'D2','2001-12-31',2001),(2452276,'D3','2002-01-01',2002)])
    s+=insert('store','s_store_sk,s_store_id,s_state',[(1,'S1','TN'),(2,'S2','CA')])
    s+=insert('item','i_item_sk,i_item_id,i_category,i_class',[(1,'I1','A','One'),(2,'I2','A',None),(3,'I3',None,'One'),(4,'I4',None,None),(5,'I5','B','Two'),(6,'I6','B','Three'),(7,'I7','C','Only')])
    rows=[(1,1,2451911,1,10,100),(1,2,2452275,1,20,100),(2,3,2451911,1,5,100),(3,4,2451911,1,5,50),(4,5,2451911,1,None,30),(5,6,2451911,1,0,0),(6,7,2451911,1,None,None),(7,8,2451911,1,7,None),(1,9,2452276,1,999,1000),(1,10,2451911,2,999,1000),(99,11,2451911,1,999,1000),(1,12,2451912,1,999,1000),(1,13,2451911,99,999,1000)]
    return s+insert('store_sales','ss_item_sk,ss_ticket_number,ss_sold_date_sk,ss_store_sk,ss_net_profit,ss_ext_sales_price',rows)
def data45():
    s=insert('date_dim','d_date_sk,d_date_id,d_date,d_year,d_qoy',[(2451911,'D1','2001-01-01',2001,1),(2452001,'D2','2001-04-01',2001,1),(2452002,'D3','2001-04-02',2001,2)])
    s+=insert('item','i_item_sk,i_item_id',[(2,'BUSINESS'),(3,'BUSINESS'),(100,'BUSINESS'),(101,'OTHER'),(102,'OTHER')])
    s+=insert('customer_address','ca_address_sk,ca_address_id,ca_zip,ca_county',[(1,'A1','85669','Alpha'),(2,'A2','99999','Beta'),(3,'A3',None,'NullZIP'),(4,'A4','85669-1234','Suffix'),(5,'A5','12345','Other'),(6,'A6','86197',None)])
    s+=insert('customer','c_customer_sk,c_customer_id,c_current_addr_sk',[(1,'C1',1),(2,'C2',2),(3,'C3',3),(4,'C4',4),(5,'C5',5),(6,'C6',99),(7,'C7',6)])
    facts=[(100,1,1,2451911,10),(101,2,1,2451911,20),(100,3,2,2451911,30),(100,4,3,2451911,40),(101,5,4,2452001,50),(101,6,5,2451911,1000),(101,7,3,2451911,1000),(100,8,2,2452002,1000),(100,9,2,2451912,1000),(999,10,1,2451911,1000),(100,11,99,2451911,1000),(100,12,6,2451911,1000),(102,13,1,2451911,None),(100,14,2,2452001,5)]
    facts.append((101,15,7,2451911,None))
    return s+insert('web_sales','ws_item_sk,ws_order_number,ws_bill_customer_sk,ws_sold_date_sk,ws_sales_price',facts)

reports={}
for q,make in [(24,data24),(34,data34),(36,data36),(45,data45)]:
    if q not in requested:continue
    d=m.out/f'q{q}';candidates=json.loads((d/'candidate-catalog.json').read_text())
    cases={'empty':'','edge_cases':make()}
    if q==24:cases['all_null_metrics']=make()+'UPDATE store_sales SET ss_ext_sales_price=NULL;'
    if q==36:cases['all_null_metrics']=make()+'UPDATE store_sales SET ss_net_profit=NULL,ss_ext_sales_price=NULL;'
    result=[]
    for name,body in cases.items():
        setup=init(q)+fixture_sql(q,body)
        (d/f'fixture-{name}.sql').write_text(setup)
        originals=[m.sql(setup+fixture_sql(q,part)) for part in m.split(candidates[0]['sql'])]
        for n,b in enumerate(originals,1):(d/f'fixture-{name}-original-part{n}.out').write_bytes(b)
        for c in candidates:
            # Rejected semantic candidates must be recorded, not published.
            try:
                parts=[m.sql(setup+fixture_sql(q,part)) for part in m.split(c['sql'])]
                if q==36:
                    match=len(parts)==len(originals) and all(collections.Counter(b.splitlines())==collections.Counter(a.splitlines()) for a,b in zip(originals,parts))
                else:match=parts==originals
                result.append({'case':name,'label':c['label'],'match':match,'rows_by_part':[len(b.splitlines()) for b in parts],'comparison':'full row multiset for tied Q36 order' if q==36 else 'exact ordered bytes per result set'})
            except Exception as e:result.append({'case':name,'label':c['label'],'match':False,'error':str(e)})
        print(f'Q{q} fixture {name}: checked {len(candidates)} conditions',flush=True)
    dump=m.dump;dump(d/'fixture-validation.json',result);reports[str(q)]=result
m.dump(m.out/('fixture-summary.json' if len(requested)==4 else f'fixture-summary-q{requested[0]}.json'),reports)
if len(requested)!=4:
    combined=json.loads((m.out/'fixture-summary.json').read_text()) if (m.out/'fixture-summary.json').exists() else {}
    combined.update(reports);m.dump(m.out/'fixture-summary.json',combined)
for q in [36,45]:
    if q not in requested:continue
    d=m.out/f'q{q}';candidates=json.loads((d/'final-candidates.json').read_text());baseline=(m.stage/f'q{q}/original.sql').read_text()
    def unlimited(s):return re.sub(r'\s+LIMIT\s+100\s*;?\s*$',';',s,flags=re.I)
    original=unlimited(baseline);expected=m.sql(original);(d/'unlimited-original.sql').write_text(original);(d/'unlimited-original.out').write_bytes(expected)
    checks=[];cache={m.clean(original):expected}
    for c in candidates:
        s=unlimited(c['sql']);key=m.clean(s);b=cache.get(key)
        if b is None:b=m.sql(s);cache[key]=b
        same=collections.Counter(expected.splitlines())==collections.Counter(b.splitlines())
        checks.append({'label':c['label'],'rows':len(b.splitlines()),'match':same,'comparison':'complete row multiset, including hierarchy level and rank' if q==36 else 'complete row multiset'})
        (d/('unlimited-'+c['label']+'.sql')).write_text(s);(d/('unlimited-'+c['label']+'.out')).write_bytes(b)
        print(f'Q{q} full result: {c["label"]}, {len(b.splitlines())} rows, match={same}',flush=True)
    m.dump(d/'unlimited-validation.json',checks)
m.verify()
print('All session-local fixture tests recorded.',flush=True)
