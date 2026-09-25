-- ============================================================================
--  QUERIES THAT GOT SLOWER AFTER ADDING THE 117 INDEXES
-- ============================================================================
--
--  19 of 99 queries regressed by more than 10%.
--  Time lost to these regressions : 690.1s
--  Time won by the 68 improvements: 1970.2s
--  So roughly a quarter of the gain from indexing is handed back here.
--
--  Method: sql/05_indexes.sql was applied to the loaded SF=1 database,
--  ANALYZE TABLE was run on all seven fact tables, and all 99 queries were
--  re-run. These are the ones whose wall time got worse. Queries 72 and 95
--  are excluded because one side of their comparison was capped rather than
--  measured.
--
--  Ordered by ABSOLUTE time lost, which is what to fix first -- not by
--  ratio, which over-weights queries that were already fast.
-- ----------------------------------------------------------------------------
--   query |     base |  indexed |  slower |   lost
-- ----------------------------------------------------------------------------
--   39    |     1.6s |   193.6s |  121.0x |  192.0s
--   31    |    33.5s |   143.1s |    4.3x |  109.6s
--   21    |     0.5s |    59.8s |  119.6x |   59.3s
--   22    |    15.3s |    70.5s |    4.6x |   55.2s
--   8     |     9.4s |    51.9s |    5.5x |   42.5s
--   88    |    48.2s |    83.9s |    1.7x |   35.7s
--   68    |     9.3s |    44.3s |    4.8x |   35.0s
--   46    |     8.8s |    42.8s |    4.9x |   34.0s
--   35    |    14.9s |    44.4s |    3.0x |   29.5s
--   79    |     7.7s |    31.0s |    4.0x |   23.3s
--   10    |    22.8s |    43.9s |    1.9x |   21.1s
--   15    |     5.4s |    21.4s |    4.0x |   16.0s
--   13    |     2.6s |    12.6s |    4.8x |   10.0s
--   99    |     3.0s |    11.7s |    3.9x |    8.7s
--   48    |     8.2s |    14.6s |    1.8x |    6.4s
--   73    |    10.6s |    15.2s |    1.4x |    4.6s
--   77    |    14.7s |    17.8s |    1.2x |    3.1s
--   29    |     5.4s |     8.3s |    1.5x |    2.9s
--   91    |     0.4s |     1.6s |    4.0x |    1.2s
-- ----------------------------------------------------------------------------
--
--  THE PATTERN
--
--  Secondary indexes most often chosen by the optimizer in these queries:
--     5 queries  store_sales.idx_ss_addr_sk
--     3 queries  store_sales.idx_ss_sold_date_sk
--     3 queries  store_sales.idx_ss_hdemo_sk
--     2 queries  inventory.idx_inv_warehouse_sk
--     2 queries  customer.idx_c_current_addr_sk
--     2 queries  catalog_sales.idx_cs_bill_customer_sk
--     2 queries  customer_address.idx_customer_address_1
--     1 queries  inventory.idx_inv_item_sk
--
--  Grouped by table, the number of regressed queries whose plan uses a NEW
--  secondary index on that table:
--
--     11  store_sales        (2,880,404 rows)
--      3  inventory         (11,745,000 rows)
--      3  catalog_sales      (1,441,548 rows)
--      2  customer
--      2  customer_address
--      1  store_returns, web_sales, catalog_returns
--
--  `store_sales` is where the damage is concentrated, and `idx_ss_addr_sk`
--  alone appears in 5 of the 19. All 19 use at least one new secondary index,
--  so none of these regressions is unrelated to the index set.
--
--  The likely mechanism: TPC-DS fact-table queries filter on a date range and
--  then touch a large fraction of the surviving rows. A secondary index turns
--  what was a sequential scan into random primary-key lookups, which loses
--  once the selected fraction passes a few percent. The optimizer
--  underestimates that fraction and picks the index.
--
--  Two things make this worse here than it would be on a tuned server:
--    * innodb_buffer_pool_size is 128 MB against a 3.2 GB database, so random
--      lookups miss cache far more often than they would with a realistic
--      pool. Raising it may remove some regressions without touching indexes.
--    * The index set is inherited wholesale from the reference repo and was
--      never tuned for this data or this MariaDB version.
--
--  This is NOT stale statistics: ANALYZE TABLE ran on all seven fact tables
--  immediately after the indexes were created.
--
--  WHERE TO START
--
--  0. First try raising the buffer pool, which costs nothing and may fix
--     several of these outright:
--       SET GLOBAL innodb_buffer_pool_size = 2147483648;   -- 2 GB
--     then re-measure before changing any index.
--
--  1. The single highest-value experiment is idx_ss_addr_sk -- it is in the
--     plan of 5 of the 19:
--       ALTER TABLE store_sales DROP INDEX idx_ss_addr_sk;
--     Then re-run those 5 AND the queries that got faster, to confirm the
--     drop does not cost more than it saves. Query 46 and 68 both join
--     store_sales to customer_address and are good first checks.
--
--  2. Or keep the index and steer the individual query:
--       ... FROM inventory IGNORE INDEX (idx_inv_item_sk) ...
--
--  3. Compare plans before deciding:
--       EXPLAIN <query>;                 -- what it picks now
--       EXPLAIN FORMAT=JSON <query>;     -- with cost estimates
--
--  Re-measure with:  python3 queries/run_query.py <n> <tag>
--  then:             python3 queries/compare.py
-- ============================================================================

