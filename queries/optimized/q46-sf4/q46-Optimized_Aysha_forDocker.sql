-- query46
-- source: queries/optimized/q46-sf4/query46_v1_datefirst.sql
-- split materialisation at default: -1.6s is inside this host's noise

analyze table store_sales;

CREATE INDEX idx_q46_cover ON store_sales
  (ss_sold_date_sk, ss_store_sk, ss_hdemo_sk, ss_addr_sk,
   ss_ticket_number, ss_customer_sk, ss_coupon_amt, ss_net_profit);

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

analyze format=json
select straight_join c_last_name
       ,c_first_name
       ,current_addr.ca_city
       ,dn.bought_city
       ,dn.ss_ticket_number
       ,dn.amt
       ,dn.profit
 from
   (select straight_join ss_ticket_number
          ,ss_customer_sk
          ,ca_city bought_city
          ,sum(ss_coupon_amt) amt
          ,sum(ss_net_profit) profit
    from date_dim
    straight_join store_sales force index (idx_q46_cover)
           on store_sales.ss_sold_date_sk = date_dim.d_date_sk
    straight_join household_demographics
           on store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
    straight_join store
           on store_sales.ss_store_sk = store.s_store_sk
    straight_join customer_address
           on store_sales.ss_addr_sk = customer_address.ca_address_sk
    where (household_demographics.hd_dep_count = 5 or
           household_demographics.hd_vehicle_count = 0)
    and date_dim.d_dow in (6,0)
    and date_dim.d_year in (1999,1999+1,1999+2)
    and store.s_city in ('Fairview','Midway')
    group by ss_ticket_number, ss_customer_sk, ss_addr_sk, ca_city) dn
 straight_join customer
        on dn.ss_customer_sk = customer.c_customer_sk
 straight_join customer_address current_addr
        on customer.c_current_addr_sk = current_addr.ca_address_sk
 where current_addr.ca_city <> dn.bought_city
 order by c_last_name, c_first_name, current_addr.ca_city,
          dn.bought_city, dn.ss_ticket_number
 limit 100;