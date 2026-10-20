# query 78 — 27.2s → 8.5s (3.2x)

Original: `queries/mariadb/query78.sql`.
Output is **byte-identical** to it (100 rows).

## What the query must do

TPC-DS Appendix B.78:

> Report the top customer / item combinations having the highest ratio of store
> channel sales to all other channel sales (minimum 2 to 1 ratio), for
> combinations with at least one store sale and one other channel sale.

Three CTEs — `ws`, `cs`, `ss` — each aggregate one sales channel by
`(year, item, customer)`, excluding items that were returned (a `LEFT JOIN` to
the returns table with `... is null`, i.e. an anti-join). The outer query joins
store sales to the other two and computes the ratio.

## Results

| File | Time | Change |
|---|---:|---|
| `query78_v0_original.sql` | **27.2s** | — |
| `query78_v1_yearfilter.sql` *(= BEST)* | 11.4s → **8.5s** | `d_year = 2001` pushed into all three CTEs |

The second number is with the covering index below.

## The rewrite

All three CTEs aggregate **every year** in the data (1998–2003), but the outer
query keeps only 2001:

```sql
where (coalesce(ws_qty,0)>0 or coalesce(cs_qty,0)>0) and ss_sold_year=2001
```

And `ws`/`cs` join on `ws_sold_year = ss_sold_year`, so only their 2001 rows
could ever match. Adding `and d_year = 2001` to each CTE is therefore safe —
rows of other years are discarded either by the outer `WHERE` or by the join.

**27.2s → 11.4s.**

## Where the remaining time goes

Timing each CTE in isolation:

| CTE | Time | Groups |
|---|---:|---:|
| **`ss`** (store_sales) | **7.7s** | 489,557 |
| `cs` (catalog_sales) | 4.4s | 256,601 |
| `ws` (web_sales) | 0.8s | 130,540 |

`ss` dominates, so that is where an index was tried.

## One index worth keeping, one not

```sql
CREATE INDEX idx_ss_q78 ON store_sales
  (ss_sold_date_sk, ss_item_sk, ss_customer_sk, ss_ticket_number,
   ss_quantity, ss_wholesale_cost, ss_sales_price);
```

Seven columns — everything the `ss` CTE reads — so the aggregation never
touches the base table. **153 MB** for **11.4s → 8.5s (~25%)**.

The equivalent index on `catalog_sales` was built and **dropped**:

| Configuration | Time |
|---|---:|
| neither index | 11.4s |
| **`ss` index only** | **8.5s** |
| `cs` index only | 12.4s |
| both | 8.9s |

The `cs` index contributes nothing — on its own it is no better than neither,
and adding it to the `ss` index makes things marginally worse. 80 MB reclaimed.

Whether 153 MB is worth 25% is a judgement call; the index is in
`sql/11_optimizer_indexes.sql` and can be dropped without touching the query,
which keeps the 27.2s → 11.4s on its own.

## A measurement note

The three-pass control **failed** here on the first attempt: visible 8.4s /
8.2s, ignored 10.6s / 9.9s, then visible again **23.7s**. Since A and C must
agree, that reading was discarded and the comparison re-run interleaved:

```
VISIBLE  9.3s   IGNORED 11.3s
VISIBLE  8.5s   IGNORED 11.3s
VISIBLE  9.0s   IGNORED 11.5s
```

Consistent across all three pairs. The 23.7s was an environmental stall — the
same artefact that produced a false "regression" for this very query earlier in
the project ([`report/17`](../../../report/17-unused-indexes-are-not-safe-to-drop.md)).
Interleaving is more robust than A/B/A when the machine is noisy.

Full writeup: [`report/18-query-optimization.md`](../../../report/18-query-optimization.md)
