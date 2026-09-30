# query 59 — 7.3s → 1.2s (6.1x)

Original: `queries/mariadb/query59.sql`.
Every variant produces **byte-identical output** to it (100 rows).

| File | Time | Change |
|---|---:|---|
| *(original, no new index)* | 7.3s | — |
| *(original + covering index)* | 3.0s | index only, SQL unchanged |
| `query59_v1_weekfilter.sql` | 2.1s | CTE restricted by `d_week_seq IN (...)` |
| `query59_v3_widemonth.sql` | 1.9s | CTE restricted by `d_month_seq between 1191 and 1216` |
| `query59_v4_hinted.sql` | 1.6s | v3 + `JOIN_PREFIX(date_dim)` |
| **`query59_BEST.sql`** = `query59_v2_daterange.sql` | **1.2s** | CTE restricted by a contiguous `ss_sold_date_sk` range |

## The index

```sql
CREATE INDEX idx_ss_sold_date_sk_store_sales_price
    ON store_sales (ss_sold_date_sk, ss_store_sk, ss_sales_price);
```

Covers every column the CTE touches, so its scan runs `Using index`.

## The rewrite

The CTE is materialised **twice** and each copy scanned all 2,879,152
`store_sales` rows, when only 1,101,383 are needed — the outer query uses 105
of `date_dim`'s 10,436 week values. Restricting the CTE fixes both copies.

**Safe because it selects whole weeks.** Filtering on the sales' own
`d_month_seq` would break a week straddling a month boundary.

## Rejected

`CREATE INDEX idx_dd_month_seq ON date_dim(d_month_seq)` makes this query
**10x slower** — 1.2s → 12.7s. Three-pass confirmed. See `sql/11`.

Full writeup: [`report/18-query-optimization.md`](../../../report/18-query-optimization.md)
