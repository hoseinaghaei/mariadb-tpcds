-- q23 v2: union the two channels FIRST, then join the shared sets once.
--
-- v1 converted the IN subqueries to joins and gained only 3% (171.5s ->
-- 166.1s).  The reason is that it left the structure alone: both
-- frequent_ss_items and best_ss_customer are still referenced TWICE per
-- statement, once in each union branch, so each is still built twice.
--
-- ANALYZE FORMAT=JSON on the original showed exactly that, per statement:
--   30,782 ms over 55,882 loops, 15,537 ms over 28,222 loops.
--
-- v2 reshapes it:
--
--     (catalog JOIN fsi JOIN bsc) UNION ALL (web JOIN fsi JOIN bsc)
--  -> (catalog UNION ALL web) JOIN fsi JOIN bsc
--
-- Each set is now referenced once per statement instead of twice.
--
-- The date filter stays INSIDE each branch rather than moving after the
-- union: d_year=1999 AND d_moy=7 is the most selective predicate here, and
-- applying it before the union keeps the unioned set small.  Moving it out
-- would union two whole fact tables first.
--
-- Semantics are unchanged.  UNION ALL preserves every row, the join keys are
-- the same, and fsi is still DISTINCT so set membership cannot multiply rows
-- (its grouping by (itemdesc, item_sk, d_date) repeats item_sk otherwise).
-- best_ss_customer groups by c_customer_sk, so it is unique already.

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
 from (select u.quantity * u.list_price sales
       from (select cs_item_sk item_sk, cs_bill_customer_sk cust_sk
                   ,cs_quantity quantity, cs_list_price list_price
             from catalog_sales, date_dim
             where cs_sold_date_sk = d_date_sk and d_year = 1999 and d_moy = 7
             union all
             select ws_item_sk, ws_bill_customer_sk
                   ,ws_quantity, ws_list_price
             from web_sales, date_dim
             where ws_sold_date_sk = d_date_sk and d_year = 1999 and d_moy = 7) u
       join frequent_ss_items f on u.item_sk = f.item_sk
       join best_ss_customer  b on u.cust_sk = b.c_customer_sk) as TBL_2
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
 from (select c_last_name,c_first_name,sum(u.quantity * u.list_price) sales
       from (select cs_item_sk item_sk, cs_bill_customer_sk cust_sk
                   ,cs_quantity quantity, cs_list_price list_price
             from catalog_sales, date_dim
             where cs_sold_date_sk = d_date_sk and d_year = 1999 and d_moy = 7
             union all
             select ws_item_sk, ws_bill_customer_sk
                   ,ws_quantity, ws_list_price
             from web_sales, date_dim
             where ws_sold_date_sk = d_date_sk and d_year = 1999 and d_moy = 7) u
       join frequent_ss_items f on u.item_sk = f.item_sk
       join best_ss_customer  b on u.cust_sk = b.c_customer_sk
       join customer            on u.cust_sk = customer.c_customer_sk
       group by c_last_name,c_first_name) as TBL_4
     order by c_last_name,c_first_name,sales
  limit 100;
