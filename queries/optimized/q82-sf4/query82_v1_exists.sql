-- q82 v1 -- two joins that only test existence become two EXISTS.
--
-- The original joins item to inventory, date_dim and store_sales and then
-- does `group by i_item_id, i_item_desc, i_current_price` with no aggregate
-- in the select list.  A GROUP BY with nothing aggregated is a DISTINCT: the
-- join multiplicity is built up and then thrown away.  An item that matches
-- 400 inventory rows and 9,000 store_sales rows contributes 3.6M intermediate
-- rows and exactly one output row.
--
-- So both joins are existence tests, and writing them as EXISTS is exact --
-- not an approximation.  EXISTS stops at the first match instead of
-- enumerating all of them.
--
-- This is still correct across item revisions.  i_item_id is NOT unique --
-- several i_item_sk share one i_item_id -- so the grouping really does merge
-- rows from different item keys.  EXISTS is evaluated per i_item_sk, before
-- the grouping, so a triple survives exactly when at least one of its item
-- keys qualifies, which is what the join produced.
--
-- The date filter is the contiguous key range d_date_sk 2451559..2451619
-- (61 rows, span 61; date_dim is dense over 2415022..2488070), so date_dim
-- goes too -- inv_date_sk can be tested directly.
--
-- Both subqueries are then index-only:
--
--   inventory    idx_inv_item_date_sk (inv_item_sk, inv_date_sk,
--                                      inv_quantity_on_hand)
--                carries all three columns the subquery names
--   store_sales  idx_ss_item_sk (ss_item_sk)
--
-- GROUP BY is kept rather than replaced by DISTINCT so the shape of the
-- statement, and its output column names, stay as they were.

select  i_item_id
       ,i_item_desc
       ,i_current_price
 from item
 where i_current_price between 33 and 33+30
 and i_manufact_id in (306,845,203,671)
 and exists (select 1
             from inventory
             where inv_item_sk = i_item_sk
               and inv_date_sk between 2451559 and 2451619
               and inv_quantity_on_hand between 100 and 500)
 and exists (select 1
             from store_sales
             where ss_item_sk = i_item_sk)
 group by i_item_id,i_item_desc,i_current_price
 order by i_item_id
 limit 100;
