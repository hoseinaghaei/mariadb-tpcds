# Q7 optimization — Docker SF4, seed 10

BEST is `query7_v3_item_ordered_range.sql`, copied exactly to `query7_BEST.sql`. It requires the two indexes in `indexes-BEST.sql`. Five final measured rounds returned the same ordered 100 rows for every retained version. Original and BEST also returned identical complete grouped results without LIMIT: **16,364 groups**.

## Final measured versions

| Version | Optimization criteria | Index profile | Median seconds | Min–max seconds | Reference speedup |
|---|---|---|---:|---:|---:|
| `v0_original` | Original | reference167 | 0.418745 | 0.414998–0.438239 | 1.00x |
| `v1_demo_cover` | Demographic covering | reference167 + demo cover | 0.213024 | 0.209037–0.232645 | 1.97x |
| `v2_item_ordered` | Ordered item access | reference167 + item pair | 0.067750 | 0.066680–0.069310 | 6.18x |
| `v3_item_ordered_range` | Ordered date range | reference167 + item pair | 0.030198 | 0.029975–0.031061 | 13.87x |

Versions are numbered from longest to shortest final median. Every retained step has a non-overlapping five-run timing range. BEST is 13.87x faster than the original on the reference profile, including the index changes. With the **same item-index profile**, unchanged original SQL measured 0.410520s versus BEST 0.030198s: **13.59x**. This separates SQL-rewrite benefit from physical-index benefit.

## What changed in each version

### v0_original — reference

The original SQL is untouched. Its demographic predicate uses `idx_cd_filter_sk`, then looks up sales through `idx_ss_cdemo_sk`. Initial ANALYZE recorded about 155,942 sales rows, 74,150 physical page reads and 11.8 seconds total. Initial ordinary runs were around 11 seconds. After the experiment warmed the working set, the original became much faster. Those early numbers are exploratory evidence, not the baseline used for the final speedup.

### v1_demo_cover — index-only improvement

SQL is intentionally identical to v0. `indexes-v1-demo.sql` adds a demographic-first sales covering index containing the date, item and promotion keys plus all four AVG inputs. The plan reads the required sales columns from the index and avoids base-row lookups. This is a physical-design experiment, not a SQL rewrite. The separate date-first covering index did not produce the desired access path and was rejected.

### v2_item_ordered — exploit GROUP BY / ORDER BY / LIMIT

This alternative replaces the demographic-first access strategy. It uses the item-index pair rather than retaining the v1 demographic covering index. `item(i_item_id)` supplies item-ID order; the item-first covering sales index supplies every sales column Q7 needs. STRAIGHT_JOIN and FORCE INDEX pin this measured access path. MariaDB can finish complete item-ID groups in order and stop after 100 groups, instead of aggregating every matching item and sorting them. GROUP BY remains `i_item_id`, preserving aggregation across multiple item surrogate keys with the same business ID. Date, demographic and promotion joins and the original AVG expressions remain.

### v3_item_ordered_range — BEST

Keeps the v2 item-index strategy and adds `ss_sold_date_sk BETWEEN 2450815 AND 2451179`. On this TPC-DS date dimension those keys are exactly the 365 dates in 1998. The original date join and `d_year=1998` are retained, so missing dimension rows and join semantics stay intact. The range rejects other years before later demographic lookups. ANALYZE shows 351 item rows examined and no full-result filesort for the LIMIT query. The selected SQL combines ordering, covering access and early date filtering. It does not combine the competing demographic-first index strategy.

## Tests that did not become extra versions

These were real executed tests with exact output checks. Tied or slower approaches are documented here and in raw evidence, rather than inflated into extra numbered SQL files. Screening medians below belong to their own index/cache stage; use the final table for the retained version comparison.

| Test | Screening median seconds | Observation |
|---|---:|---|
| `idx_nf_q7_date_cover` | 10.237809 | Date-first covering index: original retains the expensive demographic access path. |
| `reference_range` | 0.383478 | Date range alone on reference indexes; faster in screening, but not selected over the covering approaches. |
| `previous_sf1_best` | 3.817027 | Earlier SF1 date-first hint: slower than the new approaches on SF4. |
| `date_range` | 0.201638 | Date filter with demographic covering: similar to covering alone. |
| `no_date_join` | 0.202842 | Removing date_dim: no reliable extra gain; retained BEST keeps the join. |
| `range_no_bka` | 0.209702 | Disable join buffering: no reliable extra gain. |
| `range_demo_first` | 0.205471 | Force demographic-first joins: no reliable extra gain. |
| `semijoin` | 0.205122 | IN/semi-join rewrite: no reliable extra gain. |
| `ordered_no_date` | 0.029709 | Date join removal: approximately tied with the selected SQL. |
| `ordered_no_force` | 0.030055 | Remove FORCE INDEX: approximately tied; selected SQL pins the measured access paths. |
| `ordered_no_straight` | 0.029891 | Remove STRAIGHT_JOIN: approximately tied; selected SQL pins item-first ordering. |
| `ordered_no_bka` | 0.030649 | Disable join buffering: approximately tied. |
| `ordered_promo_first` | 0.034898 | Promotion-first filtering after sales: slower than demographic-first filtering. |

