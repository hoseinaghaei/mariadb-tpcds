# Q57 optimization — Docker SF4, seed 10

Overall BEST is `query57_v4_preagg_cover.sql`, copied exactly to `query57_BEST.sql`. Five final measured rounds give **2.550269s** versus original **12.313559s**: **4.83x** faster including one added index.

On the same agreed **167-index profile**, `query57_v2_safe_window.sql` measures **3.941841s**, or **3.12x** faster than original. With the added catalog covering index, unchanged original measures **10.499390s**, so the combined SQL rewrite improves that same-index comparison by **4.12x**. These comparisons are reported separately.

## Final retained versions, longest to shortest

| Version | Criteria | Visible profile | Median seconds | Min–max seconds | Reference speedup |
|---|---|---|---:|---:|---:|
| `v0_original` | Original | reference167 | 12.313559 | 12.001572–13.307421 | 1.00x |
| `v1_catalog_cover` | Catalog revenue covering | reference167 + catalog cover | 10.499390 | 10.389705–10.934507 | 1.17x |
| `v2_safe_window` | NULL-safe neighbor windows | reference167 | 3.941841 | 3.878683–4.106818 | 3.12x |
| `v3_window_cover` | Windows + covering | reference167 + catalog cover | 3.398700 | 3.303652–3.582723 | 3.62x |
| `v4_preagg_cover` | Preaggregate + windows + cover | reference167 + catalog cover | 2.550269 | 2.401726–2.675981 | 4.83x |

Each final version has five measured rounds after a discarded warm-up. Every retained candidate's timing range is faster than the reference original's range. Version numbers follow final median, not a promise that every version adds to every previous one. SQL-only, index-only and combined versions have explicit physical profiles.

## Original query and plan bottleneck

Q57 builds monthly catalog-sales totals by category, brand and call-center name for December 1999 through January 2001. It computes the average monthly total separately for each year and ranks observed months in each category/brand/center group. Three references to that result find each month's previous and next ranked month. The output keeps anomalous 2000 months whose absolute deviation from their positive yearly average exceeds 10 percent, ordered by deviation and previous sales.

The original materializes and computes the expensive monthly aggregate three times. Actual initial analysis was about 12.5 seconds, with each aggregate copy around 3.8–3.9 seconds. The baseline after warm-up was roughly 12–14 seconds. Replacing the repeated aggregates and self-joins is the main structural improvement; timings above come from ordinary runs, not from ANALYZE diagnostics.

## Index tests first

| Tested index | Ordered columns | Size MiB | Build + ANALYZE seconds |
|---|---|---:|---:|
| `idx_nf_q57_catalog_cover` | cs_sold_date_sk,cs_item_sk,cs_call_center_sk,cs_sales_price | 243.375 | 15.173 |
| `idx_nf_q57_item_cover` | i_item_sk,i_category,i_brand | 7.031 | 0.242 |

The catalog covering index supplies the date, item key, call-center key and price needed by Q57, reducing base-row fetches. Unchanged original SQL is measured separately with it. The item-cover index adds little beyond the catalog cover and is not required by any final variant. It was rejected to avoid extra storage and maintenance without a useful reliable gain.

The selected catalog index costs **243.375 MiB** and is supplied in `indexes-BEST.sql`. It is optional relative to the team's agreed profile. Index creation, visibility changes, statistics refresh and diagnostics are outside query timing. A benefit for Q57 does not establish a benefit to the full suite.

## How each retained approach works

### Original reference

`query57_v0_original.sql` is an exact copy of `queries/mariadb/query57.sql`. The source and previous SF1 query folder remain unchanged.

### Catalog covering only

SQL intentionally equals original. The recorded profile enables only the new catalog covering index in addition to the original 167. This isolates index benefit from SQL rewriting.

### NULL-safe windows, reference indexes

The monthly aggregate is computed once. LAG and LEAD provide the previous and next observed monthly sales instead of joining three copies by rank. The monthly grouping makes each year/month pair unique inside a category/brand/center partition, so adjacent rows represent the original consecutive ranks even when calendar months are missing.

`LAG(1)` and `LEAD(1)` separately record whether the neighboring row exists. They are deliberately not replaced by `psum IS NOT NULL` / `nsum IS NOT NULL`: a real neighboring month can have an all-NULL sales sum, and the original inner rank join still includes that neighbor.

Monthly rows with NULL category, brand or call-center name are excluded before the windows. Original equality self-joins cannot match NULL partition keys; ordinary window partitioning would otherwise retain those groups. Removing them does not affect any non-NULL partition's average or neighbors.

The December 1999 and January 2001 rows remain until after window calculation, preserving boundary neighbors. `d_year=2000` is applied afterward, just as the original final filter. AVG still partitions by year and ignores NULL monthly sums. The original CASE/division anomaly test, output columns, ORDER BY and LIMIT remain.

### Windows with catalog covering

Exactly the same NULL-safe window SQL, with the optional catalog covering index enabled. This measures the combination separately from both index-only and SQL-only alternatives.

### Preaggregate + windows + catalog cover — BEST

Catalog sales are first grouped by item surrogate key, call-center surrogate key, year and month using the original date join and period predicate. Item and call-center attributes are joined after that fact aggregation, reducing repeated dimension lookups. Totals are then **regrouped by the original category, brand, call-center name, year and month** before AVG/LAG/LEAD are calculated.

