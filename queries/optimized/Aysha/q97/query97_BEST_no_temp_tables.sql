-- q97, Aysha's optimization expressed with CTEs instead of temporary tables.
--
-- Her q97_BEST.sql builds ssci_t and csci_t as TEMPORARY TABLES.  Temporary
-- tables are not acceptable for this project, so the same two sets are
-- defined as CTEs here.  Nothing else changes.
--
-- Her insight is kept, and it is the valuable part: the original emulates a
-- FULL OUTER JOIN as (LEFT JOIN) UNION ALL (RIGHT JOIN ... WHERE a IS NULL),
-- which reads both sides twice.  This computes one LEFT JOIN and derives the
-- catalog-only count arithmetically:
--
--     catalog_only = (rows in csci) - (rows of csci that matched)
--
-- That is exact because both CTEs GROUP BY (customer_sk, item_sk), so each
-- pair occurs at most once on either side and a match cannot be counted
-- twice.
--
-- `limit 100` is retained from the original; the result is a single row, so
-- it changes nothing, but it keeps the statement identical in shape.

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
