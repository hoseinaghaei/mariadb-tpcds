# q58 — nothing to recover

**0.6s → 0.6s, 1.00x.** Output byte-identical. The original stays.

| pass | original | v1 |
|---|---:|---:|
| 1 | 0.7s | 0.6s |
| 2 | 0.6s | 0.7s |
| 3 | 0.8s | 0.7s |

## What it does

Each of q58's three CTEs repeats this:

```sql
and d_date in (select d_date
               from date_dim
               where d_week_seq = (select d_week_seq
                                   from date_dim
                                   where d_date = '1998-03-14'))
and <fact>_sold_date_sk = d_date_sk
```

— a join to `date_dim`, an `IN` subquery over `date_dim`, and a scalar
subquery over `date_dim`, three times over, to select seven days.

The week containing 1998-03-14 is `d_date_sk 2450883..2450889` (7 rows,
span 7), and `date_dim` is dense over 2415022..2488070, so the whole
construction collapses to a `BETWEEN` on each fact table's own foreign key and
the dimension leaves the query.

The filter is on whole weeks, which is what makes it safe in the same way it
was for q59: a week is included or excluded entire, so no group loses days at
a boundary and no sum changes.

The `item` joins stay. `i_item_id` is not unique — several `i_item_sk` share
one, and the GROUP BY deliberately merges them — so the join does real work.

## Why it changes nothing

This was written for completeness, not because anything suggested headroom.
q58 runs in 0.6s warm and 0.1s at SF=1; three `date_dim` lookups against a
73,049-row dimension that is permanently resident cost essentially nothing,
and the seven-day window means the fact-table access was already tiny either
way.

Kept as a verified-equivalent alternative rather than an improvement. The
original is what `queries/tuned/` uses.
