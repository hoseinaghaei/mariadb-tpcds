# query 22 — 23.0s → 4.3s (5.3x)

Original: `queries/mariadb/query22.sql`.
Every variant produces **byte-identical output** to it (100 rows).

## What the query must do

TPC-DS Appendix B.22:

> For each product name, brand, class, category, calculate the average quantity
> on hand. Rollup data by product name, brand, class and category.

`GROUP BY ... WITH ROLLUP` over four columns produces five levels, so ~36,000
rows come out of 8,957 detail groups.

Note `i_product_name` has **17,957 distinct values across 18,000 item rows** —
it is nearly unique, so the `L3` subtotal level (name+brand+class) is identical
to the `L4` detail level, 8,957 rows each. That redundancy is inherent to the
specified grouping order and **cannot be removed**: `ROLLUP` collapses
right-to-left, so reordering the columns would change which subtotals are
produced, and therefore the answer.

The reference implementation `spetrunia/tpcds-run-tool` cannot run this query
at all — it stubs it out with `MARIADB-EXPECTED-ERROR: rollup+order by`.

## Results

| File | Time | Change |
|---|---:|---|
| `query22_v0_original.sql` | **23.0s** | — |
| `query22_v3_hintonly.sql` | 29.6s | hint alone, no index — **worse** |
| `query22_v2_rangeonly.sql` | 11.9s | date-range filter alone, no index |
| `query22_v1_user.sql` | **5.4s → 4.9s** | hint + range + covering index |
| `query22_v5_semijoin.sql` | 7.3s | range expressed as `IN (select ...)` |
| `query22_v7_invfirst.sql` | 12.3s | driving from `inventory` instead of `item` |
| `query22_v4_nodatedim.sql` | 4.2s | `date_dim` join removed, hinted |
| **`query22_BEST.sql`** = `query22_v6_nohint.sql` | **4.3s** | same, **no hint needed** |

## The ablation matrix

Each ingredient measured alone and together, with the covering index both
hidden and visible:

| Variant | index IGNORED | index VISIBLE |
|---|---:|---:|
| original | **23.0s** | 11.5s |
| range filter only | 11.9s | 16.1s |
| hint only | 29.6s | 19.2s |
| hint + range | 18.0s | **5.4s** |

**None of the three ingredients is independently good.** The hint alone makes
things *worse* (23.0 → 29.6s). Range-plus-index is worse than index alone
(16.1s vs 11.5s). Only all three together win. Interactions like this are why
ingredients have to be measured in combination, not assumed to add up.

## The indexes

```sql
CREATE INDEX idx_inv_item_date_sk
    ON inventory (inv_item_sk, inv_date_sk, inv_quantity_on_hand);
```

Covers everything the aggregation reads from `inventory` — the plan shows
`ref ... Using index`, no row lookups.

```sql
CREATE INDEX idx_date_dim_d_month_seq ON date_dim (d_date_sk, d_month_seq);
```

Serves the min/max subqueries. Note this is the **composite** form. A plain
`date_dim(d_month_seq)` was tested separately and makes **query 59 ten times
slower** — see `sql/11`.

## The last step: deleting the join

With `inv_date_sk` bounded by the date range, the `date_dim` join does no
filtering at all. Verified:

```
dates with d_date_sk between 2450815 and 2451179 : 365
of which d_month_seq between 1176 and 1187        : 365
```

All of them. Because `d_month_seq` is contiguous in time, the `[min, max]`
`d_date_sk` window covers exactly those months and nothing else. And
referential integrity guarantees every `inv_date_sk` exists in `date_dim`
(verified: 107/107 relationships, zero orphans), so the inner join cannot drop
rows either — `d_date_sk` is the primary key, so it cannot duplicate them.

Removing it eliminates **2,385,000 `eq_ref` probes**: 4.9s → 4.3s.

**This rewrite depends on two data properties**, both guaranteed by the TPC-DS
schema but worth stating: `d_month_seq` is contiguous in `d_date_sk` order, and
`inventory.inv_date_sk` is a enforced-or-clean foreign key into `date_dim`.

Once `date_dim` is gone the hint becomes unnecessary — the optimizer finds the
same plan unaided, so `BEST` carries no hint.

Full writeup: [`report/18-query-optimization.md`](../../../report/18-query-optimization.md)
