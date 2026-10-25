-- q35 v1 -- make the three EXISTS checks index-only.
--
-- Each of q35's three EXISTS subqueries joins date_dim purely to apply
-- `d_year = 1999 and d_qoy < 4`.  Those 274 days are the contiguous key range
-- d_date_sk 2451180..2451453 (274 rows, span 274), and date_dim is dense over
-- 2415022..2488070, so the join becomes a BETWEEN on each fact table's own
-- foreign key.  Nothing in the subqueries reads a date_dim column -- they are
-- `exists (select *)`, so the projection is discarded -- and BETWEEN excludes
-- the NULL foreign keys the inner join excluded.
--
-- The point is not just removing a join.  With date_dim gone, each subquery
-- references exactly two columns, and each one has an index that holds both,
-- in that order:
--
--   store_sales    (ss_customer_sk, ss_sold_date_sk)       idx_ss_cust_date
--   catalog_sales  (cs_ship_customer_sk, cs_sold_date_sk)  idx_cs_cust_date
--   web_sales      (ws_bill_customer_sk, ws_sold_date_sk)  idx_ws_cust_date
--
-- so all three existence checks become index-only probes -- seek to the
-- customer, test whether any entry falls in the range, stop at the first hit.
-- No base-table row is touched.  Before, the date predicate lived on a column
-- the index does not carry, so a matching entry had to be resolved to its row
-- before it could be tested.
--
-- The outer query is untouched: same three dimension joins, same grouping,
-- same ordering, same limit.

select
  ca_state,
  cd_gender,
  cd_marital_status,
  cd_dep_count,
  count(*) cnt1,
  min(cd_dep_count) aggone1,
  avg(cd_dep_count) aggtwo1,
  sum(cd_dep_count) aggthree1,
  cd_dep_employed_count,
  count(*) cnt2,
  min(cd_dep_employed_count) aggone2,
  avg(cd_dep_employed_count) aggtwo2,
  sum(cd_dep_employed_count) aggthree2,
  cd_dep_college_count,
  count(*) cnt3,
  min(cd_dep_college_count) aggone3,
  avg(cd_dep_college_count) aggtwo3,
  sum(cd_dep_college_count) aggthree3
 from
  customer c,customer_address ca,customer_demographics
 where
  c.c_current_addr_sk = ca.ca_address_sk and
  cd_demo_sk = c.c_current_cdemo_sk and
  exists (select *
          from store_sales
          where c.c_customer_sk = ss_customer_sk and
                ss_sold_date_sk between 2451180 and 2451453) and
   (exists (select *
            from web_sales
            where c.c_customer_sk = ws_bill_customer_sk and
                  ws_sold_date_sk between 2451180 and 2451453) or
    exists (select *
            from catalog_sales
            where c.c_customer_sk = cs_ship_customer_sk and
                  cs_sold_date_sk between 2451180 and 2451453))
 group by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 order by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 limit 100;