USE tpcds;
-- several TPC-DS queries call functions with a space before '(' e.g. `sum (`
SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE');

-- ----------------------------------------------------------------------------
-- query39   base 1.6s  ->  indexed 193.6s   121.0x SLOWER   (+192.0s)
-- optimizer now uses:
--     inventory.idx_inv_warehouse_sk (ref)
-- ----------------------------------------------------------------------------
with inv as
(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
       ,stdev,mean, case mean when 0 then null else stdev/mean end cov
 from(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
            ,stddev_samp(inv_quantity_on_hand) stdev,avg(inv_quantity_on_hand) mean
      from inventory
          ,item
          ,warehouse
          ,date_dim
      where inv_item_sk = i_item_sk
        and inv_warehouse_sk = w_warehouse_sk
        and inv_date_sk = d_date_sk
        and d_year =1998
      group by w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy) foo
 where case mean when 0 then 0 else stdev/mean end > 1)
select inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean, inv1.cov
        ,inv2.w_warehouse_sk,inv2.i_item_sk,inv2.d_moy,inv2.mean, inv2.cov
from inv inv1,inv inv2
where inv1.i_item_sk = inv2.i_item_sk
  and inv1.w_warehouse_sk =  inv2.w_warehouse_sk
  and inv1.d_moy=4
  and inv2.d_moy=4+1
order by inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean,inv1.cov
        ,inv2.d_moy,inv2.mean, inv2.cov
;

with inv as
(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
       ,stdev,mean, case mean when 0 then null else stdev/mean end cov
 from(select w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
            ,stddev_samp(inv_quantity_on_hand) stdev,avg(inv_quantity_on_hand) mean
      from inventory
          ,item
          ,warehouse
          ,date_dim
      where inv_item_sk = i_item_sk
        and inv_warehouse_sk = w_warehouse_sk
        and inv_date_sk = d_date_sk
        and d_year =1998
      group by w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy) foo
 where case mean when 0 then 0 else stdev/mean end > 1)
select inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean, inv1.cov
        ,inv2.w_warehouse_sk,inv2.i_item_sk,inv2.d_moy,inv2.mean, inv2.cov
from inv inv1,inv inv2
where inv1.i_item_sk = inv2.i_item_sk
  and inv1.w_warehouse_sk =  inv2.w_warehouse_sk
  and inv1.d_moy=4
  and inv2.d_moy=4+1
  and inv1.cov > 1.5
order by inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean,inv1.cov
        ,inv2.d_moy,inv2.mean, inv2.cov
;

