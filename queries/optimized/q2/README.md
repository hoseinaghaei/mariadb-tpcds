# query 2 — 84s → 25.9s (3.2x)

Original: `queries/mariadb/query2.sql`.
Every variant produces **byte-identical output** to it (2,520 rows, headers
included).

## What the query must do

TPC-DS Appendix B.2:

> Report the ratios of weekly web and catalog sales increases from one year to
> the next year for each week. That is, compute the increase of Monday,
> Tuesday, ... Sunday sales from one year to the following.

It unions `web_sales` and `catalog_sales` into a single stream of
`(date, price)`, aggregates it into seven per-weekday totals per week, then
self-joins the result 53 weeks apart to form year-on-year ratios.

**It returns 2,520 rows for only 52 distinct weeks** — 49 rows per week. The
`wswscs ⋈ date_dim ON d_week_seq` join matches all 7 days of a week, on both
sides of the self-join, so every pair is reproduced 7×7 times. That is the
specified query's behaviour and is preserved exactly.

## Results

| File | Time | Change |
|---|---:|---|
| `query2_v0_original.sql` | **84s** | — |
| `query2_v4_yearwide.sql` | 64.3s | window widened to whole years 1999–2002 |
| `query2_v5_single.sql` | ~29s | restructured so the union materialises once |
| `query2_v3_boundscte.sql` | 28.6s | window computed once in a `bounds` CTE |
| `query2_v1_daterange.sql` *(= BEST)* | 32.1s → **25.9s** | window pushed into both union arms |

The second number for v1 is with the covering indexes below.

## Where the time goes

`EXPLAIN` showed the `wscs` union scanned **twice**, each pass reading all of
`web_sales` (720,378) and `catalog_sales` (1,441,837) — about **5.1M row scans**
— when the query only ever uses two years out of the six in the data.

Pushing a date-range filter into both arms of the union cuts each pass to
292,707 + 575,192 rows:

```sql
from web_sales
where ws_sold_date_sk between
      (select min(d_date_sk) from date_dim
         where d_week_seq in (select d_week_seq from date_dim
                              where d_year in (2000, 2000+1)))
  and (select max(d_date_sk) from date_dim ... )
```

**Safe because it selects whole weeks**, so every surviving week's day-totals
are complete. Weeks outside the window are discarded by the outer `d_year`
filters anyway.

## The covering indexes — worth ~20%

```sql
CREATE INDEX idx_ws_sold_date_ext_price ON web_sales     (ws_sold_date_sk, ws_ext_sales_price);
CREATE INDEX idx_cs_sold_date_ext_price ON catalog_sales (cs_sold_date_sk, cs_ext_sales_price);
```

Without them the filtered scan is still `ALL ... Using where` — the existing
single-column `idx_ws_sold_date_sk` cannot be used because `ext_sales_price`
would need a row lookup. With them the plan becomes
`range ... Using index`.

Three-pass:

| | query 2 |
|---|---:|
| indexes visible | 25.8s |
| **IGNORED** | **32.1s** |
| visible again | 26.0s |

## Things that did not work

**Computing the window once in a `bounds` CTE** (28.6s). `EXPLAIN` showed the
min/max subqueries being materialised **eight times** — 2 subqueries × 2 union
arms × 2 CTE copies — which looked like the obvious next target. Hoisting them
into a single CTE changed nothing measurable, so that overhead was not on the
critical path after all.

**Widening the window to whole years 1999–2002** (64.3s). Simpler SQL, no
nested `IN`, but it admits twice as much data and loses most of the benefit.

**Restructuring so the union materialises once** (~29s). Carrying `d_year`
through a combined `yz` CTE means `wswscs` is referenced once instead of twice.
It measured 25.8s on its first run and 60.3s and 32.2s on later ones — too
unstable to prefer over the simpler v1, and no better on average.

## A measurement note

An early v5 reading of 25.8s looked like a win until repeats gave 60.3s and
32.2s. Everything here is quoted from at least two runs. Absolute timings in
this project vary by roughly ±50% with buffer-pool state.

Full writeup: [`report/18-query-optimization.md`](../../../report/18-query-optimization.md)
