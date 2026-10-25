-- query23
-- source: queries/optimized/q23-sf4/query23_v3_densekeys.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

with frequent_ss_items as
 (select ss_item_sk item_sk
  from store_sales
  where ss_sold_date_sk between 2451180 and 2452640
  group by ss_sold_date_sk, ss_item_sk
  having count(*) > 4),
 max_store_sales as
 (select max(csales) tpcds_cmax
  from (select sum(ss_quantity*ss_sales_price) csales
        from store_sales
        where ss_sold_date_sk between 2451180 and 2452640
          and ss_customer_sk is not null
        group by ss_customer_sk) as TBL_1),
 best_ss_customer as
 (select ss_customer_sk c_customer_sk,sum(ss_quantity*ss_sales_price) ssales
  from store_sales
  where ss_customer_sk is not null
  group by ss_customer_sk
  having sum(ss_quantity*ss_sales_price) > (95/100.0) * (select
  *
from
 max_store_sales))
  select  sum(sales)
 from (select cs_quantity*cs_list_price sales
       from catalog_sales
       where cs_sold_date_sk between 2451361 and 2451391
         and cs_item_sk in (select item_sk from frequent_ss_items)
         and cs_bill_customer_sk in (select c_customer_sk from best_ss_customer)
      union all
      select ws_quantity*ws_list_price sales
       from web_sales
       where ws_sold_date_sk between 2451361 and 2451391
         and ws_item_sk in (select item_sk from frequent_ss_items)
         and ws_bill_customer_sk in (select c_customer_sk from best_ss_customer)) as TBL_2
 limit 100;
with frequent_ss_items as
 (select ss_item_sk item_sk
  from store_sales
  where ss_sold_date_sk between 2451180 and 2452640
  group by ss_sold_date_sk, ss_item_sk
  having count(*) > 4),
 max_store_sales as
 (select max(csales) tpcds_cmax
  from (select sum(ss_quantity*ss_sales_price) csales
        from store_sales
        where ss_sold_date_sk between 2451180 and 2452640
          and ss_customer_sk is not null
        group by ss_customer_sk) as TBL_3 ),
 best_ss_customer as
 (select ss_customer_sk c_customer_sk,sum(ss_quantity*ss_sales_price) ssales
  from store_sales
  where ss_customer_sk is not null
  group by ss_customer_sk
  having sum(ss_quantity*ss_sales_price) > (95/100.0) * (select
  *
 from max_store_sales))
  select  c_last_name,c_first_name,sales
 from (select c_last_name,c_first_name,sum(cs_quantity*cs_list_price) sales
        from catalog_sales
            ,customer
        where cs_sold_date_sk between 2451361 and 2451391
         and cs_item_sk in (select item_sk from frequent_ss_items)
         and cs_bill_customer_sk in (select c_customer_sk from best_ss_customer)
         and cs_bill_customer_sk = c_customer_sk
       group by c_last_name,c_first_name
      union all
      select c_last_name,c_first_name,sum(ws_quantity*ws_list_price) sales
       from web_sales
           ,customer
       where ws_sold_date_sk between 2451361 and 2451391
         and ws_item_sk in (select item_sk from frequent_ss_items)
         and ws_bill_customer_sk in (select c_customer_sk from best_ss_customer)
         and ws_bill_customer_sk = c_customer_sk
       group by c_last_name,c_first_name) as TBL_4
     order by c_last_name,c_first_name,sales
  limit 100;
