# Q34 optimization — Docker SF4

BEST is `v9_hd_cover`, copied exactly to `query34_BEST.sql`: **0.304420s** versus original **6.837074s**, **22.46x** faster in this controlled study. Optional index storage for BEST is approximately **597.97 MiB**. These are measured client times, not official TPC scores or proof of a global optimum.

The fastest retained version needing no additional indexes is `v4_hd_first` at **2.189998s**. BEST requires `indexes-BEST.sql` if it lists indexes; its result must not be quoted as running on the unmodified shared95 recipe.

## Results, original first and improvements slowest to fastest

| Version | Approach | Median seconds | Observed range | Speedup |
|---|---|---:|---:|---:|
| `v0_original` | Original | 6.837074 | 6.813122–7.052778 | 1.00x |
| `v1_no_split` | Materialize ticket groups once | 5.117326 | 5.008048–5.260247 | 1.34x |
| `v2_bounds` | Date bounds + simplification | 5.081949 | 5.037432–5.228358 | 1.35x |
| `v3_date_first` | Date-first ticket groups | 2.271367 | 2.153137–2.320333 | 3.01x |
| `v4_hd_first` | Household-first groups | 2.189998 | 2.044392–2.242065 | 3.12x |
| `v5_date_index` | Date covering | 1.598926 | 1.581130–1.621692 | 4.28x |
| `v6_bounded_date_cover` | Bounds + date cover | 1.143882 | 1.123931–1.173591 | 5.98x |
| `v7_date_cover` | Date first + cover | 0.366012 | 0.360163–0.372947 | 18.68x |
| `v8_hd_index` | Household covering | 0.337429 | 0.331536–0.346403 | 20.26x |
| `v9_hd_cover` | Household first + cover | 0.304420 | 0.296483–0.305267 | 22.46x |

Only versions with exact SF4 results, passing semantic fixtures, and a maximum of seven final timings below the baseline minimum are retained. This observed-range rule is conservative, not a statistical guarantee across hosts. Version numbers are sequential; individual methods may be alternatives rather than cumulative edits. Rejected SQL is retained only as diagnostic evidence, not numbered improvements.

## Meaning, bottlenecks and correctness

Q34 counts qualifying sales separately for each ticket/customer pair, keeps counts 15–20, then joins customer details and sorts. Its original ratio CASE, positive vehicle test, date existence, store existence and household existence are preserved.

All 42 SF4 stores happen to have the selected county, so a county-first plan is not selective on this data. Only 1040 household profiles pass the household tests. Household-first and date-first paths are tested separately, with optional covering indexes in both column orders. The sale's primary-key suffix supplies the ticket/item keys automatically, so the declared indexes need only household/date/store/customer columns.

Date bounds 2450815–2451910 supplement the verified 1998–2000 date_dim predicates; the join and day-of-month filters remain. Duplicate county literals are reduced to one equality, and the buying-potential OR becomes IN. The CASE division is not replaced by unchecked cross-multiplication. A statement-local split_materialized=off condition tests derived materialization separately; it does not change the server's shared optimizer settings.

## Every retained version

### v0_original: Original

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: none. Trial label: `final_original`.

### v1_no_split: Materialize ticket groups once

Test disabling split materialization for this statement only, avoiding a possible per-customer derived execution.

Optional indexes: none. Trial label: `final_no_split`.

### v2_bounds: Date bounds + simplification

Retain date_dim and exact original ratio CASE; simplify duplicate county and buy-potential predicates.

Optional indexes: none. Trial label: `final_bounds`.

### v3_date_first: Date-first ticket groups

Drive from the qualifying days rather than scanning all sales.

Optional indexes: none. Trial label: `final_date_first`.

### v4_hd_first: Household-first groups

Filter the 1040 qualifying household profiles before sales access.

Optional indexes: none. Trial label: `final_hd_first`.

### v5_date_index: Date covering

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q34_date_hd_cover. Trial label: `final_date_index`.

### v6_bounded_date_cover: Bounds + date cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q34_date_hd_cover. Trial label: `final_bounded_date_cover`.

### v7_date_cover: Date first + cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q34_date_hd_cover. Trial label: `final_date_cover`.

### v8_hd_index: Household covering

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q34_hd_date_cover. Trial label: `final_hd_index`.

