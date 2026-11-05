# Q33 optimization — Docker SF4, seed 10

BEST is `query33_v2_union_first.sql`, copied exactly to `query33_BEST.sql`. Seven final measured rounds gave **0.080047s** versus original **0.117565s**: **1.47x** faster. **Both use the same agreed 167 visible secondary indexes and 8 GiB buffer pool. No additional index is required.**

## Retained versions, longest to shortest

| Version | Criteria | Median seconds | Min–max seconds | Speedup |
|---|---|---:|---:|---:|
| `v0_original` | Original | 0.117565 | 0.115761–0.118847 | 1.00x |
| `v1_late_books` | Late manufacturer filter | 0.106677 | 0.104649–0.111982 | 1.10x |
| `v2_union_first` | Union before aggregation | 0.080047 | 0.076470–0.085151 | 1.47x |

Each retained version has seven measured rounds after a discarded warm-up. Only separated, reliably faster steps are retained and numbered sequentially. All 100 ordered output rows match the original exactly; complete totals for **904 manufacturers** also match after ordering by manufacturer key for that separate complete-result comparison.

## Query meaning and actual bottleneck

Q33 totals July 2000 sales by manufacturer across store, catalog and web sales, using addresses at GMT offset -5. The manufacturer must have at least one item in the Books category. This is **manufacturer membership**, not a restriction that every sold item itself be a Book: non-Book products from eligible manufacturers must contribute too.

Each original channel aggregates by manufacturer, materializes that result and UNION ALLs the three aggregates, then aggregates again. It also repeats the Books-manufacturer eligibility calculation in all three branches. The original plan already uses date-leading covering sales indexes. Actual diagnostics show about 105,491 store address probes, 55,692 catalog address probes and 27,861 web address probes, followed by tens of thousands of item lookups and repeated manufacturer-set work. Initial diagnostic time was about 138.5ms; ordinary timings are recorded separately and are not replaced by plan diagnostics.

## Index investigation first

| Tested index | Ordered columns | Size MiB | Build + ANALYZE seconds |
|---|---|---:|---:|
| `idx_nf_q33_item_cover` | i_item_sk,i_manufact_id | 1.031 | 0.175 |
| `idx_nf_q33_book_manufact` | i_category,i_manufact_id | 5.031 | 0.179 |

The first index covers narrow item-key/manufacturer lookups. The second covers category/manufacturer membership without fetching the wider item row. Each was tested independently and together, with the original 167 indexes always visible. They gave small/tied changes for unchanged SQL; forcing the item cover and using both indexes also did not establish a sufficiently reliable useful gain over the SQL-only finalist to justify extra required indexes. All such timings and definitions are preserved as evidence. They are not silently included in the headline speedup.

The selected SQL relies on the repository's existing covering fact indexes, date indexes and item/category indexes. `indexes-BEST.sql` is a comment-only notice that no extra index is needed. After testing the two experiment-owned indexes were removed and the exact shared reference set was verified again.

## How each retained SQL version works

### v0_original

Original SQL with three grouped channel CTEs and a final manufacturer aggregation. The saved v0 is an exact copy of `queries/mariadb/query33.sql`; that source and the earlier SF1 optimization folder were not edited.

### Late manufacturer filtering

The three channels still join sales to item, date_dim and customer_address and aggregate by manufacturer, but the Books-manufacturer IN predicate is applied once to the combined channel totals rather than independently in every branch. Moving this predicate is valid because it depends only on the manufacturer grouping key. It does not change which sales contribute to an eligible manufacturer's sum. Retained as `v1_late_books` because its seven-run timing range is separate from both original and BEST.

### v2_union_first — BEST

Each channel first filters its own sales through the original July date join and GMT-offset address join. It projects only item key and extended sales price, then combines those filtered rows with **UNION ALL**. The outer query joins those rows to item and to a DISTINCT set of Books manufacturers, then performs a single manufacturer SUM aggregation.

This removes the three branch-level manufacturer aggregations and their nested materialized result tables. Manufacturer membership is expressed once in the query. The Books set is DISTINCT, preventing several Book items from multiplying the same manufacturer's sales. All eligible non-Book products remain included. The two-stage branch-SUM/final-SUM is replaced by one SUM over the same multiset of values; duplicate purchases and channels are preserved by UNION ALL. Decimal amounts are kept without conversion. All-NULL groups remain NULL.

