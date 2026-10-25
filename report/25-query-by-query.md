# The 40 tier-4/5 queries: what each optimization does

Response times measured on the standing configuration (`sql/tpcds-tuned.cnf`)
— 32K pages, 8 GB buffer pool, `innodb_stats_persistent_sample_pages=160` —
running `queries/tuned/`, which substitutes the team's optimized query where
one exists. Sorted by SF=4 response time, slowest first.

**Totals: SF=4 620.9s, SF=1 100.6s.** 40/40 at both, no errors.

| # | query | SF=4 | SF=1 | SF4/SF1 | optimized by |
|---|---|---:|---:|---:|---|
| 1 | q23 | 173.6s | 28.0s | 6.2x | — |
| 2 | q67 | 46.1s | 6.3s | 7.3x | Aysha |
| 3 | q4 | 38.9s | 7.7s | 5.1x | riccio |
| 4 | q74 | 30.8s | 4.5s | 6.8x | — |
| 5 | q57 | 30.4s | 4.4s | 6.9x | — |
| 6 | q51 | 29.6s | 4.1s | 7.2x | riccio |
| 7 | q11 | 28.8s | 6.9s | 4.2x | — |
| 8 | q22 | 26.3s | 4.8s | 5.5x | Claude |
| 9 | q78 | 19.8s | 2.4s | 8.2x | Claude |
| 10 | q14 | 18.7s | 3.2s | 5.8x | Aysha |
| 11 | q68 | 15.1s | 2.7s | 5.6x | — |
| 12 | q72 | 15.1s | 1.0s | 15.1x | Claude |
| 13 | q46 | 14.9s | 2.9s | 5.1x | — |
| 14 | q77 | 13.0s | 0.5s | 26.0x | — |
| 15 | q47 | 12.0s | 1.8s | 6.7x | Aysha |
| 16 | q70 | 11.6s | 2.4s | 4.8x | — |
| 17 | q38 | 11.2s | 1.2s | 9.3x | — |
| 18 | q5 | 11.1s | 0.6s | 18.5x | riccio |
| 19 | q66 | 10.6s | 1.2s | 8.8x | — |
| 20 | q97 | 7.8s | 1.6s | 4.9x | Aysha |
| 21 | q71 | 7.4s | 0.6s | 12.3x | — |
| 22 | q27 | 6.7s | 1.2s | 5.6x | Aysha |
| 23 | q59 | 6.3s | 1.1s | 5.7x | Claude |
| 24 | q2 | 5.9s | 2.9s | 2.0x | Claude |
| 25 | q35 | 5.2s | 1.5s | 3.5x | — |
| 26 | q87 | 4.6s | 1.2s | 3.8x | — |
| 27 | q43 | 3.1s | 0.7s | 4.4x | Aysha |
| 28 | q65 | 2.7s | 0.4s | 6.8x | — |
| 29 | q37 | 2.4s | 0.2s | 12.0x | — |
| 30 | q7 | 2.3s | 0.6s | 3.8x | — |
| 31 | q39 | 1.8s | 0.4s | 4.5x | riccio |
| 32 | q31 | 1.7s | 0.3s | 5.7x | riccio |
| 33 | q82 | 1.5s | 0.2s | 7.5x | — |
| 34 | q8 | 1.4s | 0.4s | 3.5x | — |
| 35 | q21 | 0.7s | 0.2s | 3.5x | Aysha |
| 36 | q88 | 0.5s | 0.1s | 5.0x | Claude |
| 37 | q10 | 0.4s | 0.1s | 4.0x | — |
| 38 | q58 | 0.3s | 0.1s | 3.0x | — |
| 39 | q54 | 0.3s | 0.1s | 3.0x | Aysha |
| 40 | q33 | 0.3s | 0.1s | 3.0x | — |

---

## Each query

### 1. q23 — 173.6s at SF=4, 28.0s at SF=1

**Not optimized.** The most expensive query in the suite by a wide margin. No optimized version exists.

*split materialisation left ON: disabling it measured +54.0s (slower)*

### 2. q67 — 46.1s at SF=4, 6.3s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q67/q67-v2-Optimized.sql`

Pre-computes the date-key range into session variables, then drives the ROLLUP off a single `store_sales` scan.

Verified at SF=4: original 35.3s → 26.5s, **1.3x**, output byte-for-byte identical.

### 3. q4 — 38.9s at SF=4, 7.7s at SF=1

**Optimized by riccio** — `queries/optimized/q4/query4_BEST.sql`