### v9_hd_cover: Household first + cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q34_hd_date_cover. Trial label: `final_hd_cover`.


## Optional index tests and costs

| Index | Declared columns | Approximate MiB | Build seconds |
|---|---|---:|---:|
| `idx_nf_q34_hd_date_cover` | `ss_hdemo_sk,ss_sold_date_sk,ss_store_sk,ss_customer_sk` | 597.97 | 12.881 |
| `idx_nf_q34_date_hd_cover` | `ss_sold_date_sk,ss_hdemo_sk,ss_store_sk,ss_customer_sk` | 597.97 | 12.865 |

Index creation is outside query timing. Sizes use persistent size statistics and 32K pages; maintenance/storage costs and effects on other queries are not established by this query study. Original SQL with provisional BEST's index availability measured **0.336289s**, range **0.329923–0.342730s**, with indexes `idx_nf_q34_hd_date_cover`. Compare that control with the rewritten version only where profiles match. The baseline-to-BEST gain includes any optional-index effect and must not all be credited to SQL rewriting.

## Benchmark protocol

MariaDB 13.0.2, SF4 seed 10, 32K pages, 8 GiB buffer pool and 160 sample pages. The base recipe has exactly 95 secondary indexes (sql/05 + sql/11 + sql/14 minus sql/drop_unreferenced_indexes.sql) pinned at cc4369c. Image and clean source mount remain ffbe5ba; index recipe alignment is recorded separately.

All this query's optional indexes were created once before the study, stayed visible and unchanged during screening/final timing, and were excluded per statement using IGNORE INDEX where required. No CREATE, DROP, ALTER visibility or ANALYZE TABLE occurred between timed conditions. Persistent statistics were saved before and after the study and are byte-identical. The database was returned to shared95 afterward. These comparisons isolate optimizer index availability under fixed statistics; excluded indexes still occupy physical storage, so they do not measure physical removal/cache/maintenance effects.

Each candidate had a discarded warm-up and three exploratory repetitions. Promising candidates had a fresh discarded warm-up and seven final repetitions, alternating forward/reverse order. Final table medians use only final rounds. Time includes MariaDB client startup, session flags, execution and output transfer. Initial inspection and ANALYZE FORMAT=JSON timings are not mixed into benchmark medians.

## Validation and rejected tests

Every timed output matches the original byte for byte. Empty and nonempty edge-case fixtures run in session-local temporary tables with original schema types. Fixtures cover original grouping/multiplicity, NULL rules, missing dimension rows and boundary conditions. Q36 additionally tests all-NULL aggregate inputs and explicit hierarchy/rank semantics. Q24 checks both result sets separately. Q36/Q45 unlimited checks preserve all rows and multiplicity, comparing full row multisets where ordering is tied. See fixture-validation.json and unlimited-validation.json in evidence.

- Every screened method was retained or is recorded as a control; see raw trials.

The initial Q34 hint renderer incorrectly touched table-qualified column names. Those statements failed parsing before timing and are preserved in evidence/failed-hint-renderer/. The renderer was corrected, owned indexes removed, and the entire study restarted from shared95.

## Files and reproduction

- Versioned SQL and `.out`, BEST aliases, benchmark-results.csv (including duration components/totals and 100ns ticks), benchmark-runs.csv, screening-results.csv, and [the HTML chart](optimization-report.html).
- Evidence includes exact hinted execution SQL, EXPLAIN plans, original actual execution plans, raw trials and hashes, unchanged-statistics snapshots, temporary-table fixtures, full-result comparisons and input snapshots. Top-level original is a byte-exact copy of queries/mariadb/query34.sql; original source and SF1 work are unchanged.
- Top-level versions use only the optional index subset declared for that version. Recreate it with its indexes-version.sql or indexes-BEST.sql. Evidence's executed SQL reproduces the fixed-statistics comparison with all of this query's optional indexes installed; it is intentionally different from the unchanged source baseline because it contains IGNORE INDEX exclusions. Building/dropping a different subset can change statistics and therefore timings.
- Local study entry point: `python3 /setup/next4-sf4.py`, using the prepared /setup/next4-input and /results mounts. The copied runner is development evidence, not a portable fresh-install script. Fixture runner is next4-fixtures.py; it creates only temporary tables. Never rerun a completed output directory without archiving it under a new run identifier.
