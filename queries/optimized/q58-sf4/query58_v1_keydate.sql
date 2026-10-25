-- q58 v1 -- resolve the week once, at authoring time, instead of three times
-- per execution.
--
-- Each of the three CTEs repeats this:
--
--   and d_date in (select d_date
--                  from date_dim
--                  where d_week_seq = (select d_week_seq
--                                      from date_dim
--                                      where d_date = '1998-03-14'))
--   and <fact>_sold_date_sk = d_date_sk
--
-- a join to date_dim, an IN subquery over date_dim, and a scalar subquery
-- over date_dim -- three times over -- to select seven days.
--
-- The week containing 1998-03-14 is d_date_sk 2450883..2450889 (7 rows, span
-- 7), and date_dim is dense over 2415022..2488070, so the whole construction
-- collapses to a BETWEEN on each fact table's own foreign key.  Nothing reads
-- a date_dim column afterwards, so the dimension leaves the query entirely.
--
-- The filter is on whole weeks, which is what makes the substitution safe in
-- the same way it was for q59: a week is included or excluded entire, so no
-- group loses days at a boundary and no sum changes.
--
-- The item joins stay.  i_item_id is not unique -- several i_item_sk share
-- one i_item_id, and the GROUP BY deliberately merges them -- so the join is
-- doing real work, not just filtering.
--
-- Expect very little from this one: q58 runs in 0.3s at SF=4 and 0.1s at
-- SF=1, so there is almost nothing to recover.  It is rewritten for
-- consistency with the other nine, and because the change is the same proven
-- substitution rather than a new idea.

with ss_items as
 (select i_item_id item_id
        ,sum(ss_ext_sales_price) ss_item_rev
 from store_sales
     ,item
 where ss_item_sk = i_item_sk
   and ss_sold_date_sk between 2450883 and 2450889
 group by i_item_id),
 cs_items as
 (select i_item_id item_id
        ,sum(cs_ext_sales_price) cs_item_rev
  from catalog_sales
      ,item
 where cs_item_sk = i_item_sk
  and  cs_sold_date_sk between 2450883 and 2450889
 group by i_item_id),
 ws_items as
 (select i_item_id item_id
        ,sum(ws_ext_sales_price) ws_item_rev
  from web_sales
      ,item
 where ws_item_sk = i_item_sk
  and  ws_sold_date_sk between 2450883 and 2450889
 group by i_item_id)
  select  ss_items.item_id
       ,ss_item_rev
       ,ss_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3) * 100 ss_dev
       ,cs_item_rev
       ,cs_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3) * 100 cs_dev
       ,ws_item_rev
       ,ws_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3) * 100 ws_dev
       ,(ss_item_rev+cs_item_rev+ws_item_rev)/3 average
 from ss_items,cs_items,ws_items
 where ss_items.item_id=cs_items.item_id
   and ss_items.item_id=ws_items.item_id
   and ss_item_rev between 0.9 * cs_item_rev and 1.1 * cs_item_rev
   and ss_item_rev between 0.9 * ws_item_rev and 1.1 * ws_item_rev
   and cs_item_rev between 0.9 * ss_item_rev and 1.1 * ss_item_rev
   and cs_item_rev between 0.9 * ws_item_rev and 1.1 * ws_item_rev
   and ws_item_rev between 0.9 * ss_item_rev and 1.1 * ss_item_rev
   and ws_item_rev between 0.9 * cs_item_rev and 1.1 * cs_item_rev
 order by item_id
         ,ss_item_rev
 limit 100;