Aggregates the two years once per channel on narrow surrogate keys, rather than building the full year-over-year CTE three times.

Verified at SF=4: original 61.8s → 18.4s, **3.4x**, output byte-for-byte identical.

*split materialisation left ON: disabling it measured +14.6s (slower)*

### 4. q74 — 30.8s at SF=4, 4.5s at SF=1

**Not optimized.** No optimized version exists. Same year-over-year shape as q4 and q11, so the q4 approach may transfer.

### 5. q57 — 30.4s at SF=4, 4.4s at SF=1

**Not optimized.** No optimized version exists. Window-function query, same family as q47.

*split materialisation left ON: disabling it measured +3.2s (slower)*

### 6. q51 — 29.6s at SF=4, 4.1s at SF=1

**Optimized by riccio** — `queries/optimized/q51/query51_BEST.sql`

Unifies the store and web daily series into one scan before the window functions, instead of building two full CTEs.

Verified at SF=4: original 26.9s → 22.3s, **1.2x**, output byte-for-byte identical.

### 7. q11 — 28.8s at SF=4, 6.9s at SF=1

**Not optimized.** No optimized version exists. Year-over-year customer totals, same shape as q4 and q74.

*split materialisation OFF: measured -5.6s at SF=4*

### 8. q22 — 26.3s at SF=4, 4.8s at SF=1

**Optimized by Claude** — `queries/optimized/q22/query22_BEST.sql`

Narrows the `date_dim` range and drives from `inventory` through a covering index rather than joining `date_dim` first.

Verified at SF=4: original 28.5s → 22.9s, **1.2x**, output byte-for-byte identical.

*split materialisation at default: -1.3s is inside this host's noise*

### 9. q78 — 19.8s at SF=4, 2.4s at SF=1

**Optimized by Claude** — `queries/optimized/q78/query78_BEST.sql`

Filters each of the three channels by year before the union, using a covering index on `store_sales`.

Verified at SF=4: original 28.1s → 19.9s, **1.4x**, output byte-for-byte identical.

*split materialisation left ON: disabling it measured +13.9s (slower)*

### 10. q14 — 18.7s at SF=4, 3.2s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q14/Query-14-A/q14_A_Optimized.sql,`

Replaces the repeated `date_dim` joins with `MIN/MAX(d_date_sk)` ranges, turns the eligibility check into `EXISTS`, and computes the average as `SUM/COUNT` rather than materialising a large UNION first.

Verified at SF=4: original 191.7s → 27.9s, **6.9x**, output byte-for-byte identical.

> **Correction applied:** typo i_braknd_id -> i_brand_id (part B would not run at all)

> **Correction applied:** part B emitted 8 columns; TPC-DS requires 12 (the ty_/ly_ key columns are repeated per year) - expanded, and its ORDER BY updated to the new aliases

*split materialisation OFF: measured -17.0s at SF=4*

### 11. q68 — 15.1s at SF=4, 2.7s at SF=1

**Not optimized.** No optimized version exists.

*split materialisation at default: -1.9s is inside this host's noise*

### 12. q72 — 15.1s at SF=4, 1.0s at SF=1

**Optimized by Claude** — `queries/optimized/q72/query72_BEST.sql`

Fixes the join order with `JOIN_PREFIX` so the date dimensions filter before `catalog_sales` and `inventory` are reached.

Verified at SF=4: original 40.1s → 10.1s, **4.0x**, output byte-for-byte identical.

*split materialisation at default: -1.6s is inside this host's noise*

### 13. q46 — 14.9s at SF=4, 2.9s at SF=1

**Not optimized.** No optimized version exists.

*split materialisation at default: -1.6s is inside this host's noise*

### 14. q77 — 13.0s at SF=4, 0.5s at SF=1

**Not optimized.** No optimized version exists.

### 15. q47 — 12.0s at SF=4, 1.8s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q47/q47_Optimized_3secs.sql`

Joins `date_dim` first, replaces the three-way self-join on `rn` with `LAG`/`LEAD` so `v1` is built once instead of three times, and pre-aggregates on integer keys.

Verified at SF=4: original 27.5s → 9.1s, **3.0x**, output byte-for-byte identical.

> **Correction applied:** named the select list: SELECT * had sum_sales and avg_monthly_sales transposed

### 16. q70 — 11.6s at SF=4, 2.4s at SF=1

**Not optimized.** No optimized version exists.

### 17. q38 — 11.2s at SF=4, 1.2s at SF=1

**Not optimized.** Aysha's file for this query contains only `CREATE INDEX` statements, so there is no query to substitute. Its indexes are in `sql/14_contributed_indexes.sql`.

