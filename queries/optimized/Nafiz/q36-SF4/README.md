# Q36 optimization — Docker SF4

BEST is `v8_late_item_cover`, copied exactly to `query36_BEST.sql`: **1.214941s** versus original **12.163015s**, **10.01x** faster in this controlled study. Optional index storage for BEST is approximately **511.81 MiB**. These are measured client times, not official TPC scores or proof of a global optimum.

The fastest retained version needing no additional indexes is `v7_late_item` at **3.078147s**. BEST requires `indexes-BEST.sql` if it lists indexes; its result must not be quoted as running on the unmodified shared95 recipe.

## Results, original first and improvements slowest to fastest

| Version | Approach | Median seconds | Observed range | Speedup |
|---|---|---:|---:|---:|
| `v0_original` | Original | 12.163015 | 11.894571–12.433330 | 1.00x |
| `v1_raw_levels` | Raw level expansion | 9.349200 | 9.217469–9.538915 | 1.30x |
| `v2_index_only` | Profit/price covering | 9.130291 | 8.985260–10.221789 | 1.33x |
| `v3_bounded_leaf` | Bounded leaf aggregation | 5.231889 | 5.174191–5.358842 | 2.32x |
| `v4_leaf_levels` | Single leaf aggregation | 5.095613 | 4.916996–5.211637 | 2.39x |
| `v5_bounded_cover` | Bounded leaf + cover | 4.275406 | 4.200686–4.801188 | 2.84x |
| `v6_leaf_cover` | Leaf levels + cover | 4.165205 | 4.028511–4.658738 | 2.92x |
| `v7_late_item` | Aggregate before item | 3.078147 | 3.016498–3.253953 | 3.95x |
| `v8_late_item_cover` | Late item + cover | 1.214941 | 1.197846–1.273612 | 10.01x |

Only versions with exact SF4 results, passing semantic fixtures, and a maximum of seven final timings below the baseline minimum are retained. This observed-range rule is conservative, not a statistical guarantee across hosts. Version numbers are sequential; individual methods may be alternatives rather than cumulative edits. Rejected SQL is retained only as diagnostic evidence, not numbered improvements.

## Meaning, bottlenecks and correctness

Q36 must distinguish **real NULL category/class values from generated subtotal levels**. The starting point is the current corrected queries/mariadb/query36.sql with explicit grouping levels. The historical SF1 NULL-detection ROLLUP rewrite is not adopted here.

The original source_rows CTE is read by three hierarchy branches; its actual execution diagnostics show repeated fact work. The single-leaf rewrite first computes SUM(profit) and SUM(price) per category/class. It then expands the small leaf table into levels 0, 1 and 2 and groups using level-dependent keys. Only after summing the numerators and denominators does it divide. It never averages margins. Explicit level tags preserve real NULL groups and duplicate-looking subtotal rows. Empty input produces no grand-total row, matching the corrected original.

The further aggregate-before-item refinement groups qualifying facts by numeric item key after date/store filtering. It joins the unique item primary key only once per resulting item group, then sums again at the original category/class grain. Missing item rows are still excluded. Separate profit and price sums preserve NULL rules, and division happens only at the final hierarchy level; margins are never averaged.

The same RANK partition and final ORDER BY/LIMIT remain. Date bounds retain the date_dim/year check. An optional date/item/store/profit/extended-price covering index removes base-row fetches; an unchanged-SQL index control separates it from the rewrite. Raw fact expansion is also tested as a contrasting method and kept only if reliably faster. Unlimited result checks include every hierarchy row and rank; tied output ordering in fixtures is compared by full row multiplicity.

## Every retained version

### v0_original: Original

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: none. Trial label: `final_original`.

### v1_raw_levels: Raw level expansion

Test one fact scan with three raw grouping-level rows per fact rather than preaggregating leaves.

Optional indexes: none. Trial label: `final_raw_levels`.

### v2_index_only: Profit/price covering

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q36_date_cover. Trial label: `final_index_only`.

### v3_bounded_leaf: Bounded leaf aggregation

Add verified date bounds to the single-pass hierarchy.

Optional indexes: none. Trial label: `final_bounded_leaf`.

### v4_leaf_levels: Single leaf aggregation

Read facts once, then expand the small leaf result into three explicit hierarchy levels; retain genuine NULL identities.

Optional indexes: none. Trial label: `final_leaf_levels`.

### v5_bounded_cover: Bounded leaf + cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q36_date_cover. Trial label: `final_bounded_cover`.

### v6_leaf_cover: Leaf levels + cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q36_date_cover. Trial label: `final_leaf_cover`.

### v7_late_item: Aggregate before item

