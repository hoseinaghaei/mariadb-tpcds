"""Prepare query-specific candidates; no database actions or invented timings."""
import json,pathlib,re
root=pathlib.Path(__file__).resolve().parents[2];stage=root/'windows/docker/next4-input'
for q in [24,34,36,45]:
    d=stage/f'q{q}';original=(d/'original.sql').read_text();candidates=[]
    def add(label,method,sql,indexes=(),reason=''):
        candidates.append({'label':label,'method':method,'sql':sql,'indexes':list(indexes),'reason':reason})
    definitions=[]
    def idx(name,table,columns):definitions.append({'name':name,'table':table,'columns':columns})
    add('original','Original',original)
    if q==24:
        idx('idx_nf_q24_zip','customer_address','ca_zip')
        idx('idx_nf_q24_cust_store_cover','store_sales','ss_customer_sk,ss_store_sk,ss_ext_sales_price')
        names=[x['name'] for x in definitions]
        add('index_only','ZIP/customer covering',original,names,'Test index access on unchanged original SQL.')
        oldfrom='from store_sales\n    ,store_returns\n    ,store\n    ,item\n    ,customer\n    ,customer_address'
        joins='''FROM store
STRAIGHT_JOIN customer_address ON s_zip=ca_zip
STRAIGHT_JOIN customer ON c_current_addr_sk=ca_address_sk
STRAIGHT_JOIN store_sales ON ss_customer_sk=c_customer_sk AND ss_store_sk=s_store_sk
STRAIGHT_JOIN store_returns ON ss_ticket_number=sr_ticket_number AND ss_item_sk=sr_item_sk
STRAIGHT_JOIN item ON ss_item_sk=i_item_sk'''
        zipfirst=original.replace(oldfrom,joins);assert zipfirst!=original and zipfirst.count('STRAIGHT_JOIN')==10
        add('zip_first','Store ZIP first',zipfirst,reason='Begin with the market/ZIP/address/customer restrictions before fact lookup; retain all joins and both AVG thresholds.')
        add('zip_cover','ZIP first + cover',zipfirst,names,'Use ZIP lookup and covering customer/store sales lookup with the same join-order rewrite.')
        def windowize(s):
            parts=s.split(';');result=[]
            for p in parts:
                if not p.strip():continue
                m=re.search(r'\)\s*select c_last_name',p,re.I);assert m
                cte=p[:m.start()+1];tail=p[m.end()-len('select c_last_name'):]
                tail=re.sub(r'\(select 0\.05\*avg\(netpaid\)\s+from ssales\)', 'MAX(threshold)',tail,flags=re.I)
                tail=tail.replace('from ssales','from with_threshold')
                assert 'MAX(threshold)' in tail
                result.append(cte+', with_threshold AS (SELECT ssales.*,0.05*AVG(netpaid) OVER () threshold FROM ssales)\n'+tail)
            return ';\n'.join(result)+';'
        add('window_once','Single threshold materialization',windowize(original),reason='Compute the all-colour grouped average with a window before either outer colour filter.')
        add('zip_window','ZIP first + window',windowize(zipfirst),reason='Combine early ZIP filtering with one grouped CTE per result set.')
        add('zip_window_cover','ZIP/window + cover',windowize(zipfirst),names,'Combine both independently validated rewrites with optional covering indexes.')
    elif q==34:
        idx('idx_nf_q34_hd_date_cover','store_sales','ss_hdemo_sk,ss_sold_date_sk,ss_store_sk,ss_customer_sk')
        idx('idx_nf_q34_date_hd_cover','store_sales','ss_sold_date_sk,ss_hdemo_sk,ss_store_sk,ss_customer_sk')
        hd,dt=[x['name'] for x in definitions]
        bounded=original.replace('and date_dim.d_year in','and store_sales.ss_sold_date_sk BETWEEN 2450815 AND 2451910\n    and date_dim.d_year in')
        bounded=re.sub(r"store.s_county in \([^)]*\)","store.s_county='Williamson County'",bounded,flags=re.S)
        bounded=bounded.replace("(household_demographics.hd_buy_potential = '>10000' or\n         household_demographics.hd_buy_potential = 'Unknown')","household_demographics.hd_buy_potential IN ('>10000','Unknown')")
        add('bounds','Date bounds + simplification',bounded,reason='Retain date_dim and exact original ratio CASE; simplify duplicate county and buy-potential predicates.')
        add('no_split','Materialize ticket groups once',"SET STATEMENT optimizer_switch='split_materialized=off' FOR "+bounded,reason='Test disabling split materialization for this statement only, avoiding a possible per-customer derived execution.')
        datejoins='FROM date_dim STRAIGHT_JOIN store_sales ON ss_sold_date_sk=d_date_sk STRAIGHT_JOIN household_demographics ON ss_hdemo_sk=hd_demo_sk STRAIGHT_JOIN store ON ss_store_sk=s_store_sk'
        hdjoins='FROM household_demographics STRAIGHT_JOIN store_sales ON ss_hdemo_sk=hd_demo_sk STRAIGHT_JOIN date_dim ON ss_sold_date_sk=d_date_sk STRAIGHT_JOIN store ON ss_store_sk=s_store_sk'
        datefirst=bounded.replace('from store_sales,date_dim,store,household_demographics',datejoins)
        hdfirst=bounded.replace('from store_sales,date_dim,store,household_demographics',hdjoins)
        add('date_first','Date-first ticket groups',datefirst,reason='Drive from the qualifying days rather than scanning all sales.')
        add('hd_first','Household-first groups',hdfirst,reason='Filter the 1040 qualifying household profiles before sales access.')
        add('hd_index','Household covering',original,[hd]);add('date_index','Date covering',original,[dt])
        add('hd_cover','Household first + cover',hdfirst,[hd]);add('date_cover','Date first + cover',datefirst,[dt])
        add('bounded_date_cover','Bounds + date cover',bounded,[dt])
    elif q==36:
        idx('idx_nf_q36_date_cover','store_sales','ss_sold_date_sk,ss_item_sk,ss_store_sk,ss_net_profit,ss_ext_sales_price')
        cover=definitions[0]['name']
        add('bounds','Verified year bounds',original.replace('d1.d_year = 2001','d1.d_year = 2001 AND ss_sold_date_sk BETWEEN 2451911 AND 2452275'),reason='Keep the corrected explicit hierarchy and date existence join.')
        leaf='''SELECT i_category,i_class,SUM(ss_net_profit) profit,SUM(ss_ext_sales_price) price
FROM store_sales JOIN date_dim d1 ON d1.d_date_sk=ss_sold_date_sk
JOIN item ON i_item_sk=ss_item_sk JOIN store ON s_store_sk=ss_store_sk
WHERE d1.d_year=2001 AND s_state='TN'
GROUP BY i_category,i_class'''
        final='''SELECT gross_margin,i_category,i_class,lochierarchy,
RANK() OVER(PARTITION BY lochierarchy,CASE WHEN lochierarchy=0 THEN i_category END ORDER BY gross_margin ASC) rank_within_parent
FROM hierarchy ORDER BY lochierarchy DESC,CASE WHEN lochierarchy=0 THEN i_category END,rank_within_parent LIMIT 100;'''
        expanded='''WITH leaf AS (LEAF), levels AS (SELECT 0 lev UNION ALL SELECT 1 UNION ALL SELECT 2), hierarchy AS (
SELECT SUM(profit)/SUM(price) gross_margin,
CASE WHEN lev<2 THEN i_category END i_category,
CASE WHEN lev=0 THEN i_class END i_class,lev lochierarchy
FROM leaf CROSS JOIN levels
GROUP BY lev,CASE WHEN lev<2 THEN i_category END,CASE WHEN lev=0 THEN i_class END
) '''+final
        onepass=expanded.replace('LEAF',leaf)
        bounded=expanded.replace('LEAF',leaf.replace("d1.d_year=2001","d1.d_year=2001 AND ss_sold_date_sk BETWEEN 2451911 AND 2452275"))
        add('leaf_levels','Single leaf aggregation',onepass,reason='Read facts once, then expand the small leaf result into three explicit hierarchy levels; retain genuine NULL identities.')
        add('bounded_leaf','Bounded leaf aggregation',bounded,reason='Add verified date bounds to the single-pass hierarchy.')
        add('index_only','Profit/price covering',original,[cover])
        add('leaf_cover','Leaf levels + cover',onepass,[cover]);add('bounded_cover','Bounded leaf + cover',bounded,[cover])
        item_totals='''SELECT ss_item_sk,SUM(ss_net_profit) profit,SUM(ss_ext_sales_price) price
FROM store_sales JOIN date_dim d1 ON d1.d_date_sk=ss_sold_date_sk
JOIN store ON s_store_sk=ss_store_sk
WHERE d1.d_year=2001 AND s_state='TN' AND ss_sold_date_sk BETWEEN 2451911 AND 2452275
GROUP BY ss_item_sk'''
        late_leaf='''SELECT i_category,i_class,SUM(profit) profit,SUM(price) price
FROM item_totals JOIN item ON i_item_sk=ss_item_sk GROUP BY i_category,i_class'''
        late=expanded.replace('WITH leaf AS (LEAF)', 'WITH item_totals AS ('+item_totals+'), leaf AS ('+late_leaf+')')
        add('late_item','Aggregate before item',late,reason='Aggregate qualifying facts by numeric item key before item lookups; regroup sums at category/class grain, then form explicit hierarchy levels.')
        add('late_item_cover','Late item + cover',late,[cover],'Combine late item lookup and explicit hierarchy with the date/profit/price covering index.')
        # Raw expansion is a useful contrasting approach: no preaggregation.
        raw=leaf[:leaf.index('GROUP BY')].replace('SELECT i_category,i_class,SUM(ss_net_profit) profit,SUM(ss_ext_sales_price) price','SELECT i_category,i_class,ss_net_profit profit,ss_ext_sales_price price')
        add('raw_levels','Raw level expansion',expanded.replace('LEAF',raw),reason='Test one fact scan with three raw grouping-level rows per fact rather than preaggregating leaves.')
    else:
        idx('idx_nf_q45_date_cover','web_sales','ws_sold_date_sk,ws_bill_customer_sk,ws_item_sk,ws_sales_price')
        idx('idx_nf_q45_customer_cover','web_sales','ws_bill_customer_sk,ws_sold_date_sk,ws_item_sk,ws_sales_price')
        idx('idx_nf_q45_item_cover','web_sales','ws_item_sk,ws_sold_date_sk,ws_bill_customer_sk,ws_sales_price')
        idx('idx_nf_q45_zip','customer_address','ca_zip')
        date,customer,item,zipidx=[x['name'] for x in definitions]
        bounded=original.replace('and d_qoy = 1','and ws_sold_date_sk BETWEEN 2451911 AND 2452001 AND d_qoy = 1')
        add('bounds','Verified quarter bounds',bounded,reason='Use actual date_dim quarter keys, including 2452001; retain original year and quarter tests.')
        add('index_only','Date price covering',original,[date])
        add('bounded_cover','Bounds + date cover',bounded,[date])
        zips="('85669','86197','88274','83405','86475','85392','85460','80348','81792')"
        keys='(2,3,5,7,11,13,17,19,23,29)'
        zipmatch=f'SUBSTR(ca_zip,1,5) IN {zips}'
        itemmatch=f'i_item_id IN(SELECT i_item_id FROM item WHERE i_item_sk IN {keys})'
        common='''FROM web_sales JOIN customer ON ws_bill_customer_sk=c_customer_sk
JOIN customer_address ON c_current_addr_sk=ca_address_sk
JOIN date_dim ON ws_sold_date_sk=d_date_sk JOIN item ON ws_item_sk=i_item_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001'''
        union=f'''SELECT ca_zip,ca_county,SUM(amount) FROM (
SELECT ca_zip,ca_county,SUM(ws_sales_price) amount {common} AND {zipmatch} GROUP BY ca_zip,ca_county
UNION ALL
SELECT ca_zip,ca_county,SUM(ws_sales_price) amount {common} AND {itemmatch} AND ({zipmatch}) IS NOT TRUE GROUP BY ca_zip,ca_county
) branches GROUP BY ca_zip,ca_county ORDER BY ca_zip,ca_county LIMIT 100;'''
        add('disjoint_union','Disjoint ZIP/item branches',union,reason='Partition the OR without double-counting; IS NOT TRUE retains NULL ZIP rows in the item branch.')
        add('union_cover','Disjoint branches + cover',union,[date])
        prefix='('+' OR '.join("ca_zip LIKE '"+z+"%'" for z in re.findall("'([0-9]+)'",zips))+')'
        zipjoins='''FROM customer_address STRAIGHT_JOIN customer ON c_current_addr_sk=ca_address_sk
STRAIGHT_JOIN web_sales ON ws_bill_customer_sk=c_customer_sk
STRAIGHT_JOIN date_dim ON ws_sold_date_sk=d_date_sk
STRAIGHT_JOIN item ON ws_item_sk=i_item_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001'''
        itemjoins='''FROM item STRAIGHT_JOIN web_sales ON ws_item_sk=i_item_sk
STRAIGHT_JOIN date_dim ON ws_sold_date_sk=d_date_sk
STRAIGHT_JOIN customer ON ws_bill_customer_sk=c_customer_sk
STRAIGHT_JOIN customer_address ON c_current_addr_sk=ca_address_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001'''
        selective=union.replace(common,zipjoins,1)
        pos=selective.index('UNION ALL');selective=selective[:pos]+selective[pos:].replace(common,itemjoins,1)
        selective=selective.replace('AND '+zipmatch+' GROUP BY','AND '+prefix+' AND '+zipmatch+' GROUP BY',1)
        add('selective_union','Selective branch join order',selective,reason='ZIP/customer first for ZIP sales, matching item versions first for the other branch; preserve the business-ID membership test.')
        add('selective_cover','Selective branches + covers',selective,[customer,item,zipidx])
        add('all_cover','Branch alternative all covers',selective,[date,customer,item,zipidx])
        eligible_customers=f"SELECT zc.c_customer_sk FROM customer zc JOIN customer_address za ON zc.c_current_addr_sk=za.ca_address_sk WHERE SUBSTR(za.ca_zip,1,5) IN {zips}"
        eligible_items=f"SELECT zi.i_item_sk FROM item zi WHERE zi.i_item_id IN (SELECT pick.i_item_id FROM item pick WHERE pick.i_item_sk IN {keys})"
        necessary=f' AND (ws_bill_customer_sk IN ({eligible_customers}) OR ws_item_sk IN ({eligible_items})) '
        pushed=bounded.replace('group by ca_zip, ca_county',necessary+' group by ca_zip, ca_county')
        assert pushed!=bounded
        add('fact_eligibility','Early fact eligibility',pushed,reason='Apply necessary ZIP-customer/item-key eligibility on fact foreign keys before expensive dimension lookups; retain original OR, all joins and the verified quarter predicates.')
        add('fact_eligibility_cover','Fact eligibility + cover',pushed,[date],'Combine early fact-key eligibility with the date/customer/item/price covering index.')
    (d/'candidates.json').write_text(json.dumps(candidates,indent=2));(d/'indexes.json').write_text(json.dumps(definitions,indent=2))
    print(f'Q{q}: {len(candidates)-1} suitable candidate conditions, {len(definitions)} optional indexes.')