-- ----------------------------------------------------------------------------
-- query31   base 33.5s  ->  indexed 143.1s   4.3x SLOWER   (+109.6s)
-- optimizer now uses:
--     store_sales.idx_ss_addr_sk (ref)
-- ----------------------------------------------------------------------------
with ss as
 (select ca_county,d_qoy, d_year,sum(ss_ext_sales_price) as store_sales
 from store_sales,date_dim,customer_address
 where ss_sold_date_sk = d_date_sk
  and ss_addr_sk=ca_address_sk
 group by ca_county,d_qoy, d_year),
 ws as
 (select ca_county,d_qoy, d_year,sum(ws_ext_sales_price) as web_sales
 from web_sales,date_dim,customer_address
 where ws_sold_date_sk = d_date_sk
  and ws_bill_addr_sk=ca_address_sk
 group by ca_county,d_qoy, d_year)
 select 
        ss1.ca_county
       ,ss1.d_year
       ,ws2.web_sales/ws1.web_sales web_q1_q2_increase
       ,ss2.store_sales/ss1.store_sales store_q1_q2_increase
       ,ws3.web_sales/ws2.web_sales web_q2_q3_increase
       ,ss3.store_sales/ss2.store_sales store_q2_q3_increase
 from
        ss ss1
       ,ss ss2
       ,ss ss3
       ,ws ws1
       ,ws ws2
       ,ws ws3
 where
    ss1.d_qoy = 1
    and ss1.d_year = 2000
    and ss1.ca_county = ss2.ca_county
    and ss2.d_qoy = 2
    and ss2.d_year = 2000
 and ss2.ca_county = ss3.ca_county
    and ss3.d_qoy = 3
    and ss3.d_year = 2000
    and ss1.ca_county = ws1.ca_county
    and ws1.d_qoy = 1
    and ws1.d_year = 2000
    and ws1.ca_county = ws2.ca_county
    and ws2.d_qoy = 2
    and ws2.d_year = 2000
    and ws1.ca_county = ws3.ca_county
    and ws3.d_qoy = 3
    and ws3.d_year =2000
    and case when ws1.web_sales > 0 then ws2.web_sales/ws1.web_sales else null end 
       > case when ss1.store_sales > 0 then ss2.store_sales/ss1.store_sales else null end
    and case when ws2.web_sales > 0 then ws3.web_sales/ws2.web_sales else null end
       > case when ss2.store_sales > 0 then ss3.store_sales/ss2.store_sales else null end
 order by ss1.d_year;

-- ----------------------------------------------------------------------------
-- query21   base 0.5s  ->  indexed 59.8s   119.6x SLOWER   (+59.3s)
-- optimizer now uses:
--     inventory.idx_inv_warehouse_sk (ref)
-- ----------------------------------------------------------------------------
select  *
 from(select w_warehouse_name
            ,i_item_id
            ,sum(case when (cast(d_date as date) < cast ('1998-04-08' as date))
	                then inv_quantity_on_hand 
                      else 0 end) as inv_before
            ,sum(case when (cast(d_date as date) >= cast ('1998-04-08' as date))
                      then inv_quantity_on_hand 
                      else 0 end) as inv_after
   from inventory
       ,warehouse
       ,item
       ,date_dim
   where i_current_price between 0.99 and 1.49
     and i_item_sk          = inv_item_sk
     and inv_warehouse_sk   = w_warehouse_sk
     and inv_date_sk    = d_date_sk
     and d_date between (cast ('1998-04-08' as date) - interval 30 day)
                    and (cast ('1998-04-08' as date) + interval 30 day)
   group by w_warehouse_name, i_item_id) x
 where (case when inv_before > 0 
             then inv_after / inv_before 
             else null
             end) between 2.0/3.0 and 3.0/2.0
 order by w_warehouse_name
         ,i_item_id
 limit 100;

-- ----------------------------------------------------------------------------
-- query22   base 15.3s  ->  indexed 70.5s   4.6x SLOWER   (+55.2s)
-- optimizer now uses:
--     inventory.idx_inv_item_sk (ref)
-- ----------------------------------------------------------------------------
select * from (
select  i_product_name
             ,i_brand
             ,i_class
             ,i_category
             ,avg(inv_quantity_on_hand) qoh
       from inventory
           ,date_dim
           ,item
       where inv_date_sk=d_date_sk
              and inv_item_sk=i_item_sk
              and d_month_seq between 1212 and 1212 + 11
       group by i_product_name
                       ,i_brand
                       ,i_class
                       ,i_category with rollup
) tpcds_rollup
order by qoh, i_product_name, i_brand, i_class, i_category
limit 100;