BEST is a structural continuation of moving manufacturer eligibility to the combined stream, with aggregation performed once after the UNION. It is not a combination of every tested strategy: it does not retain the extra indexes, force-index hints, global item preaggregation or join-cache session changes.

## Other methods actually tested

- Explicit July date-key ranges (`2451727` through `2451757`, 31 days) with all date joins retained were slower here. The SF1 date-range gain does not carry over automatically to this SF4 indexed plan.
- A shared DISTINCT Books CTE while retaining all three channel manufacturer aggregations gave little benefit; the important structural gain was removing the extra aggregation layers.
- Per-channel item preaggregation added grouping work and was slower than the raw filtered UNION stream.
- A materialized eligible-item set did not improve reliably over the simple item join.
- Forcing narrow item-index access did not beat the unforced UNION approach reliably enough to select it.
- Global item totals after the UNION tied the simpler UNION query rather than providing a useful reliable reduction.
- Disabling join buffering tied/slowed the selected query and was not retained.
- The two added item indexes produced small changes with overlapping ranges in repeated tests; no final variant requires them.

`screening-results.csv` contains exploratory medians for each labeled physical profile. `benchmark-runs.csv` preserves all successful exploratory, warm-up and final timings with query/output hashes. Do not mix a screening reading or ANALYZE time with the final seven-round median. Rejected SQL texts remain evidence JSON, not extra numbered optimized files. These tests do not prove that no future optimization is possible.

## Correctness checks

Every real-data timed candidate matched the original ordered 100-row output byte for byte. The final original, late-filter and UNION-first candidates were also run without LIMIT, ordered by `i_manufact_id` for complete comparison; all **904 manufacturer totals** matched exactly. This separate keyed comparison avoids treating the original ORDER BY total_sales as a complete tie-breaker for all rows. Main query ordering and LIMIT are unchanged.

A nonempty temporary-table fixture validates manufacturer membership through another item, several Books from one manufacturer, non-Book sales from that manufacturer, duplicate sale rows, all three channels, negative and zero sales, all-NULL manufacturer totals, NULL manufacturer IDs, excluded GMT offsets, July endpoints, wrong month/year, orphan date keys, and missing items/addresses. Every candidate passed exactly. Expected fixture results are manufacturer 30 -> NULL, 50 -> 0.00, 40 -> 2.00 and 10 -> 26.00. The Books-set DISTINCT is important to that result. Fixture tables existed only inside their client session and did not modify the warehouse.

Real output SHA-256: `cce7fd86e6248f8899787e64345ef47a9a63b77b8611169e4a42b6d8e0529017`. Actual outputs, full keyed totals, fixture SQL/output/checks and EXPLAIN/ANALYZE JSON are in `evidence/`. This is measured correctness on this nonempty SF4 instance and the fixture, not a proof for every future schema or data type.

## Benchmark protocol and limits

MariaDB 13.0.2 in Docker; SF4 seed 10; 8 GiB buffer pool; 32 KiB pages; query cache OFF; persistent-statistics sample pages 160. Exact initial settings and index columns are in `evidence/metadata.json`. All 13 standing reference settings and the 167-index profile are verified. No no-index baseline is used.

One discarded warm-up per final version, then seven measured serial rounds with forward/reversed order. Medians and min/max are client wall times including connection, session preamble and result transfer. Index builds, visibility changes, ANALYZE and plan diagnostics are excluded. There is no forced cache clear; the results describe the warmed local working set. Both experimental indexes are IGNORED throughout the final SQL-only comparison. Their physical presence during measurement is documented; they are removed afterward. Avoid interpreting small millisecond fluctuations as universal gains. Other scales and machines require new measurements.

## Files and reuse

Each retained SQL has its checked `.out`; BEST is an exact alias of `v2_union_first`. `benchmark-results.csv` contains final medians/ranges, profile, validation and duration components/totals; ticks are derived 100-nanosecond units, not CPU cycles. `benchmark-runs.csv` includes every successful stage. `optimization-report.html` orders bars and rows from original/longest to BEST/shortest. The README records accepted and rejected methods and index costs. Evidence contains the development runner and unrounded values.

After testing, the shared 167-index configuration is restored and verified. BEST can run immediately on it; no additional index setup is required. From the repository root in PowerShell:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q33-SF4 "$($container):/tmp/q33-SF4"
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q33-SF4/query33_BEST.sql'
```

The preserved study runner uses mounted `/project`, `/setup` and `/results` paths and records the development experiment; it is not a general fresh-database setup script. Existing SF1 results remain historical measurements of their own configuration.