### 18. q5 — 11.1s at SF=4, 0.6s at SF=1

**Optimized by riccio** — `queries/optimized/q5/query5_BEST.sql`

Pushes the date filter into each of the six UNION branches, so every fact table is range-scanned instead of fully scanned then filtered.

Verified at SF=4: original 32.9s → 4.0s, **8.2x**, output byte-for-byte identical.

*split materialisation OFF: measured -8.9s at SF=4*

### 19. q66 — 10.6s at SF=4, 1.2s at SF=1

**Not optimized.** No optimized version exists.

### 20. q97 — 7.8s at SF=4, 1.6s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q97/query97_BEST.sql`

Builds the store and catalog customer-item sets as temporary tables once, instead of as CTEs referenced repeatedly.

Verified at SF=4: original 6.8s → 7.7s, **0.9x**, output byte-for-byte identical.

### 21. q71 — 7.4s at SF=4, 0.6s at SF=1

**Not optimized.** No optimized version exists.

### 22. q27 — 6.7s at SF=4, 1.2s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q27/q27_Optimized.sql`

Forces the join order so the demographics and date filters apply before `store_sales` is read.

Verified at SF=4: original 5.2s → 6.4s, **0.8x**, output byte-for-byte identical.

*split materialisation OFF: measured -3.7s at SF=4*

### 23. q59 — 6.3s at SF=4, 1.1s at SF=1

**Optimized by Claude** — `queries/optimized/q59-sf4/query59_BEST.sql`

Two changes: `split_materialized=off`, because one of its two CTE references was being re-materialised 7,665 times; and bounding the CTE to the 105 weeks the outer query can read, out of 262.

Verified at SF=4: original 162.5s → 4.4s, **36.6x**, output byte-for-byte identical.

*split materialisation OFF: measured -138.1s at SF=4*

### 24. q2 — 5.9s at SF=4, 2.9s at SF=1

**Optimized by Claude** — `queries/optimized/q2/query2_BEST.sql`

Bounds the `wscs` CTE to the needed date range instead of unioning all of store, catalog and web sales across every year.

Verified at SF=4: original 13.1s → 4.9s, **2.7x**, output byte-for-byte identical.

*split materialisation OFF: measured -9.5s at SF=4*

### 25. q35 — 5.2s at SF=4, 1.5s at SF=1

**Not optimized.** Aysha's file for this query contains only `CREATE INDEX` statements, so there is no query to substitute.

### 26. q87 — 4.6s at SF=4, 1.2s at SF=1

**Not optimized.** No optimized version exists.

### 27. q43 — 3.1s at SF=4, 0.7s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q43/q43_Optimized.sql`

Drives from a covering index on `store_sales(ss_sold_date_sk, ss_store_sk, ss_sales_price)` so the day-of-week pivot never touches the base table.

Verified at SF=4: original 2.5s → 1.9s, **1.3x**, output byte-for-byte identical.

