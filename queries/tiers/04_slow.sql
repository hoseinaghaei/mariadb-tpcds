-- ==========================================================================
--  Tier 4 - slow  (20 queries)
-- ==========================================================================
--
--  Ranked by response time on the INDEXED database (117 indexes applied),
--  which is the current state of the `tpcds` schema.
--
--  Range in this file : 7.9s .. 31.5s
--  Total for this file: 304.1s
--  Queries            : 62, 59, 67, 29, 25, 37, 82, 97, 99, 13, 57, 48, 73, 26, 77, 15, 74, 11, 79, 27
--
--  Columns below each query header:
--    indexed = this run   base = before the 117 indexes   x = speedup
--    (!) marks a query the indexes made SLOWER
--    (*) marks a capped query that never completed
-- ==========================================================================

USE tpcds;
-- several TPC-DS queries call functions with a space before '(' e.g. `sum (`
SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE');

-- --------------------------------------------------------------------------
-- query62   indexed 7.9s   base 7.3s   0.92x
-- --------------------------------------------------------------------------
select  
   substr(w_warehouse_name,1,20)
  ,sm_type
  ,web_name
  ,sum(case when (ws_ship_date_sk - ws_sold_date_sk <= 30 ) then 1 else 0 end)  as "30 days" 
  ,sum(case when (ws_ship_date_sk - ws_sold_date_sk > 30) and 
                 (ws_ship_date_sk - ws_sold_date_sk <= 60) then 1 else 0 end )  as "31-60 days" 
  ,sum(case when (ws_ship_date_sk - ws_sold_date_sk > 60) and 
                 (ws_ship_date_sk - ws_sold_date_sk <= 90) then 1 else 0 end)  as "61-90 days" 
  ,sum(case when (ws_ship_date_sk - ws_sold_date_sk > 90) and
                 (ws_ship_date_sk - ws_sold_date_sk <= 120) then 1 else 0 end)  as "91-120 days" 
  ,sum(case when (ws_ship_date_sk - ws_sold_date_sk  > 120) then 1 else 0 end)  as ">120 days" 
from
   web_sales
  ,warehouse
  ,ship_mode
  ,web_site
  ,date_dim
where
    d_month_seq between 1212 and 1212 + 11
and ws_ship_date_sk   = d_date_sk
and ws_warehouse_sk   = w_warehouse_sk
and ws_ship_mode_sk   = sm_ship_mode_sk
and ws_web_site_sk    = web_site_sk
group by
   substr(w_warehouse_name,1,20)
  ,sm_type
  ,web_name
order by substr(w_warehouse_name,1,20)
        ,sm_type
       ,web_name
limit 100;

-- --------------------------------------------------------------------------
-- query59   indexed 8.1s   base 17.8s   2.20x
-- --------------------------------------------------------------------------
with wss as 
 (select d_week_seq,
        ss_store_sk,
        sum(case when (d_day_name='Sunday') then ss_sales_price else null end) sun_sales,
        sum(case when (d_day_name='Monday') then ss_sales_price else null end) mon_sales,
        sum(case when (d_day_name='Tuesday') then ss_sales_price else  null end) tue_sales,
        sum(case when (d_day_name='Wednesday') then ss_sales_price else null end) wed_sales,
        sum(case when (d_day_name='Thursday') then ss_sales_price else null end) thu_sales,
        sum(case when (d_day_name='Friday') then ss_sales_price else null end) fri_sales,
        sum(case when (d_day_name='Saturday') then ss_sales_price else null end) sat_sales
 from store_sales,date_dim
 where d_date_sk = ss_sold_date_sk
 group by d_week_seq,ss_store_sk
 )
  select  s_store_name1,s_store_id1,d_week_seq1
       ,sun_sales1/sun_sales2,mon_sales1/mon_sales2
       ,tue_sales1/tue_sales2,wed_sales1/wed_sales2,thu_sales1/thu_sales2
       ,fri_sales1/fri_sales2,sat_sales1/sat_sales2
 from
 (select s_store_name s_store_name1,wss.d_week_seq d_week_seq1
        ,s_store_id s_store_id1,sun_sales sun_sales1
        ,mon_sales mon_sales1,tue_sales tue_sales1
        ,wed_sales wed_sales1,thu_sales thu_sales1
        ,fri_sales fri_sales1,sat_sales sat_sales1
  from wss,store,date_dim d
  where d.d_week_seq = wss.d_week_seq and
        ss_store_sk = s_store_sk and 
        d_month_seq between 1185 and 1185 + 11) y,
 (select s_store_name s_store_name2,wss.d_week_seq d_week_seq2
        ,s_store_id s_store_id2,sun_sales sun_sales2
        ,mon_sales mon_sales2,tue_sales tue_sales2
        ,wed_sales wed_sales2,thu_sales thu_sales2
        ,fri_sales fri_sales2,sat_sales sat_sales2
  from wss,store,date_dim d
  where d.d_week_seq = wss.d_week_seq and
        ss_store_sk = s_store_sk and 
        d_month_seq between 1185+ 12 and 1185 + 23) x
 where s_store_id1=s_store_id2
   and d_week_seq1=d_week_seq2-52
 order by s_store_name1,s_store_id1,d_week_seq1
