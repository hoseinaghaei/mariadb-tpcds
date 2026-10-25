-- q23 v1: replace the IN subqueries with joins.  No temporary tables.
--
-- ANALYZE FORMAT=JSON on the original, for EACH of the two statements:
--
--     ms      node           loops
--   30,782    materialized   55,882
--   15,537    materialized   28,222
--   12,485    materialized    1,987
--   10,918    materialized    1,034
--
-- 79.8s of statement 1's 90.2s.  The loops come from the IN subqueries:
-- frequent_ss_items and best_ss_customer are each referenced twice per
-- statement, once per union branch, and get re-materialised per outer row.
--
-- Written as joins, each set is produced once and probed, rather than
-- rebuilt.  Two details make the rewrite exact:
--
--  * frequent_ss_items groups by (itemdesc, item_sk, d_date), so the same
--    item_sk can appear on several rows.  A plain join would multiply the
--    fact rows.  SELECT DISTINCT item_sk restores the IN semantics, which
--    only ever asked set membership.
--  * best_ss_customer groups by c_customer_sk, so that key is already
--    unique and the join cannot duplicate.
--
-- The 95th-percentile threshold stays a scalar subquery: it yields one row
-- and is evaluated once.
--
-- The customer join in statement 2 must be qualified: best_ss_customer also
-- exposes c_customer_sk, and an unqualified reference is ambiguous
-- (ERROR 1052).  The original had no such clash because it used IN rather
-- than a join, so the CTE's column was never in scope there.

with frequent_ss_items as
 (select distinct item_sk from (
   select i_item_sk item_sk
    from store_sales
        ,date_dim
        ,item
    where ss_sold_date_sk = d_date_sk
      and ss_item_sk = i_item_sk
      and d_year in (1999,1999+1,1999+2,1999+3)
    group by substr(i_item_desc,1,30),i_item_sk,d_date
    having count(*) >4) fsi_grouped),
 max_store_sales as
 (select max(csales) tpcds_cmax
  from (select c_customer_sk,sum(ss_quantity*ss_sales_price) csales
        from store_sales
            ,customer
            ,date_dim
        where ss_customer_sk = c_customer_sk
         and ss_sold_date_sk = d_date_sk
         and d_year in (1999,1999+1,1999+2,1999+3)
        group by c_customer_sk) as TBL_1),
 best_ss_customer as
 (select c_customer_sk
  from store_sales
      ,customer
  where ss_customer_sk = c_customer_sk
  group by c_customer_sk
  having sum(ss_quantity*ss_sales_price) > (95/100.0) * (select tpcds_cmax from max_store_sales))
  select  sum(sales)
 from (select cs_quantity*cs_list_price sales
       from catalog_sales
       join date_dim            on cs_sold_date_sk = d_date_sk
       join frequent_ss_items f on cs_item_sk = f.item_sk
       join best_ss_customer  b on cs_bill_customer_sk = b.c_customer_sk
       where d_year = 1999
         and d_moy = 7
      union all
      select ws_quantity*ws_list_price sales
       from web_sales
       join date_dim            on ws_sold_date_sk = d_date_sk
       join frequent_ss_items f on ws_item_sk = f.item_sk
       join best_ss_customer  b on ws_bill_customer_sk = b.c_customer_sk
       where d_year = 1999
         and d_moy = 7) as TBL_2
 limit 100;

with frequent_ss_items as
 (select distinct item_sk from (
   select i_item_sk item_sk
    from store_sales
        ,date_dim
        ,item
    where ss_sold_date_sk = d_date_sk
      and ss_item_sk = i_item_sk
      and d_year in (1999,1999+1,1999+2,1999+3)
    group by substr(i_item_desc,1,30),i_item_sk,d_date
    having count(*) >4) fsi_grouped),
 max_store_sales as
 (select max(csales) tpcds_cmax
  from (select c_customer_sk,sum(ss_quantity*ss_sales_price) csales
        from store_sales
            ,customer
            ,date_dim
        where ss_customer_sk = c_customer_sk
         and ss_sold_date_sk = d_date_sk
         and d_year in (1999,1999+1,1999+2,1999+3)
        group by c_customer_sk) as TBL_3 ),
 best_ss_customer as
 (select c_customer_sk
  from store_sales
      ,customer
  where ss_customer_sk = c_customer_sk
  group by c_customer_sk
  having sum(ss_quantity*ss_sales_price) > (95/100.0) * (select tpcds_cmax from max_store_sales))
  select  c_last_name,c_first_name,sales
 from (select c_last_name,c_first_name,sum(cs_quantity*cs_list_price) sales
        from catalog_sales
        join date_dim            on cs_sold_date_sk = d_date_sk
        join frequent_ss_items f on cs_item_sk = f.item_sk
        join best_ss_customer  b on cs_bill_customer_sk = b.c_customer_sk
        join customer            on cs_bill_customer_sk = customer.c_customer_sk
        where d_year = 1999
         and d_moy = 7
       group by c_last_name,c_first_name
      union all
      select c_last_name,c_first_name,sum(ws_quantity*ws_list_price) sales
       from web_sales
       join date_dim            on ws_sold_date_sk = d_date_sk
       join frequent_ss_items f on ws_item_sk = f.item_sk
       join best_ss_customer  b on ws_bill_customer_sk = b.c_customer_sk
       join customer            on ws_bill_customer_sk = customer.c_customer_sk
       where d_year = 1999
         and d_moy = 7
       group by c_last_name,c_first_name) as TBL_4
     order by c_last_name,c_first_name,sales
  limit 100;