The earlier SF1 BEST file contained a UTF-8 BOM. One helper invocation initially sent the BOM to MariaDB and failed before returning results. It was corrected by decoding that historical file with `utf-8-sig`; only successful executions appear in the timing table. The source file was not edited.

## Index cost and configuration

| Added index | Size MiB | Build seconds |
|---|---:|---:|
| `idx_nf_q7_demo_cover` | 723.97 | 32.04 |
| `idx_nf_q7_item_id` | 3.03 | 0.19 |
| `idx_nf_q7_item_cover` | 723.97 | 27.36 |

The shared reference is 167 secondary indexes, all visible, with an 8 GiB buffer pool and 32 KiB pages. v1 uses one additional index. v2/v3 use two additional indexes. Competing experimental indexes were IGNORED during each profile's tests; the original 167 stayed visible throughout. Index builds, visibility changes, ANALYZE and plan diagnostics are excluded from query timings. The index-only and item-first alternatives require different setups; they are not cumulative. Index storage and maintenance are real tradeoffs. Q7-only gains do not establish that these indexes improve the full suite.

After completing the study, the temporary indexes created solely by this experiment are removed to restore the shared 167-index profile. Their measured definitions are supplied here for reproduction. Do not expect BEST's measured runtime until `indexes-BEST.sql` is applied. Do not drop or ignore teammates' existing indexes to reproduce this study.

## Benchmark and validation protocol

MariaDB 13.0.2 in Docker; SF4, generator seed 10; dedicated serial workload; query cache OFF; 8 GiB buffer pool; 32 KiB pages; 160 persistent-statistics sample pages; all 13 standing reference settings checked before the study. Exact initial settings and index columns are saved in `evidence/metadata.json`.

Each candidate receives a discarded warm-up. The final comparison has five measured rounds with forward/reversed execution order, with the required experimental index visibility selected outside each timer. Times are client wall time including connection, session preamble and result transfer. They describe this warmed local working set; there is no claim of a controlled cold-cache benchmark. No forced cache clearing or concurrent benchmark workload is used. EXPLAIN/ANALYZE diagnostics are separate from ordinary timing. At approximately 30 ms, client overhead is a meaningful part of the total; tiny differences between tied variants are not evidence of further improvement.

Every successful timed run matched the original ordered output byte for byte: all five columns, 100 rows, duplicates, NULL text and decimal results retained. Output SHA-256: `faf9868450fc3d1e4ec1c9dc85367b09307550da3a64bdee2e4d408cf1ba4c17`. The complete grouped original/BEST comparison without LIMIT also matched byte for byte; its files and hash are saved in `evidence/`. This is real nonempty SF4 validation, not a proof for every possible database or scale factor. No aggregate formula or grouping key was changed.

`benchmark-results.csv` summarizes the final retained versions and includes component and total duration units (ticks are derived 100-nanosecond units, not CPU cycles). `benchmark-runs.csv` includes every successful exploratory/warm-up/final run, identified by label and index profile. `evidence/runs.json` preserves the unrounded timings and query/output hashes; diagnostic plans, index sizes, full outputs and validation records are also included. Each retained SQL has a `.out`; BEST is an exact alias of v3.

## Reproduce

Use the same SF4 seed-10 server and reference configuration. Copy this folder into a running container, apply the appropriate index script outside query timing, and run the desired SQL through the Unix socket. For example, from the repository root in PowerShell:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q7-SF4 "$($container):/tmp/q7-SF4"
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot tpcds < /tmp/q7-SF4/indexes-BEST.sql'
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q7-SF4/query7_BEST.sql'
```

The index setup changes the live physical profile to 169 secondary indexes. Record that profile in subsequent benchmarks. To reproduce the shared 167-index baseline, use a clean reference database or explicitly remove only these experiment-owned indexes after saving any needed results. The supplied `evidence/study-runner.py` records the original development protocol; its `/project` and `/results` paths refer to the mounted Docker layout. It is evidence, not an automatic fresh-database setup script.

Further gains may exist on other data, hardware or scale factors. The tested alternatives stopped producing a reliable improvement beyond the selected combination; this does not prove a global optimum.