limit 100;

-- --------------------------------------------------------------------------
-- query67   indexed 8.1s   base 20.7s   2.56x
-- --------------------------------------------------------------------------
select * from (
select  *
from (select i_category
            ,i_class
            ,i_brand
            ,i_product_name
            ,d_year
            ,d_qoy
            ,d_moy
            ,s_store_id
            ,sumsales
            ,rank() over (partition by i_category order by sumsales desc) rk
      from (select i_category
                  ,i_class
                  ,i_brand
                  ,i_product_name
                  ,d_year
                  ,d_qoy
                  ,d_moy
                  ,s_store_id
                  ,sum(coalesce(ss_sales_price*ss_quantity,0)) sumsales
            from store_sales
                ,date_dim
                ,store
                ,item
       where  ss_sold_date_sk=d_date_sk
          and ss_item_sk=i_item_sk
          and ss_store_sk = s_store_sk
          and d_month_seq between 1212 and 1212+11
       group by i_category, i_class, i_brand, i_product_name, d_year, d_qoy, d_moy,s_store_id with rollup)dw1) dw2
where rk <= 100
) tpcds_rollup
order by i_category
        ,i_class
        ,i_brand
        ,i_product_name
        ,d_year
        ,d_qoy
        ,d_moy
        ,s_store_id
        ,sumsales
        ,rk
limit 100;

-- --------------------------------------------------------------------------
-- query29   indexed 8.3s   base 5.4s   0.65x (!)
-- --------------------------------------------------------------------------
select   
     i_item_id
    ,i_item_desc
    ,s_store_id
    ,s_store_name
    ,sum(ss_quantity)        as store_sales_quantity
    ,sum(sr_return_quantity) as store_returns_quantity
    ,sum(cs_quantity)        as catalog_sales_quantity
 from
    store_sales
   ,store_returns
   ,catalog_sales
   ,date_dim             d1
   ,date_dim             d2
   ,date_dim             d3
   ,store
   ,item
 where
     d1.d_moy               = 4 
 and d1.d_year              = 1999
 and d1.d_date_sk           = ss_sold_date_sk
 and i_item_sk              = ss_item_sk
 and s_store_sk             = ss_store_sk
 and ss_customer_sk         = sr_customer_sk
 and ss_item_sk             = sr_item_sk
 and ss_ticket_number       = sr_ticket_number
 and sr_returned_date_sk    = d2.d_date_sk
 and d2.d_moy               between 4 and  4 + 3 
 and d2.d_year              = 1999
 and sr_customer_sk         = cs_bill_customer_sk
 and sr_item_sk             = cs_item_sk
 and cs_sold_date_sk        = d3.d_date_sk     
 and d3.d_year              in (1999,1999+1,1999+2)
 group by
    i_item_id
   ,i_item_desc
   ,s_store_id
   ,s_store_name
 order by
    i_item_id 
   ,i_item_desc
   ,s_store_id
   ,s_store_name
 limit 100;

