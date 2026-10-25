-- query54
-- source: queries/optimized/Aysha/q54/q54_Optimized_V2.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

with my_customers as (
 select straight_join c_customer_sk, c_current_addr_sk
 from (
        select cs_bill_customer_sk as customer_sk
        from   date_dim, catalog_sales, item
        where  cs_sold_date_sk = d_date_sk
          and  cs_item_sk = i_item_sk
          and  d_year = 2000 and d_moy = 7
          and  i_category = 'Women' and i_class = 'swimwear'
        union
        select ws_bill_customer_sk
        from   date_dim, web_sales, item
        where  ws_sold_date_sk = d_date_sk
          and  ws_item_sk = i_item_sk
          and  d_year = 2000 and d_moy = 7
          and  i_category = 'Women' and i_class = 'swimwear'
      ) u
      join customer on c_customer_sk = u.customer_sk
)
, my_revenue as (
 select straight_join mc.c_customer_sk,
        sum(ss_ext_sales_price) as revenue
 from   my_customers mc
        join customer_address on mc.c_current_addr_sk = ca_address_sk
        join store on ca_county = s_county and ca_state = s_state
        join store_sales on ss_customer_sk = mc.c_customer_sk
        join date_dim on ss_sold_date_sk = d_date_sk
 where  d_month_seq between (select distinct d_month_seq+1
                             from   date_dim where d_year = 2000 and d_moy = 7)
                        and (select distinct d_month_seq+3
                             from   date_dim where d_year = 2000 and d_moy = 7)
 group by mc.c_customer_sk
)
, segments as (
 select cast((revenue/50) as int) as segment
 from   my_revenue
)
select segment, count(*) as num_customers, segment*50 as segment_base
from segments
group by segment
order by segment, num_customers
limit 100;
