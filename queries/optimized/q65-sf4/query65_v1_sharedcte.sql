-- q65 v1 -- aggregate store_sales once instead of twice.
--
-- The original contains the same derived table twice, written out in full
-- both times:
--
--   (select ss_store_sk, ss_item_sk, sum(ss_sales_price) as revenue
--      from store_sales, date_dim
--     where ss_sold_date_sk = d_date_sk and d_month_seq between 1176 and 1176+11
--     group by ss_store_sk, ss_item_sk)
--
-- once as `sa` (wrapped by `sb`, which averages it per store) and once as
-- `sc` (joined to store and item).  Because the two spellings are separate
-- derived tables, a 12-month window of store_sales is scanned and grouped
-- twice -- and the earlier ANALYZE of this query showed <derived3> being
-- scanned ALL at 1,048,697 rows with `temporary + filesort`.
--
-- Naming it once as a CTE and referring to it twice lets it materialise once
-- and be read twice.  sb is then an aggregate over sc rather than a second
-- pass over the fact table: avg(revenue) grouped by store, over exactly the
-- rows sc already holds, which is what `sa` was.
--
-- d_month_seq between 1176 and 1176+11 is the contiguous key range
-- 2450815..2451179 (365 rows, span 365 -- calendar year 1998), and date_dim
-- is dense over 2415022..2488070, so the join becomes a BETWEEN on
-- ss_sold_date_sk.  d_date_sk is not read anywhere else, and BETWEEN
-- excludes the NULL foreign keys the inner join excluded.
--
-- Nothing else moves: the store and item joins, the `sc.revenue <= 0.1*sb.ave`
-- predicate, the ORDER BY and the LIMIT are as they were.

with sc as (
  select ss_store_sk, ss_item_sk, sum(ss_sales_price) as revenue
  from store_sales
  where ss_sold_date_sk between 2450815 and 2451179
  group by ss_store_sk, ss_item_sk
),
sb as (
  select ss_store_sk, avg(revenue) as ave
  from sc
  group by ss_store_sk
)
select
	s_store_name,
	i_item_desc,
	sc.revenue,
	i_current_price,
	i_wholesale_cost,
	i_brand
 from store, item, sb, sc
 where sb.ss_store_sk = sc.ss_store_sk and
       sc.revenue <= 0.1 * sb.ave and
       s_store_sk = sc.ss_store_sk and
       i_item_sk = sc.ss_item_sk
 order by s_store_name, i_item_desc
limit 100;