-- --------------------------------------------------------------------------
-- query25   indexed 8.4s   base 8.5s   1.01x
-- --------------------------------------------------------------------------
select  
 i_item_id
 ,i_item_desc
 ,s_store_id
 ,s_store_name
 ,sum(ss_net_profit) as store_sales_profit
 ,sum(sr_net_loss) as store_returns_loss
 ,sum(cs_net_profit) as catalog_sales_profit
 from
 store_sales
 ,store_returns
 ,catalog_sales
 ,date_dim d1
 ,date_dim d2
 ,date_dim d3
 ,store
 ,item
 where
 d1.d_moy = 4
 and d1.d_year = 2000
 and d1.d_date_sk = ss_sold_date_sk
 and i_item_sk = ss_item_sk
 and s_store_sk = ss_store_sk
 and ss_customer_sk = sr_customer_sk
 and ss_item_sk = sr_item_sk
 and ss_ticket_number = sr_ticket_number
 and sr_returned_date_sk = d2.d_date_sk
 and d2.d_moy               between 4 and  10
 and d2.d_year              = 2000
 and sr_customer_sk = cs_bill_customer_sk
 and sr_item_sk = cs_item_sk
 and cs_sold_date_sk = d3.d_date_sk
 and d3.d_moy               between 4 and  10 
 and d3.d_year              = 2000
 group by
 i_item_id
 ,i_item_desc
 ,s_store_id
 ,s_store_name
 order by
 i_item_id
 ,i_item_desc
 ,s_store_id
 ,s_store_name
 limit 100;

-- --------------------------------------------------------------------------
-- query37   indexed 8.4s   base 9.6s   1.14x
-- --------------------------------------------------------------------------
select  i_item_id
       ,i_item_desc
       ,i_current_price
 from item, inventory, date_dim, catalog_sales
 where i_current_price between 22 and 22 + 30
 and inv_item_sk = i_item_sk
 and d_date_sk=inv_date_sk
 and d_date between cast('2001-06-02' as date) and (cast('2001-06-02' as date) +  interval 60 day)
 and i_manufact_id in (678,964,918,849)
 and inv_quantity_on_hand between 100 and 500
 and cs_item_sk = i_item_sk
 group by i_item_id,i_item_desc,i_current_price
 order by i_item_id
 limit 100;

-- --------------------------------------------------------------------------
-- query82   indexed 9.0s   base 10.3s   1.14x
-- --------------------------------------------------------------------------
select  i_item_id
       ,i_item_desc
       ,i_current_price
 from item, inventory, date_dim, store_sales
 where i_current_price between 30 and 30+30
 and inv_item_sk = i_item_sk
 and d_date_sk=inv_date_sk
 and d_date between cast('2002-05-30' as date) and (cast('2002-05-30' as date) +  interval 60 day)
 and i_manufact_id in (437,129,727,663)
 and inv_quantity_on_hand between 100 and 500
 and ss_item_sk = i_item_sk
 group by i_item_id,i_item_desc,i_current_price
 order by i_item_id
 limit 100;

-- --------------------------------------------------------------------------
-- query97   indexed 9.4s   base 26.5s   2.82x
-- --------------------------------------------------------------------------
with ssci as (
select ss_customer_sk customer_sk
      ,ss_item_sk item_sk
from store_sales,date_dim
where ss_sold_date_sk = d_date_sk
  and d_month_seq between 1212 and 1212 + 11
group by ss_customer_sk
        ,ss_item_sk),
csci as(
 select cs_bill_customer_sk customer_sk
      ,cs_item_sk item_sk
from catalog_sales,date_dim
where cs_sold_date_sk = d_date_sk
  and d_month_seq between 1212 and 1212 + 11
group by cs_bill_customer_sk
        ,cs_item_sk)
 select  sum(case when ssci_customer_sk is not null and csci_customer_sk is null then 1 else 0 end) store_only
      ,sum(case when ssci_customer_sk is null and csci_customer_sk is not null then 1 else 0 end) catalog_only
      ,sum(case when ssci_customer_sk is not null and csci_customer_sk is not null then 1 else 0 end) store_and_catalog
from (
      -- MariaDB has no FULL OUTER JOIN: emulated as
      -- (A LEFT JOIN B) UNION ALL (A RIGHT JOIN B WHERE A keys IS NULL).
      -- The anti-join filter on the second branch keeps only the B rows that
      -- found no A match, so UNION ALL adds no duplicates and legitimate
      -- duplicate rows are preserved.
      (select ssci.customer_sk ssci_customer_sk
             ,csci.customer_sk csci_customer_sk
       from ssci left outer join csci on (ssci.customer_sk=csci.customer_sk
                                      and ssci.item_sk = csci.item_sk))
      union all
      (select ssci.customer_sk ssci_customer_sk
             ,csci.customer_sk csci_customer_sk
       from ssci right outer join csci on (ssci.customer_sk=csci.customer_sk
                                       and ssci.item_sk = csci.item_sk)
       where ssci.customer_sk is null
         and ssci.item_sk is null)
     ) fj