-- ----------------------------------------------------------------------------
-- query8   base 9.4s  ->  indexed 51.9s   5.5x SLOWER   (+42.5s)
-- optimizer now uses:
--     store_sales.idx_ss_sold_date_sk (range)
-- ----------------------------------------------------------------------------
select  s_store_name
      ,sum(ss_net_profit)
 from store_sales
     ,date_dim
     ,store,
     (select ca_zip
     from (
      SELECT substr(ca_zip,1,5) ca_zip
      FROM customer_address
      WHERE substr(ca_zip,1,5) IN (
                          '89436','30868','65085','22977','83927','77557',
                          '58429','40697','80614','10502','32779',
                          '91137','61265','98294','17921','18427',
                          '21203','59362','87291','84093','21505',
                          '17184','10866','67898','25797','28055',
                          '18377','80332','74535','21757','29742',
                          '90885','29898','17819','40811','25990',
                          '47513','89531','91068','10391','18846',
                          '99223','82637','41368','83658','86199',
                          '81625','26696','89338','88425','32200',
                          '81427','19053','77471','36610','99823',
                          '43276','41249','48584','83550','82276',
                          '18842','78890','14090','38123','40936',
                          '34425','19850','43286','80072','79188',
                          '54191','11395','50497','84861','90733',
                          '21068','57666','37119','25004','57835',
                          '70067','62878','95806','19303','18840',
                          '19124','29785','16737','16022','49613',
                          '89977','68310','60069','98360','48649',
                          '39050','41793','25002','27413','39736',
                          '47208','16515','94808','57648','15009',
                          '80015','42961','63982','21744','71853',
                          '81087','67468','34175','64008','20261',
                          '11201','51799','48043','45645','61163',
                          '48375','36447','57042','21218','41100',
                          '89951','22745','35851','83326','61125',
                          '78298','80752','49858','52940','96976',
                          '63792','11376','53582','18717','90226',
                          '50530','94203','99447','27670','96577',
                          '57856','56372','16165','23427','54561',
                          '28806','44439','22926','30123','61451',
                          '92397','56979','92309','70873','13355',
                          '21801','46346','37562','56458','28286',
                          '47306','99555','69399','26234','47546',
                          '49661','88601','35943','39936','25632',
                          '24611','44166','56648','30379','59785',
                          '11110','14329','93815','52226','71381',
                          '13842','25612','63294','14664','21077',
                          '82626','18799','60915','81020','56447',
                          '76619','11433','13414','42548','92713',
                          '70467','30884','47484','16072','38936',
                          '13036','88376','45539','35901','19506',
                          '65690','73957','71850','49231','14276',
                          '20005','18384','76615','11635','38177',
                          '55607','41369','95447','58581','58149',
                          '91946','33790','76232','75692','95464',
                          '22246','51061','56692','53121','77209',
                          '15482','10688','14868','45907','73520',
                          '72666','25734','17959','24677','66446',
                          '94627','53535','15560','41967','69297',
                          '11929','59403','33283','52232','57350',
                          '43933','40921','36635','10827','71286',
                          '19736','80619','25251','95042','15526',
                          '36496','55854','49124','81980','35375',
                          '49157','63512','28944','14946','36503',
                          '54010','18767','23969','43905','66979',
                          '33113','21286','58471','59080','13395',
                          '79144','70373','67031','38360','26705',
                          '50906','52406','26066','73146','15884',
                          '31897','30045','61068','45550','92454',
                          '13376','14354','19770','22928','97790',
                          '50723','46081','30202','14410','20223',
                          '88500','67298','13261','14172','81410',
                          '93578','83583','46047','94167','82564',
                          '21156','15799','86709','37931','74703',
                          '83103','23054','70470','72008','49247',
                          '91911','69998','20961','70070','63197',
                          '54853','88191','91830','49521','19454',
                          '81450','89091','62378','25683','61869',
                          '51744','36580','85778','36871','48121',
                          '28810','83712','45486','67393','26935',
                          '42393','20132','55349','86057','21309',
                          '80218','10094','11357','48819','39734',
                          '40758','30432','21204','29467','30214',
                          '61024','55307','74621','11622','68908',
                          '33032','52868','99194','99900','84936',
                          '69036','99149','45013','32895','59004',
                          '32322','14933','32936','33562','72550',
                          '27385','58049','58200','16808','21360',
                          '32961','18586','79307','15492')
     intersect
      select ca_zip
      from (SELECT substr(ca_zip,1,5) ca_zip,count(*) cnt
            FROM customer_address, customer
            WHERE ca_address_sk = c_current_addr_sk and
                  c_preferred_cust_flag='Y'
            group by ca_zip
            having count(*) > 10)A1)A2) V1
 where ss_store_sk = s_store_sk
  and ss_sold_date_sk = d_date_sk
  and d_qoy = 1 and d_year = 2002
  and (substr(s_zip,1,2) = substr(V1.ca_zip,1,2))
 group by s_store_name
 order by s_store_name
 limit 100;

