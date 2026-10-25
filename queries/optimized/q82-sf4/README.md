# q82 — a GROUP BY with nothing to aggregate

**0.8s → 0.1s at SF=4, 8.0x, output byte-identical.**

The largest ratio of anything in this batch, on one of the smallest queries.

## The finding

q82 joins `item` to `inventory`, `date_dim` and `store_sales`, then does

```sql
group by i_item_id, i_item_desc, i_current_price
```

with **no aggregate in the select list**. A GROUP BY that aggregates nothing
is a DISTINCT: the join multiplicity is built up at full cost and then thrown
away. An item matching 400 inventory rows and 9,000 `store_sales` rows
contributes 3.6M intermediate rows and exactly one output row.

Both joins are therefore existence tests, and writing them as `EXISTS` is
exact rather than approximate. `EXISTS` stops at the first match instead of
enumerating every one.

This stays correct across item revisions. `i_item_id` is **not** unique —
several `i_item_sk` share one `i_item_id`, and the GROUP BY deliberately
merges them. `EXISTS` is evaluated per `i_item_sk`, before the grouping, so a
triple survives exactly when at least one of its item keys qualifies, which
is what the join produced.

## Why it is so much faster

Once the joins are subqueries, both are index-only:

| subquery | index | covers |
|---|---|---|
| `inventory` | `idx_inv_item_date_sk (inv_item_sk, inv_date_sk, inv_quantity_on_hand)` | all three columns named |
| `store_sales` | `idx_ss_item_sk (ss_item_sk)` | the only column named |

Neither touches a base-table row. The `date_dim` join goes too: the 61-day
window is the contiguous key range `d_date_sk 2451559..2451619` (61 rows,
span 61), so `inv_date_sk` can be tested directly.

GROUP BY is kept rather than replaced with DISTINCT so the statement's shape
and output column names are unchanged.

## Why this one worked when the others did not

Five of the ten rewrites in this batch regressed or did nothing. The ones
that paid — q23 (3.6x), q70 (3.22x), q82 (8.0x) — each **removed work**: a
CTE rebuilt 55,882 times, a second full table pass, a join multiplicity of
3.6M rows discarded at the end.

The ones that did not pay — q66, q38, q77, q58 — only substituted a date
range for a `date_dim` join. That changes which access path the optimizer
picks without reducing the work to be done, and on three of the four it
picked worse.