The regrouping preserves multiple item keys sharing a category/brand and multiple call-center keys sharing a name. SUM of the partial sums retains duplicate sale amounts, decimal values and all-NULL groups. Original dimension joins remain, so missing items, dates or call centers are still excluded. This combines key-level fact preaggregation with the safe windows and one catalog cover. It does not retain the additional item index, date-key bounds or a join-order hint.

## Other tested methods and rejection reasons

- Exact December-1999 through January-2001 bounds (`2451514` through `2451941`, 428 days) were tested with the original date predicates and joins retained. A range alone made the reference window plan slower in screening. Bounds plus a date-first hint tied the simpler window query; they were not kept.
- Key preaggregation without a new index was roughly tied with the simpler window rewrite in repeated reference tests. It was not inflated into another numbered SQL-only version. Its useful gain appeared when combined with the catalog cover.
- The additional item covering index did not add a convincing gain over the catalog cover alone.
- Explicitly aligning the AVG window's ordering and full-partition frame did not produce a reliable useful extra gain. The simpler original AVG partition is retained.
- Adding bounds or an aligned frame to preaggregation produced overlapping timings with the simpler preaggregation and was not selected.
- The historical SF1 window query matched the real LIMIT-100 sample but failed the NULL-neighbor/NULL-key fixture. It is not copied into the new final variants.

Raw exploratory medians and counts are in `screening-results.csv`; unrounded successful runs and physical-profile labels are in `benchmark-runs.csv` and `evidence/runs.json`. Some screening approaches have a single exploratory run; only the final table uses the five-round confirmation protocol. Tied or slower approaches are not presented as extra improvements. Further optimization may exist beyond these tested methods.

## Correctness validation

Every final execution returned the same 100 ordered rows as original, with all seven output columns byte-identical. Output SHA-256: `e1e8114f1238f2cc4b201f1c3251c1f0515fe7da1f94d8cf62c47586ff04a894`.

Original, the SQL-only window and overall BEST were also executed without LIMIT. Their complete **53434 rows** matched exactly after ordering by all seven projected columns for that separate comparison. This canonical ordering checks values and multiplicity without assuming that the original two-key ORDER BY breaks all ties. The main saved SQL retains the original ORDER BY and its actual ordered 100-row output.

A nonempty temporary-table fixture checks missing calendar months (neighbors are observed ranks, not forced calendar adjacency), December/January boundaries, an existing month with NULL total, all-NULL or zero averages, NULL category/brand/center keys, duplicate sale rows, multiple item keys sharing attributes, multiple call-center keys sharing a name, and missing item/date/center joins. It returns three anomaly rows, including rows with a NULL previous or next amount; every safe retained approach matches them exactly.

The historical rewrite filters on neighboring amounts being non-NULL and lacks the explicit original NULL-key exclusion, so its fixture output differs. This is a semantic assumption exposed by the fixture, not a statement that the current SF4 data is corrupt. Only the historical LIMIT sample was checked here; its complete result is not claimed to be validated. New versions check row existence independently and preserve the original equality behavior.

The fixture SQL/output and per-candidate checks, full real outputs, plans, index costs and query hashes are saved under `evidence/`. Temporary fixture tables existed only inside their client session; no warehouse rows were modified.

## Benchmark protocol

MariaDB 13.0.2 Docker; SF4 seed 10; 8 GiB buffer pool; 32 KiB pages; query cache OFF; persistent-statistics sample pages 160. Exact initial settings and indexes are in `evidence/metadata.json`; all 13 reference settings and the original 167-index set are checked.

One discarded warm-up per final profile, then five serial rounds alternating forward/reversed order. Client wall time includes connection, session preamble and output transfer. Index builds, ANALYZE, visibility changes and plan diagnostics are excluded. No forced cache clearing is used. Original 167 indexes remain visible throughout; experiment-owned indexes are IGNORED where the profile excludes them. Physically present ignored indexes may affect storage/cache conditions, so these are local controlled warmed measurements, not official TPC-DS scores or promises for another scale/hardware.

## Saved files, reference restoration and reuse

Each numbered SQL has a checked `.out`; BEST is an exact alias of `query57_v4_preagg_cover.sql`. `benchmark-results.csv` records final medians/ranges, profiles, repetitions, validation and duration components/totals; ticks are derived 100-nanosecond units, not CPU cycles. `benchmark-runs.csv` records all successful stages. The HTML table and linear bar chart are ordered longest to shortest with original first. The preserved study runner documents the mounted development layout, not a general database installer.

After testing, only the two experiment-owned indexes are removed, restoring the shared **167 visible secondary indexes** and keeping the 8 GiB buffer pool. The SQL-only winner `query57_v2_safe_window.sql` runs directly on that profile. Apply `indexes-BEST.sql` for overall BEST; it adds only the catalog cover, producing 168 secondary indexes.

From the repository root in PowerShell:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q57-SF4 "$($container):/tmp/q57-SF4"
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot tpcds < /tmp/q57-SF4/indexes-BEST.sql'
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q57-SF4/query57_BEST.sql'
```

For an unchanged-index comparison, use the SQL-only file before applying the optional index. Restore the reference afterward by removing only your own addition or by using a clean reference database. Remeasure other datasets, scales and machines independently.