> **Correction applied:** removed index DDL: create index idx_date_year_sk_day on date_dim (d_year, d_dat; create index idx_ss_date_store_price on store_sales (ss_sold; analyze table date_dim, store_sales

### 28. q65 — 2.7s at SF=4, 0.4s at SF=1

**Not optimized.** No optimized version exists.

### 29. q37 — 2.4s at SF=4, 0.2s at SF=1

**Not optimized.** No optimized version exists.

### 30. q7 — 2.3s at SF=4, 0.6s at SF=1

**Not optimized.** No optimized version exists.

### 31. q39 — 1.8s at SF=4, 0.4s at SF=1

**Optimized by riccio** — `queries/optimized/q39/query39_BEST.sql`

Keeps each grouped inventory result ahead of its dimension lookups and keeps the two statements independent, so neither shares a materialised temp.

Verified at SF=4: original 3.2s → 1.2s, **2.8x**, output byte-for-byte identical.

### 32. q31 — 1.7s at SF=4, 0.3s at SF=1

**Optimized by riccio** — `queries/optimized/q31/query31_BEST.sql`

Filters each quarter early and pivots the three store/web comparisons into one pass instead of six CTE references.

Verified at SF=4: original 1.2s → 1.0s, **1.2x**, output byte-for-byte identical.

### 33. q82 — 1.5s at SF=4, 0.2s at SF=1

**Not optimized.** No optimized version exists.

### 34. q8 — 1.4s at SF=4, 0.4s at SF=1

**Not optimized.** No optimized version exists.

### 35. q21 — 0.7s at SF=4, 0.2s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q21/query21_optimized.sql`

Stops the derived table being merged, forces the join order so `date_dim` and `item` filter before `inventory` is touched.

Verified at SF=4: original 2.1s → 0.6s, **3.5x**, output byte-for-byte identical.

### 36. q88 — 0.5s at SF=4, 0.1s at SF=1

**Optimized by Claude** — `queries/optimized/q88/query88_BEST.sql`

Collapses the eight separate time-bucket subqueries into one pass of `sum(case when ...)` over a single covering-index scan.

Verified at SF=4: original 0.9s → 0.1s, **6.2x**, output byte-for-byte identical.

### 37. q10 — 0.4s at SF=4, 0.1s at SF=1

**Not optimized.** No optimized version here, but **Nafiz has since contributed `query10_BEST.sql`** — not yet wired in.

### 38. q58 — 0.3s at SF=4, 0.1s at SF=1

**Not optimized.** No optimized version exists.

### 39. q54 — 0.3s at SF=4, 0.1s at SF=1

**Optimized by Aysha** — `queries/optimized/Aysha/q54/q54_Optimized_V2.sql`

Filters each fact table before the union, dedups before joining `customer`, and forces the join order.

Verified at SF=4: original 6.3s → 0.2s — ** EMPTY/ERROR **.

### 40. q33 — 0.3s at SF=4, 0.1s at SF=1

**Not optimized.** No optimized version here, but **Nafiz has since contributed `query33_BEST.sql`** — not yet wired in.


---

## Summary

### Where the SF=4 time goes

| | queries | SF=4 total | share |
|---|---:|---:|---:|
| optimized | 19 | 251.0s | 40% |
| not optimized | 21 | 369.9s | **60%** |

The 21 unoptimized queries are now the larger half of the runtime, and three
of them — q23, q74, q57 — sit in the top five. **q23 alone is 173.6s, 28% of
the whole suite**, and it is the one query where disabling split
materialisation measured *worse* (+54.0s), so the easy lever does not apply.

### What to look at next

1. **q23** — 173.6s, no optimized version, 28% of the total.
2. **q74, q57, q11** — 30.8s, 30.4s, 28.8s, none optimized. q74 and q11 share
   the year-over-year customer-total shape that q4 and q31 already solve, so
   that approach may transfer directly.
3. **q10 and q33** — Nafiz has contributed `query10_BEST.sql` and
   `query33_BEST.sql` since this run; neither is wired into `queries/tuned/`
   yet. Both are already fast, so the gain is small, but the same import would
   pick up anything else he has for the slower queries.
4. **q67** — the slowest query that *is* optimized, and its gain is the
   smallest of the group at 1.3x.

### Two optimizations that make things worse

| query | original | "optimized" |
|---|---:|---:|
| q27 | 5.2s | 6.4s |
| q97 | 6.8s | 7.7s |

Both return identical output, so they are correct — just slower than the
query they replace at SF=4. Worth re-checking with their authors, since both
were tuned at SF=1.

### The SF=4 / SF=1 ratio

Most queries sit between 4x and 9x. The outliers are worth noting because
they indicate where scale hurts disproportionately:

| query | ratio | |
|---|---:|---|
| q77 | 26.0x | not optimized |
| q5 | 18.5x | optimized, but 11.1s at SF=4 |
| q72 | 15.1x | optimized |
| q71 | 12.3x | not optimized |
| q37 | 12.0x | not optimized |
| q2 | **2.0x** | the flattest — scales best of the 40 |

A high ratio means the query degrades faster than the data grows, usually
because its working set stops fitting in the buffer pool. q2's 2.0x is the
one that scales close to linearly.

## Caveats

- Measured on **macOS, where `innodb_flush_method=O_DIRECT` has no effect**
  (`pagesize/test-odirect.sh`): InnoDB's reads are served by the OS file
  cache and a server restart does not clear it. Both runs are equally
  affected, so the SF=4/SF=1 comparison holds, but absolute times would
  differ on Linux. `./reproduce.sh full` runs the matching configuration in a
  container.
- **One run each.** Several queries here have shown 10–30s run-to-run swings
  unrelated to any setting — q5 measured 32.2s and 60.0s in consecutive
  passes earlier. Treat individual figures as indicative; the totals and the
  ordering are more reliable than any single row.
- The verified speedups quoted per query come from
  `queries/verify-tuned.sh`, which ran the original and the optimized version
  back to back and diffed the output. Those are a fairer measure of the
  optimization than the SF=4 column, which is a single pass.
