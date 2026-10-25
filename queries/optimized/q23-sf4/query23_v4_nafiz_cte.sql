-- q23 v4 -- Nafiz's pruning, expressed as CTEs, on top of v3's key ranges.
--
-- Nafiz pushed queries/optimized/Nafiz/q23/ with a 38.0x result at SF=1
-- (54.293s -> 1.427s median).  His BEST builds five TEMPORARY TABLEs, which
-- this project does not accept, so this file keeps his two real ideas and
-- expresses them as CTEs.  He also independently verified the same date-key
-- bounds used in v3 -- 2451180..2452640 is exactly 1999-01-01..2002-12-31.
--
-- HIS FIRST IDEA, and the one v3 missed: prune the frequent-item scan by
-- customer first.  v3 computes frequent_ss_items over every item in four
-- years of store_sales -- 1,423 rows out of a ~9M-row scan -- and then the
-- outer query throws nearly all of it away.  An item can only matter if some
-- *best* customer bought it through catalog or web in July 1999, and that is
-- a tiny set.  Computing the candidates first and restricting the frequency
-- test to them is a valid pushdown: the outer query's filter is
-- `item in frequent AND customer in best`, so an item outside the candidate
-- set cannot reach the result however frequent it is.
--
-- HIS SECOND IDEA: one pass over store_sales for both customer aggregates.
-- The original computes max_store_sales (date-filtered) and best_ss_customer
-- (all dates) as two separate scans; a CASE inside a single GROUP BY yields
-- both.  Customers with no sales in the window get period_sales = NULL, and
-- MAX ignores NULLs, so the threshold is unchanged.
--
-- KEPT FROM v3: the dimension joins become surrogate-key ranges.  date_dim
-- is dense (73,049 rows over 2,415,022..2,488,070, span == count), so
--      d_year in (1999..2002)      -> 2451180..2452640
--      d_year = 1999 and d_moy = 7 -> 2451361..2451391
-- and `ss_customer_sk is not null` replaces the customer join, because
-- customer is dense 1..233,000 and every non-NULL key falls inside it.  The
-- NOT NULL test is required: without it the NULL-customer rows collapse into
-- one group whose sum could become the threshold.
--
-- The `item` join is gone for the same reason as in v3:
-- substr(i_item_desc,1,30) is functionally dependent on i_item_sk, which is
-- unique in item, so it splits no group, and ss_item_sk is NOT NULL across
-- all 11,519,024 rows and spans exactly item's dense 1..46,000.
--
-- Both statements repeat the CTEs because MariaDB cannot carry them across
-- statements without the temporary tables this file exists to avoid.

with cust as (
  select ss_customer_sk,
         sum(ss_quantity*ss_sales_price) as all_sales,
         sum(case when ss_sold_date_sk between 2451180 and 2452640
                  then ss_quantity*ss_sales_price end) as period_sales
  from store_sales
  where ss_customer_sk is not null
  group by ss_customer_sk),
 best_ss_customer as (
  select ss_customer_sk as c_customer_sk
  from cust
  where all_sales > (95/100.0) * (select max(period_sales) from cust)),
 candidate_items as (
  select distinct item_sk from (
    select cs_item_sk as item_sk
    from catalog_sales
    where cs_sold_date_sk between 2451361 and 2451391
      and cs_bill_customer_sk in (select c_customer_sk from best_ss_customer)
    union all
    select ws_item_sk as item_sk
    from web_sales
    where ws_sold_date_sk between 2451361 and 2451391
      and ws_bill_customer_sk in (select c_customer_sk from best_ss_customer)
  ) as channel_items),
 frequent_ss_items as (
  select ss_item_sk item_sk
  from store_sales
  where ss_sold_date_sk between 2451180 and 2452640
    and ss_item_sk in (select item_sk from candidate_items)
  group by ss_sold_date_sk, ss_item_sk
  having count(*) > 4)
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

with cust as (
  select ss_customer_sk,
         sum(ss_quantity*ss_sales_price) as all_sales,
         sum(case when ss_sold_date_sk between 2451180 and 2452640
                  then ss_quantity*ss_sales_price end) as period_sales
  from store_sales
  where ss_customer_sk is not null
  group by ss_customer_sk),
 best_ss_customer as (
  select ss_customer_sk as c_customer_sk
  from cust
  where all_sales > (95/100.0) * (select max(period_sales) from cust)),
 candidate_items as (
  select distinct item_sk from (
    select cs_item_sk as item_sk
    from catalog_sales
    where cs_sold_date_sk between 2451361 and 2451391
      and cs_bill_customer_sk in (select c_customer_sk from best_ss_customer)
    union all
    select ws_item_sk as item_sk
    from web_sales
    where ws_sold_date_sk between 2451361 and 2451391
      and ws_bill_customer_sk in (select c_customer_sk from best_ss_customer)
  ) as channel_items),
 frequent_ss_items as (
  select ss_item_sk item_sk
  from store_sales
  where ss_sold_date_sk between 2451180 and 2452640
    and ss_item_sk in (select item_sk from candidate_items)
  group by ss_sold_date_sk, ss_item_sk
  having count(*) > 4)
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