-- ----------------------------------------------------------------------------
-- query88   base 48.2s  ->  indexed 83.9s   1.7x SLOWER   (+35.7s)
-- optimizer now uses:
--     store_sales.idx_ss_hdemo_sk (ref)
-- ----------------------------------------------------------------------------
select  *
from
 (select count(*) h8_30_to_9
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk   
     and ss_hdemo_sk = household_demographics.hd_demo_sk 
     and ss_store_sk = s_store_sk
     and time_dim.t_hour = 8
     and time_dim.t_minute >= 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2)) 
     and store.s_store_name = 'ese') s1,
 (select count(*) h9_to_9_30 
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk 
     and time_dim.t_hour = 9 
     and time_dim.t_minute < 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s2,
 (select count(*) h9_30_to_10 
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk
     and time_dim.t_hour = 9
     and time_dim.t_minute >= 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s3,
 (select count(*) h10_to_10_30
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk
     and time_dim.t_hour = 10 
     and time_dim.t_minute < 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s4,
 (select count(*) h10_30_to_11
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk
     and time_dim.t_hour = 10 
     and time_dim.t_minute >= 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s5,
 (select count(*) h11_to_11_30
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk 
     and time_dim.t_hour = 11
     and time_dim.t_minute < 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s6,
 (select count(*) h11_30_to_12
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk
     and time_dim.t_hour = 11
     and time_dim.t_minute >= 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s7,
 (select count(*) h12_to_12_30
 from store_sales, household_demographics , time_dim, store
 where ss_sold_time_sk = time_dim.t_time_sk
     and ss_hdemo_sk = household_demographics.hd_demo_sk
     and ss_store_sk = s_store_sk
     and time_dim.t_hour = 12
     and time_dim.t_minute < 30
     and ((household_demographics.hd_dep_count = 3 and household_demographics.hd_vehicle_count<=3+2) or
          (household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
          (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2))
     and store.s_store_name = 'ese') s8
;

-- ----------------------------------------------------------------------------
-- query68   base 9.3s  ->  indexed 44.3s   4.8x SLOWER   (+35.0s)
-- optimizer now uses:
--     store_sales.idx_ss_addr_sk (ref)
-- ----------------------------------------------------------------------------
select  c_last_name
       ,c_first_name
       ,ca_city
       ,bought_city
       ,ss_ticket_number
       ,extended_price
       ,extended_tax
       ,list_price
 from (select ss_ticket_number
             ,ss_customer_sk
             ,ca_city bought_city
             ,sum(ss_ext_sales_price) extended_price 
             ,sum(ss_ext_list_price) list_price
             ,sum(ss_ext_tax) extended_tax 
       from store_sales
           ,date_dim
           ,store
           ,household_demographics
           ,customer_address 
       where store_sales.ss_sold_date_sk = date_dim.d_date_sk
         and store_sales.ss_store_sk = store.s_store_sk  
        and store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
        and store_sales.ss_addr_sk = customer_address.ca_address_sk
        and date_dim.d_dom between 1 and 2 
        and (household_demographics.hd_dep_count = 5 or
             household_demographics.hd_vehicle_count= 3)
        and date_dim.d_year in (1999,1999+1,1999+2)
        and store.s_city in ('Midway','Fairview')
       group by ss_ticket_number
               ,ss_customer_sk
               ,ss_addr_sk,ca_city) dn
      ,customer
      ,customer_address current_addr
 where ss_customer_sk = c_customer_sk
   and customer.c_current_addr_sk = current_addr.ca_address_sk
   and current_addr.ca_city <> bought_city
 order by c_last_name
         ,ss_ticket_number
 limit 100;

-- ----------------------------------------------------------------------------
-- query46   base 8.8s  ->  indexed 42.8s   4.9x SLOWER   (+34.0s)
-- optimizer now uses:
--     store_sales.idx_ss_addr_sk (ref)
-- ----------------------------------------------------------------------------
select  c_last_name
       ,c_first_name
       ,ca_city
       ,bought_city
       ,ss_ticket_number
       ,amt,profit 
 from
   (select ss_ticket_number
          ,ss_customer_sk
          ,ca_city bought_city
          ,sum(ss_coupon_amt) amt
          ,sum(ss_net_profit) profit
    from store_sales,date_dim,store,household_demographics,customer_address 
    where store_sales.ss_sold_date_sk = date_dim.d_date_sk
    and store_sales.ss_store_sk = store.s_store_sk  
    and store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
    and store_sales.ss_addr_sk = customer_address.ca_address_sk
    and (household_demographics.hd_dep_count = 5 or
         household_demographics.hd_vehicle_count= 3)
    and date_dim.d_dow in (6,0)
    and date_dim.d_year in (1999,1999+1,1999+2) 
    and store.s_city in ('Midway','Fairview','Fairview','Fairview','Fairview') 
    group by ss_ticket_number,ss_customer_sk,ss_addr_sk,ca_city) dn,customer,customer_address current_addr
    where ss_customer_sk = c_customer_sk
      and customer.c_current_addr_sk = current_addr.ca_address_sk
      and current_addr.ca_city <> bought_city
  order by c_last_name
          ,c_first_name
          ,ca_city
          ,bought_city
          ,ss_ticket_number
  limit 100;

-- ----------------------------------------------------------------------------
-- query35   base 14.9s  ->  indexed 44.4s   3.0x SLOWER   (+29.5s)
-- optimizer now uses:
--     store_sales.idx_ss_sold_date_sk (range)
-- ----------------------------------------------------------------------------
select   
  ca_state,
  cd_gender,
  cd_marital_status,
  cd_dep_count,
  count(*) cnt1,
  avg(cd_dep_count) aggone1,
  max(cd_dep_count) aggtwo1,
  sum(cd_dep_count) aggthree1,
  cd_dep_employed_count,
  count(*) cnt2,
  avg(cd_dep_employed_count) aggone2,
  max(cd_dep_employed_count) aggtwo2,
  sum(cd_dep_employed_count) aggthree2,
  cd_dep_college_count,
  count(*) cnt3,
  avg(cd_dep_college_count) aggone3,
  max(cd_dep_college_count) aggtwo3,
  sum(cd_dep_college_count) aggthree3
 from
  customer c,customer_address ca,customer_demographics
 where
  c.c_current_addr_sk = ca.ca_address_sk and
  cd_demo_sk = c.c_current_cdemo_sk and 
  exists (select *
          from store_sales,date_dim
          where c.c_customer_sk = ss_customer_sk and
                ss_sold_date_sk = d_date_sk and
                d_year = 1999 and
                d_qoy < 4) and
   (exists (select *
            from web_sales,date_dim
            where c.c_customer_sk = ws_bill_customer_sk and
                  ws_sold_date_sk = d_date_sk and
                  d_year = 1999 and
                  d_qoy < 4) or 
    exists (select * 
            from catalog_sales,date_dim
            where c.c_customer_sk = cs_ship_customer_sk and
                  cs_sold_date_sk = d_date_sk and
                  d_year = 1999 and
                  d_qoy < 4))
 group by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 order by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 limit 100;

-- ----------------------------------------------------------------------------
-- query79   base 7.7s  ->  indexed 31.0s   4.0x SLOWER   (+23.3s)
-- optimizer now uses:
--     store_sales.idx_ss_hdemo_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query10   base 22.8s  ->  indexed 43.9s   1.9x SLOWER   (+21.1s)
-- optimizer now uses:
--     store_sales.idx_ss_sold_date_sk (range)
-- ----------------------------------------------------------------------------
select  
  cd_gender,
  cd_marital_status,
  cd_education_status,
  count(*) cnt1,
  cd_purchase_estimate,
  count(*) cnt2,
  cd_credit_rating,
  count(*) cnt3,
  cd_dep_count,
  count(*) cnt4,
  cd_dep_employed_count,
  count(*) cnt5,
  cd_dep_college_count,
  count(*) cnt6
 from
  customer c,customer_address ca,customer_demographics
 where
  c.c_current_addr_sk = ca.ca_address_sk and
  ca_county in ('Walker County','Richland County','Gaines County','Douglas County','Dona Ana County') and
  cd_demo_sk = c.c_current_cdemo_sk and 
  exists (select *
          from store_sales,date_dim
          where c.c_customer_sk = ss_customer_sk and
                ss_sold_date_sk = d_date_sk and
                d_year = 2002 and
                d_moy between 4 and 4+3) and
   (exists (select *
            from web_sales,date_dim
            where c.c_customer_sk = ws_bill_customer_sk and
                  ws_sold_date_sk = d_date_sk and
                  d_year = 2002 and
                  d_moy between 4 ANd 4+3) or 
    exists (select * 
            from catalog_sales,date_dim
            where c.c_customer_sk = cs_ship_customer_sk and
                  cs_sold_date_sk = d_date_sk and
                  d_year = 2002 and
                  d_moy between 4 and 4+3))
 group by cd_gender,
          cd_marital_status,
          cd_education_status,
          cd_purchase_estimate,
          cd_credit_rating,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 order by cd_gender,
          cd_marital_status,
          cd_education_status,
          cd_purchase_estimate,
          cd_credit_rating,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
limit 100;

-- ----------------------------------------------------------------------------
-- query15   base 5.4s  ->  indexed 21.4s   4.0x SLOWER   (+16.0s)
-- optimizer now uses:
--     customer.idx_c_current_addr_sk (ref)
--     catalog_sales.idx_cs_bill_customer_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query13   base 2.6s  ->  indexed 12.6s   4.8x SLOWER   (+10.0s)
-- optimizer now uses:
--     customer_address.idx_customer_address_1 (range)
--     store_sales.idx_ss_addr_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query99   base 3.0s  ->  indexed 11.7s   3.9x SLOWER   (+8.7s)
-- optimizer now uses:
--     catalog_sales.idx_cs_ship_date_sk (range)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query48   base 8.2s  ->  indexed 14.6s   1.8x SLOWER   (+6.4s)
-- optimizer now uses:
--     customer_address.idx_customer_address_1 (range)
--     store_sales.idx_ss_addr_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query73   base 10.6s  ->  indexed 15.2s   1.4x SLOWER   (+4.6s)
-- optimizer now uses:
--     store_sales.idx_ss_hdemo_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query77   base 14.7s  ->  indexed 17.8s   1.2x SLOWER   (+3.1s)
-- optimizer now uses:
--     store_returns.idx_sr_store_sk (ref)
--     web_sales.idx_ws_web_page_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query29   base 5.4s  ->  indexed 8.3s   1.5x SLOWER   (+2.9s)
-- optimizer now uses:
--     catalog_sales.idx_cs_bill_customer_sk (ref)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- query91   base 0.4s  ->  indexed 1.6s   4.0x SLOWER   (+1.2s)
-- optimizer now uses:
--     customer.idx_c_current_addr_sk (ref)
--     catalog_returns.idx_cr_returning_customer_sk (ref)
-- ----------------------------------------------------------------------------
select  
        cc_call_center_id Call_Center,
        cc_name Call_Center_Name,
        cc_manager Manager,
        sum(cr_net_loss) Returns_Loss
from
        call_center,
        catalog_returns,
        date_dim,
        customer,
        customer_address,
        customer_demographics,
        household_demographics
where
        cr_call_center_sk       = cc_call_center_sk
and     cr_returned_date_sk     = d_date_sk
and     cr_returning_customer_sk= c_customer_sk
and     cd_demo_sk              = c_current_cdemo_sk
and     hd_demo_sk              = c_current_hdemo_sk
and     ca_address_sk           = c_current_addr_sk
and     d_year                  = 1999 
and     d_moy                   = 11
and     ( (cd_marital_status       = 'M' and cd_education_status     = 'Unknown')
        or(cd_marital_status       = 'W' and cd_education_status     = 'Advanced Degree'))
and     hd_buy_potential like '0-500%'
and     ca_gmt_offset           = -7
group by cc_call_center_id,cc_name,cc_manager,cd_marital_status,cd_education_status
order by sum(cr_net_loss) desc;

