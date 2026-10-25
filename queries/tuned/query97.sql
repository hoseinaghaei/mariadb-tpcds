-- query97
-- source: queries/optimized/Aysha/q97/query97_BEST_no_temp_tables.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

with ssci as (
  select ss_customer_sk customer_sk
        ,ss_item_sk item_sk
  from store_sales, date_dim
  where ss_sold_date_sk = d_date_sk
    and d_month_seq between 1176 and 1176 + 11
  group by ss_customer_sk, ss_item_sk),
csci as (
  select cs_bill_customer_sk customer_sk
        ,cs_item_sk item_sk
  from catalog_sales, date_dim
  where cs_sold_date_sk = d_date_sk
    and d_month_seq between 1176 and 1176 + 11
  group by cs_bill_customer_sk, cs_item_sk)
select
   sum(c.customer_sk is null and s.customer_sk is not null) store_only
  ,(select count(*) from csci) - sum(c.customer_sk is not null) catalog_only
  ,sum(c.customer_sk is not null) store_and_catalog
from ssci s
left join csci c
  on s.customer_sk = c.customer_sk
 and s.item_sk = c.item_sk
limit 100;