limit 100;

-- --------------------------------------------------------------------------
-- query99   indexed 11.7s   base 3.0s   0.26x (!)
-- --------------------------------------------------------------------------
select  
   substr(w_warehouse_name,1,20)
  ,sm_type
  ,cc_name
  ,sum(case when (cs_ship_date_sk - cs_sold_date_sk <= 30 ) then 1 else 0 end)  as "30 days" 
  ,sum(case when (cs_ship_date_sk - cs_sold_date_sk > 30) and 
                 (cs_ship_date_sk - cs_sold_date_sk <= 60) then 1 else 0 end )  as "31-60 days" 
  ,sum(case when (cs_ship_date_sk - cs_sold_date_sk > 60) and 
                 (cs_ship_date_sk - cs_sold_date_sk <= 90) then 1 else 0 end)  as "61-90 days" 
  ,sum(case when (cs_ship_date_sk - cs_sold_date_sk > 90) and
                 (cs_ship_date_sk - cs_sold_date_sk <= 120) then 1 else 0 end)  as "91-120 days" 
  ,sum(case when (cs_ship_date_sk - cs_sold_date_sk  > 120) then 1 else 0 end)  as ">120 days" 
from
   catalog_sales
  ,warehouse
  ,ship_mode
  ,call_center
  ,date_dim
where
    d_month_seq between 1212 and 1212 + 11
and cs_ship_date_sk   = d_date_sk
and cs_warehouse_sk   = w_warehouse_sk
and cs_ship_mode_sk   = sm_ship_mode_sk
and cs_call_center_sk = cc_call_center_sk
group by
   substr(w_warehouse_name,1,20)
  ,sm_type
  ,cc_name
order by substr(w_warehouse_name,1,20)
        ,sm_type
        ,cc_name
limit 100;

-- --------------------------------------------------------------------------
-- query13   indexed 12.6s   base 2.6s   0.21x (!)
-- --------------------------------------------------------------------------
select avg(ss_quantity)
       ,avg(ss_ext_sales_price)
       ,avg(ss_ext_wholesale_cost)
       ,sum(ss_ext_wholesale_cost)
 from store_sales
     ,store
     ,customer_demographics
     ,household_demographics
     ,customer_address
     ,date_dim
 where s_store_sk = ss_store_sk
 and  ss_sold_date_sk = d_date_sk and d_year = 2001
 and((ss_hdemo_sk=hd_demo_sk
  and cd_demo_sk = ss_cdemo_sk
  and cd_marital_status = 'D'
  and cd_education_status = '2 yr Degree'
  and ss_sales_price between 100.00 and 150.00
  and hd_dep_count = 3   
     )or
     (ss_hdemo_sk=hd_demo_sk
  and cd_demo_sk = ss_cdemo_sk
  and cd_marital_status = 'S'
  and cd_education_status = 'Secondary'
  and ss_sales_price between 50.00 and 100.00   
  and hd_dep_count = 1
     ) or 
     (ss_hdemo_sk=hd_demo_sk
  and cd_demo_sk = ss_cdemo_sk
  and cd_marital_status = 'W'
  and cd_education_status = 'Advanced Degree'
  and ss_sales_price between 150.00 and 200.00 
  and hd_dep_count = 1  
     ))
 and((ss_addr_sk = ca_address_sk
  and ca_country = 'United States'
  and ca_state in ('CO', 'IL', 'MN')
  and ss_net_profit between 100 and 200  
     ) or
     (ss_addr_sk = ca_address_sk
  and ca_country = 'United States'
  and ca_state in ('OH', 'MT', 'NM')
  and ss_net_profit between 150 and 300  
     ) or
     (ss_addr_sk = ca_address_sk
  and ca_country = 'United States'
  and ca_state in ('TX', 'MO', 'MI')
  and ss_net_profit between 50 and 250  
     ))
;