Aggregate qualifying facts by numeric item key before item lookups; regroup sums at category/class grain, then form explicit hierarchy levels.

Optional indexes: none. Trial label: `final_late_item`.

### v8_late_item_cover: Late item + cover

Combine late item lookup and explicit hierarchy with the date/profit/price covering index.

Optional indexes: idx_nf_q36_date_cover. Trial label: `final_late_item_cover`.


## Optional index tests and costs

| Index | Declared columns | Approximate MiB | Build seconds |
|---|---|---:|---:|
| `idx_nf_q36_date_cover` | `ss_sold_date_sk,ss_item_sk,ss_store_sk,ss_net_profit,ss_ext_sales_price` | 511.81 | 11.600 |

Index creation is outside query timing. Sizes use persistent size statistics and 32K pages; maintenance/storage costs and effects on other queries are not established by this query study. Original SQL with provisional BEST's index availability measured **9.249064s**, range **9.073552–9.788600s**, with indexes `idx_nf_q36_date_cover`. Compare that control with the rewritten version only where profiles match. The baseline-to-BEST gain includes any optional-index effect and must not all be credited to SQL rewriting.

## Benchmark protocol

MariaDB 13.0.2, SF4 seed 10, 32K pages, 8 GiB buffer pool and 160 sample pages. The base recipe has exactly 95 secondary indexes (sql/05 + sql/11 + sql/14 minus sql/drop_unreferenced_indexes.sql) pinned at cc4369c. Image and clean source mount remain ffbe5ba; index recipe alignment is recorded separately.

All this query's optional indexes were created once before the study, stayed visible and unchanged during screening/final timing, and were excluded per statement using IGNORE INDEX where required. No CREATE, DROP, ALTER visibility or ANALYZE TABLE occurred between timed conditions. Persistent statistics were saved before and after the study and are byte-identical. The database was returned to shared95 afterward. These comparisons isolate optimizer index availability under fixed statistics; excluded indexes still occupy physical storage, so they do not measure physical removal/cache/maintenance effects.

Each candidate had a discarded warm-up and three exploratory repetitions. Promising candidates had a fresh discarded warm-up and seven final repetitions, alternating forward/reverse order. Final table medians use only final rounds. Time includes MariaDB client startup, session flags, execution and output transfer. Initial inspection and ANALYZE FORMAT=JSON timings are not mixed into benchmark medians.

## Validation and rejected tests

Every timed output matches the original byte for byte. Empty and nonempty edge-case fixtures run in session-local temporary tables with original schema types. Fixtures cover original grouping/multiplicity, NULL rules, missing dimension rows and boundary conditions. Q36 additionally tests all-NULL aggregate inputs and explicit hierarchy/rank semantics. Q24 checks both result sets separately. Q36/Q45 unlimited checks preserve all rows and multiplicity, comparing full row multisets where ordering is tied. See fixture-validation.json and unlimited-validation.json in evidence.

- `bounds`: Final maximum 11.922559s is not below baseline minimum 11.894571s, or unlimited validation failed (final confirmation).

An earlier partial batch hit the server 180-second limit on the original query in round 5 after previous original runs near 12 seconds. Persistent statistics were unchanged; the cause of that runtime outlier is not established. That incomplete batch, its raw trials, timeout log and statistics are preserved under evidence/partial-before-item-refinement/. None of its timings enter the final table. The complete comparison was restarted from shared95 with aggregate-before-item candidates included. A successful final median does not erase the earlier observed timeout.

## Files and reproduction

- Versioned SQL and `.out`, BEST aliases, benchmark-results.csv (including duration components/totals and 100ns ticks), benchmark-runs.csv, screening-results.csv, and [the HTML chart](optimization-report.html).
- Evidence includes exact hinted execution SQL, EXPLAIN plans, original actual execution plans, raw trials and hashes, unchanged-statistics snapshots, temporary-table fixtures, full-result comparisons and input snapshots. Top-level original is a byte-exact copy of queries/mariadb/query36.sql; original source and SF1 work are unchanged.
- Top-level versions use only the optional index subset declared for that version. Recreate it with its indexes-version.sql or indexes-BEST.sql. Evidence's executed SQL reproduces the fixed-statistics comparison with all of this query's optional indexes installed; it is intentionally different from the unchanged source baseline because it contains IGNORE INDEX exclusions. Building/dropping a different subset can change statistics and therefore timings.
- Local study entry point: `python3 /setup/next4-sf4.py`, using the prepared /setup/next4-input and /results mounts. The copied runner is development evidence, not a portable fresh-install script. Fixture runner is next4-fixtures.py; it creates only temporary tables. Never rerun a completed output directory without archiving it under a new run identifier.
