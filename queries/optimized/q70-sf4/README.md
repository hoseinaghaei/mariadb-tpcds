# q70 — a subquery that filters nothing

**11.6s → 3.6s at SF=4, 3.22x, output byte-identical.**

| pass | original | v1 |
|---|---:|---:|
| 1 | 22.4s | 5.2s |
| 2 | 11.7s | 3.6s |
| 3 | 11.6s | 3.6s |

(Pass 1 is a cold buffer pool on both sides.)

## The finding

q70 restricts its result with

```sql
and s_state in
    ( select s_state
      from (select s_state as s_state,
                   rank() over (partition by s_state
                                order by sum(ss_net_profit) desc) as ranking
            from store_sales, store, date_dim
            where d_month_seq between 1176 and 1176+11
              and d_date_sk = ss_sold_date_sk
              and s_store_sk = ss_store_sk
            group by s_state
           ) tmp1
      where ranking <= 5 )
```

which reads as "keep only the top five states by profit". It does not do
that, and it never did.

The inner query **groups by `s_state` and then partitions by `s_state`**.
Grouping has already reduced the input to one row per state, so every
partition contains exactly one row, and `rank()` returns 1 for all of them.
`ranking <= 5` therefore admits every row. The subquery degenerates to "the
distinct `s_state` values reachable under this join and this month filter" —
which is exactly the set the outer query is already confined to, since it
applies the same join and the same filter.

So `s_state in (...)` is TRUE for every outer row, and the cost of
establishing that is a second full pass over a 12-month window of
`store_sales`.

This is a property of the published TPC-DS query text, not a transcription
error on our side. Reproducing the benchmark's answer means preserving the
behaviour, not repairing the apparent intent — and deleting the subquery
preserves it exactly.

The one case where `IN` would not be a no-op is a NULL `s_state`: `NULL IN
(...)` is UNKNOWN, not TRUE, so such a row would be dropped. `store` holds 42
rows and none has a NULL `s_state`, so no guard is needed. One row does have
a NULL `s_county`; that is left alone, because under `WITH ROLLUP` it is
indistinguishable from a rollup row in `(s_county is null)` and that quirk is
part of the original answer.

## The second change

The outer query grouped 2.3M rows by `(s_state, s_county)` — two varchars —
when 42 stores determine both. The rewrite aggregates by `ss_store_sk` first
and joins `store` afterwards, so the grouped input is 42 rows before any
string is touched.

`sum(sum(x)) = sum(x)` holds exactly here: `ss_net_profit` is `DECIMAL(7,2)`,
so staging the sum is not a floating-point re-association and the output does
not shift in the last digit.

Unlike q66, where the same key-narrowing idea produced a regression, this one
is bundled with a change that removes an entire table scan, and the measured
result is dominated by that.

## The third change

`d_month_seq between 1176 and 1176+11` is the contiguous key range
`d_date_sk 2450815..2451179` (365 rows, span 365 — it is calendar year 1998).
`date_dim` is dense over 2415022..2488070, so the join becomes a `BETWEEN` on
`ss_sold_date_sk` and the dimension leaves the query. `BETWEEN` also excludes
the NULL foreign keys the inner join excluded.