-- --------------------------------------------------------------------------
-- query57   indexed 13.8s   base 36.5s   2.64x
-- --------------------------------------------------------------------------
with v1 as(
 select i_category, i_brand,
        cc_name,
        d_year, d_moy,
        sum(cs_sales_price) sum_sales,
        avg(sum(cs_sales_price)) over
          (partition by i_category, i_brand,
                     cc_name, d_year)
          avg_monthly_sales,
        rank() over
          (partition by i_category, i_brand,
                     cc_name
           order by d_year, d_moy) rn
 from item, catalog_sales, date_dim, call_center
 where cs_item_sk = i_item_sk and
       cs_sold_date_sk = d_date_sk and
       cc_call_center_sk= cs_call_center_sk and
       (
         d_year = 2000 or
         ( d_year = 2000-1 and d_moy =12) or
         ( d_year = 2000+1 and d_moy =1)
       )
 group by i_category, i_brand,
          cc_name , d_year, d_moy),
 v2 as(
 select v1.cc_name
        ,v1.d_year, v1.d_moy
        ,v1.avg_monthly_sales
        ,v1.sum_sales, v1_lag.sum_sales psum, v1_lead.sum_sales nsum
 from v1, v1 v1_lag, v1 v1_lead
 where v1.i_category = v1_lag.i_category and
       v1.i_category = v1_lead.i_category and
       v1.i_brand = v1_lag.i_brand and
       v1.i_brand = v1_lead.i_brand and
       v1. cc_name = v1_lag. cc_name and
       v1. cc_name = v1_lead. cc_name and
       v1.rn = v1_lag.rn + 1 and
       v1.rn = v1_lead.rn - 1)
  select  *
 from v2
 where  d_year = 2000 and
        avg_monthly_sales > 0 and
        case when avg_monthly_sales > 0 then abs(sum_sales - avg_monthly_sales) / avg_monthly_sales else null end > 0.1
 order by sum_sales - avg_monthly_sales, nsum
 limit 100;

-- --------------------------------------------------------------------------
-- query48   indexed 14.6s   base 8.2s   0.56x (!)
-- --------------------------------------------------------------------------
select sum (ss_quantity)
 from store_sales, store, customer_demographics, customer_address, date_dim
 where s_store_sk = ss_store_sk
 and  ss_sold_date_sk = d_date_sk and d_year = 1998
 and  
 (
  (
   cd_demo_sk = ss_cdemo_sk
   and 
   cd_marital_status = 'M'
   and 
   cd_education_status = '4 yr Degree'
   and 
   ss_sales_price between 100.00 and 150.00  
   )
 or
  (
  cd_demo_sk = ss_cdemo_sk
   and 
   cd_marital_status = 'D'
   and 
   cd_education_status = 'Primary'
   and 
   ss_sales_price between 50.00 and 100.00   
  )
 or 
 (
  cd_demo_sk = ss_cdemo_sk
  and 
   cd_marital_status = 'U'
   and 
   cd_education_status = 'Advanced Degree'
   and 
   ss_sales_price between 150.00 and 200.00  
 )
 )
 and
 (
  (
  ss_addr_sk = ca_address_sk
  and
  ca_country = 'United States'
  and
  ca_state in ('KY', 'GA', 'NM')
  and ss_net_profit between 0 and 2000  
  )
 or
  (ss_addr_sk = ca_address_sk
  and
  ca_country = 'United States'
  and
  ca_state in ('MT', 'OR', 'IN')
  and ss_net_profit between 150 and 3000 
  )
 or
  (ss_addr_sk = ca_address_sk
  and
  ca_country = 'United States'
  and
  ca_state in ('WI', 'MO', 'WV')
  and ss_net_profit between 50 and 25000 
  )
 )
;

-- --------------------------------------------------------------------------
-- query73   indexed 15.2s   base 10.6s   0.70x (!)
-- --------------------------------------------------------------------------
select c_last_name
       ,c_first_name
       ,c_salutation
       ,c_preferred_cust_flag 
       ,ss_ticket_number
       ,cnt from
   (select ss_ticket_number
          ,ss_customer_sk
          ,count(*) cnt
    from store_sales,date_dim,store,household_demographics
    where store_sales.ss_sold_date_sk = date_dim.d_date_sk
    and store_sales.ss_store_sk = store.s_store_sk  
    and store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
    and date_dim.d_dom between 1 and 2 
    and (household_demographics.hd_buy_potential = '>10000' or
         household_demographics.hd_buy_potential = 'Unknown')
    and household_demographics.hd_vehicle_count > 0
    and case when household_demographics.hd_vehicle_count > 0 then 
             household_demographics.hd_dep_count/ household_demographics.hd_vehicle_count else null end > 1
    and date_dim.d_year in (1998,1998+1,1998+2)
    and store.s_county in ('Williamson County','Williamson County','Williamson County','Williamson County')
    group by ss_ticket_number,ss_customer_sk) dj,customer
    where ss_customer_sk = c_customer_sk
      and cnt between 1 and 5
    order by cnt desc, c_last_name asc;

