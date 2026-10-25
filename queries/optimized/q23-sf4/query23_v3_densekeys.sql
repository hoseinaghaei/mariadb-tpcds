-- q23 v3 -- strip the three CTEs down to single-table aggregates.
--
-- ANALYZE FORMAT=JSON on the original, SF=4:
--
--   statement 1  120,240ms      statement 2   87,873ms
--     <derived2>   x55,882  35,937ms            x55,882  30,162ms
--     <derived13>  x28,222  17,183ms            x28,222  15,785ms
--     <derived5>    x1,987  31,274ms             x1,987  11,862ms
--     <derived14>   x1,034  14,547ms             x1,034  10,372ms
--
-- <derived2>/<derived13> are both `frequent_ss_items`, split-materialised
-- once per surviving outer row: 99.1s of the 208.1s the query spends under
-- ANALYZE.  Making that CTE cheap is the whole optimization.
--
-- Four rewrites, each an equivalence that holds on the TPC-DS schema and was
-- confirmed against this database before use:
--
--  1. frequent_ss_items drops the `item` join.  Its only purpose is
--     substr(i_item_desc,1,30) in the GROUP BY, and i_item_sk is unique in
--     item (46,000 rows / 46,000 distinct), so that expression is
--     functionally dependent on a column already in the key -- it splits no
--     group.  The join itself discards nothing: ss_item_sk is NOT NULL in all
--     11,519,024 rows and spans exactly 1..46,000, matching item's dense
--     range.  Downstream only ever reads item_sk.
--
--  2. The date_dim joins become ranges on the surrogate key.  date_dim holds
--     73,049 rows over d_date_sk 2,415,022..2,488,070 with no gaps
--     (span == count), so a contiguous set of days is a contiguous key range:
--        d_year in (1999..2002)      ->  2,451,180 .. 2,452,640   (1,461 days)
--        d_year = 1999 and d_moy = 7 ->  2,451,361 .. 2,451,391   (31 days)
--     Both verified as span == count.  date_dim is a fixed TPC-DS dimension
--     -- 73,049 rows at every scale factor -- so these bounds are not
--     SF=4-specific.  BETWEEN also excludes NULL, which is what the inner
--     join did with the 519,301 NULL ss_sold_date_sk rows.
--
--     This is also what fixes the second defect: the original plan reached
--     catalog_sales by ALL (5,759,989 rows) and probed date_dim 5,716,991
--     times to keep ~55,882.  A range on cs_sold_date_sk drives the selective
--     side first, the way q68 and q46 were fixed.
--
--  3. Grouping is by (ss_sold_date_sk, ss_item_sk), not (item, date).  Same
--     groups -- GROUP BY is order-insensitive -- but it now matches the
--     leading columns of idx_ss_date_item_store_cover
--     (ss_sold_date_sk, ss_item_sk, ss_store_sk, ss_sales_price), so the CTE
--     is answerable by an ordered index-only scan instead of building a temp
--     table keyed on a 30-character varchar.
--
--  4. The customer joins drop to `ss_customer_sk is not null`.  customer is
--     dense 1..233,000 and every non-NULL ss_customer_sk falls inside it, so
--     the join removed exactly the 518,489 NULL rows and nothing else.  The
--     IS NOT NULL test has to stay: without it those rows collapse into one
--     group whose sum could become max_store_sales and change the answer.
--
-- Output is unchanged; see test-v3.sh, which compares the CTE cardinalities
-- as well as the final rows (q23 returns a NULL and no rows at SF=4, so the
-- final answer alone is too weak a check).

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
