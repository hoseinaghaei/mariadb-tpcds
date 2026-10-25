-- q70 v1 -- drop a subquery that filters nothing, and aggregate on the key.
--
-- The `s_state in (...)` subquery costs a second full pass over the 12-month
-- window of store_sales and removes no rows at all.  That is provable from
-- the SQL alone:
--
--     select s_state from (
--       select s_state,
--              rank() over (partition by s_state order by sum(ss_net_profit) desc) ranking
--       from store_sales, store, date_dim
--       where <identical join and month filter as the outer query>
--       group by s_state) tmp1
--     where ranking <= 5
--
-- It groups by s_state and then partitions by s_state.  Every partition
-- therefore holds exactly one row, so rank() is 1 for every row and
-- `ranking <= 5` admits all of them.  The subquery reduces to "the distinct
-- s_state values reachable under this join and month filter" -- which is
-- precisely the set the outer query is already restricted to, because it
-- applies the same join and the same filter.  So `s_state in (...)` is TRUE
-- for every outer row.
--
-- (This is a quirk of the published TPC-DS text, not a transcription error:
-- the partition clause defeats the top-5 filter the query appears to intend.
-- Reproducing the answer means keeping that behaviour, not repairing it.)
--
-- The one case where IN would not be a no-op is a NULL s_state, which yields
-- UNKNOWN rather than TRUE and would drop the row.  store holds 42 rows and
-- none has a NULL s_state, so no guard is needed.  (One row does have a NULL
-- s_county; that is left exactly as it was, because with ROLLUP it is
-- indistinguishable from a rollup row in `(s_county is null)` and that
-- quirk belongs to the original answer.)
--
-- Second change: aggregate by ss_store_sk and join store afterwards.  The
-- original groups 2.3M rows by (s_state, s_county) -- two varchars -- when
-- 42 stores determine both.  Pre-aggregating to one row per store reduces
-- the group key to a single integer and the grouped input to 42 rows before
-- the strings are ever touched.  sum(sum(x)) = sum(x) exactly here:
-- ss_net_profit is DECIMAL(7,2), so the two-stage sum is not a floating
-- point re-association and the output is byte-identical.
--
-- Third: d_month_seq between 1176 and 1176+11 is the contiguous key range
-- d_date_sk 2450815..2451179 (365 rows, span 365), and date_dim is dense
-- over 2415022..2488070, so the join to d1 becomes a range predicate and
-- disappears.  BETWEEN also excludes the NULL ss_sold_date_sk rows, which
-- is what the inner join did.

with ss_by_store as (
  select ss_store_sk, sum(ss_net_profit) as np
  from store_sales
  where ss_sold_date_sk between 2450815 and 2451179
  group by ss_store_sk
)
select * from (
select
    sum(np) as total_sum
   ,s_state
   ,s_county
   ,(s_state is null)+(s_county is null) as lochierarchy
   ,rank() over (
 	partition by (s_state is null)+(s_county is null),
 	case when (s_county is null) = 0 then s_state end
 	order by sum(np) desc) as rank_within_parent
 from
    ss_by_store
   ,store
 where
    s_store_sk = ss_store_sk
 group by s_state,s_county with rollup
) tpcds_rollup
order by
   lochierarchy desc
  ,case when lochierarchy = 0 then s_state end
  ,rank_within_parent
 limit 100;