-- --------------------------------------------------------------------------
-- query26   indexed 16.0s   base 20.2s   1.26x
-- --------------------------------------------------------------------------
select  i_item_id, 
        avg(cs_quantity) agg1,
        avg(cs_list_price) agg2,
        avg(cs_coupon_amt) agg3,
        avg(cs_sales_price) agg4 
 from catalog_sales, customer_demographics, date_dim, item, promotion
 where cs_sold_date_sk = d_date_sk and
       cs_item_sk = i_item_sk and
       cs_bill_cdemo_sk = cd_demo_sk and
       cs_promo_sk = p_promo_sk and
       cd_gender = 'F' and 
       cd_marital_status = 'W' and
       cd_education_status = 'Primary' and
       (p_channel_email = 'N' or p_channel_event = 'N') and
       d_year = 1998 
 group by i_item_id
 order by i_item_id
 limit 100;

-- --------------------------------------------------------------------------
-- query77   indexed 17.8s   base 14.7s   0.83x (!)
-- --------------------------------------------------------------------------
select * from (
with ss as
 (select s_store_sk,
         sum(ss_ext_sales_price) as sales,
         sum(ss_net_profit) as profit
 from store_sales,
      date_dim,
      store
 where ss_sold_date_sk = d_date_sk
       and d_date between cast('1998-08-04' as date) 
                  and (cast('1998-08-04' as date) +  interval 30 day) 
       and ss_store_sk = s_store_sk
 group by s_store_sk)
 ,
 sr as
 (select s_store_sk,
         sum(sr_return_amt) as returns,
         sum(sr_net_loss) as profit_loss
 from store_returns,
      date_dim,
      store
 where sr_returned_date_sk = d_date_sk
       and d_date between cast('1998-08-04' as date)
                  and (cast('1998-08-04' as date) +  interval 30 day)
       and sr_store_sk = s_store_sk
 group by s_store_sk), 
 cs as
 (select cs_call_center_sk,
        sum(cs_ext_sales_price) as sales,
        sum(cs_net_profit) as profit
 from catalog_sales,
      date_dim
 where cs_sold_date_sk = d_date_sk
       and d_date between cast('1998-08-04' as date)
                  and (cast('1998-08-04' as date) +  interval 30 day)
 group by cs_call_center_sk 
 ), 
 cr as
 (select cr_call_center_sk,
         sum(cr_return_amount) as returns,
         sum(cr_net_loss) as profit_loss
 from catalog_returns,
      date_dim
 where cr_returned_date_sk = d_date_sk
       and d_date between cast('1998-08-04' as date)
                  and (cast('1998-08-04' as date) +  interval 30 day)
 group by cr_call_center_sk
 ), 
 ws as
 ( select wp_web_page_sk,
        sum(ws_ext_sales_price) as sales,
        sum(ws_net_profit) as profit
 from web_sales,
      date_dim,
      web_page
 where ws_sold_date_sk = d_date_sk
       and d_date between cast('1998-08-04' as date)
                  and (cast('1998-08-04' as date) +  interval 30 day)
       and ws_web_page_sk = wp_web_page_sk
 group by wp_web_page_sk), 
 wr as
 (select wp_web_page_sk,
        sum(wr_return_amt) as returns,
        sum(wr_net_loss) as profit_loss
 from web_returns,
      date_dim,
      web_page
 where wr_returned_date_sk = d_date_sk
       and d_date between cast('1998-08-04' as date)
                  and (cast('1998-08-04' as date) +  interval 30 day)
       and wr_web_page_sk = wp_web_page_sk
 group by wp_web_page_sk)
  select  channel
        , id
        , sum(sales) as sales
        , sum(returns) as returns
        , sum(profit) as profit
 from 
 (select 'store channel' as channel
        , ss.s_store_sk as id
        , sales
        , coalesce(returns, 0) as returns
        , (profit - coalesce(profit_loss,0)) as profit
 from   ss left join sr
        on  ss.s_store_sk = sr.s_store_sk
 union all
 select 'catalog channel' as channel
        , cs_call_center_sk as id
        , sales
        , returns
        , (profit - profit_loss) as profit
 from  cs
       , cr
 union all
 select 'web channel' as channel
        , ws.wp_web_page_sk as id
        , sales
        , coalesce(returns, 0) returns
        , (profit - coalesce(profit_loss,0)) as profit
 from   ws left join wr
        on  ws.wp_web_page_sk = wr.wp_web_page_sk
 ) x
 group by channel, id with rollup
) tpcds_rollup
order by channel
         ,id
 limit 100;

-- --------------------------------------------------------------------------
-- query15   indexed 21.4s   base 5.4s   0.25x (!)
-- --------------------------------------------------------------------------
select  ca_zip
       ,sum(cs_sales_price)
 from catalog_sales
     ,customer
     ,customer_address
     ,date_dim
 where cs_bill_customer_sk = c_customer_sk
 	and c_current_addr_sk = ca_address_sk 
 	and ( substr(ca_zip,1,5) in ('85669', '86197','88274','83405','86475',
                                   '85392', '85460', '80348', '81792')
 	      or ca_state in ('CA','WA','GA')
 	      or cs_sales_price > 500)
 	and cs_sold_date_sk = d_date_sk
 	and d_qoy = 2 and d_year = 2000
 group by ca_zip
 order by ca_zip
 limit 100;

-- --------------------------------------------------------------------------
-- query74   indexed 24.6s   base 38.7s   1.57x
-- --------------------------------------------------------------------------
with year_total as (
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,d_year as year
       ,max(ss_net_paid) year_total
       ,'s' sale_type
 from customer
     ,store_sales
     ,date_dim
 where c_customer_sk = ss_customer_sk
   and ss_sold_date_sk = d_date_sk
   and d_year in (2001,2001+1)
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,d_year
 union all
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,d_year as year
       ,max(ws_net_paid) year_total
       ,'w' sale_type
 from customer
     ,web_sales
     ,date_dim
 where c_customer_sk = ws_bill_customer_sk
   and ws_sold_date_sk = d_date_sk
   and d_year in (2001,2001+1)
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,d_year
         )
  select 
        t_s_secyear.customer_id, t_s_secyear.customer_first_name, t_s_secyear.customer_last_name
 from year_total t_s_firstyear
     ,year_total t_s_secyear
     ,year_total t_w_firstyear
     ,year_total t_w_secyear
 where t_s_secyear.customer_id = t_s_firstyear.customer_id
         and t_s_firstyear.customer_id = t_w_secyear.customer_id
         and t_s_firstyear.customer_id = t_w_firstyear.customer_id
         and t_s_firstyear.sale_type = 's'
         and t_w_firstyear.sale_type = 'w'
         and t_s_secyear.sale_type = 's'
         and t_w_secyear.sale_type = 'w'
         and t_s_firstyear.year = 2001
         and t_s_secyear.year = 2001+1
         and t_w_firstyear.year = 2001
         and t_w_secyear.year = 2001+1
         and t_s_firstyear.year_total > 0
         and t_w_firstyear.year_total > 0
         and case when t_w_firstyear.year_total > 0 then t_w_secyear.year_total / t_w_firstyear.year_total else null end
           > case when t_s_firstyear.year_total > 0 then t_s_secyear.year_total / t_s_firstyear.year_total else null end
 order by 2,1,3
limit 100;

-- --------------------------------------------------------------------------
-- query11   indexed 26.3s   base 67.6s   2.57x
-- --------------------------------------------------------------------------
with year_total as (
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,c_preferred_cust_flag customer_preferred_cust_flag
       ,c_birth_country customer_birth_country
       ,c_login customer_login
       ,c_email_address customer_email_address
       ,d_year dyear
       ,sum(ss_ext_list_price-ss_ext_discount_amt) year_total
       ,'s' sale_type
 from customer
     ,store_sales
     ,date_dim
 where c_customer_sk = ss_customer_sk
   and ss_sold_date_sk = d_date_sk
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,c_preferred_cust_flag 
         ,c_birth_country
         ,c_login
         ,c_email_address
         ,d_year 
 union all
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,c_preferred_cust_flag customer_preferred_cust_flag
       ,c_birth_country customer_birth_country
       ,c_login customer_login
       ,c_email_address customer_email_address
       ,d_year dyear
       ,sum(ws_ext_list_price-ws_ext_discount_amt) year_total
       ,'w' sale_type
 from customer
     ,web_sales
     ,date_dim
 where c_customer_sk = ws_bill_customer_sk
   and ws_sold_date_sk = d_date_sk
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,c_preferred_cust_flag 
         ,c_birth_country
         ,c_login
         ,c_email_address
         ,d_year
         )
  select  
                  t_s_secyear.customer_id
                 ,t_s_secyear.customer_first_name
                 ,t_s_secyear.customer_last_name
                 ,t_s_secyear.customer_email_address
 from year_total t_s_firstyear
     ,year_total t_s_secyear
     ,year_total t_w_firstyear
     ,year_total t_w_secyear
 where t_s_secyear.customer_id = t_s_firstyear.customer_id
         and t_s_firstyear.customer_id = t_w_secyear.customer_id
         and t_s_firstyear.customer_id = t_w_firstyear.customer_id
         and t_s_firstyear.sale_type = 's'
         and t_w_firstyear.sale_type = 'w'
         and t_s_secyear.sale_type = 's'
         and t_w_secyear.sale_type = 'w'
         and t_s_firstyear.dyear = 2001
         and t_s_secyear.dyear = 2001+1
         and t_w_firstyear.dyear = 2001
         and t_w_secyear.dyear = 2001+1
         and t_s_firstyear.year_total > 0
         and t_w_firstyear.year_total > 0
         and case when t_w_firstyear.year_total > 0 then t_w_secyear.year_total / t_w_firstyear.year_total else 0.0 end
             > case when t_s_firstyear.year_total > 0 then t_s_secyear.year_total / t_s_firstyear.year_total else 0.0 end
 order by t_s_secyear.customer_id
         ,t_s_secyear.customer_first_name
         ,t_s_secyear.customer_last_name
         ,t_s_secyear.customer_email_address
limit 100;

-- --------------------------------------------------------------------------
-- query79   indexed 31.0s   base 7.7s   0.25x (!)
-- --------------------------------------------------------------------------
select 
  c_last_name,c_first_name,substr(s_city,1,30),ss_ticket_number,amt,profit
  from
   (select ss_ticket_number
          ,ss_customer_sk
          ,store.s_city
          ,sum(ss_coupon_amt) amt
          ,sum(ss_net_profit) profit
    from store_sales,date_dim,store,household_demographics
    where store_sales.ss_sold_date_sk = date_dim.d_date_sk
    and store_sales.ss_store_sk = store.s_store_sk  
    and store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
    and (household_demographics.hd_dep_count = 8 or household_demographics.hd_vehicle_count > 0)
    and date_dim.d_dow = 1
    and date_dim.d_year in (1998,1998+1,1998+2) 
    and store.s_number_employees between 200 and 295
    group by ss_ticket_number,ss_customer_sk,ss_addr_sk,store.s_city) ms,customer
    where ss_customer_sk = c_customer_sk
 order by c_last_name,c_first_name,substr(s_city,1,30), profit
limit 100;

-- --------------------------------------------------------------------------
-- query27   indexed 31.5s   base 35.7s   1.13x
-- --------------------------------------------------------------------------
select * from (
select  i_item_id,
        s_state, (s_state is null) g_state,
        avg(ss_quantity) agg1,
        avg(ss_list_price) agg2,
        avg(ss_coupon_amt) agg3,
        avg(ss_sales_price) agg4
 from store_sales, customer_demographics, date_dim, store, item
 where ss_sold_date_sk = d_date_sk and
       ss_item_sk = i_item_sk and
       ss_store_sk = s_store_sk and
       ss_cdemo_sk = cd_demo_sk and
       cd_gender = 'F' and
       cd_marital_status = 'W' and
       cd_education_status = 'Primary' and
       d_year = 1998 and
       s_state in ('TN','TN', 'TN', 'TN', 'TN', 'TN')
 group by i_item_id, s_state with rollup
) tpcds_rollup
order by i_item_id
         ,s_state
 limit 100;

