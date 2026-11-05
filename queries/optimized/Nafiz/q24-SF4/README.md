# Q24 optimization — Docker SF4

BEST is `v5_zip_window_cover`, copied exactly to `query24_BEST.sql`: **0.022555s** versus original **5.006346s**, **221.96x** faster in this controlled study. Optional index storage for BEST is approximately **474.72 MiB**. These are measured client times, not official TPC scores or proof of a global optimum.

The fastest retained version needing no additional indexes is `v2_zip_window` at **0.142773s**. BEST requires `indexes-BEST.sql` if it lists indexes; its result must not be quoted as running on the unmodified shared95 recipe.

## Results, original first and improvements slowest to fastest

| Version | Approach | Median seconds | Observed range | Speedup |
|---|---|---:|---:|---:|
| `v0_original` | Original | 5.006346 | 4.972453–5.125823 | 1.00x |
| `v1_zip_first` | Store ZIP first | 0.265883 | 0.258539–0.276687 | 18.83x |
| `v2_zip_window` | ZIP first + window | 0.142773 | 0.139466–0.149671 | 35.07x |
| `v3_index_only` | ZIP/customer covering | 0.028420 | 0.027738–0.029320 | 176.16x |
| `v4_zip_cover` | ZIP first + cover | 0.028348 | 0.027859–0.028698 | 176.60x |
| `v5_zip_window_cover` | ZIP/window + cover | 0.022555 | 0.022223–0.023735 | 221.96x |

Only versions with exact SF4 results, passing semantic fixtures, and a maximum of seven final timings below the baseline minimum are retained. This observed-range rule is conservative, not a statistical guarantee across hosts. Version numbers are sequential; individual methods may be alternatives rather than cumulative edits. Rejected SQL is retained only as diagnostic evidence, not numbered improvements.

## Meaning, bottlenecks and correctness

Q24 has **two independent statements/result sets**, first sky and then slate. Each groups returned store sales at the original ten-attribute grain, then compares the selected colour's customer/store total against 5% of the average of **all colours' grouped totals**. The average is not a transaction average, and the colour condition cannot be pushed into that threshold calculation.

The actual SF4 data has five market-10 stores but only two store ZIPs. The original actual plans spend substantial time forming the unfiltered threshold groups. A ZIP-first join order applies store ZIP/address/current customer restrictions before fact lookups. The optional address ZIP index and customer/store sales covering index make these restrictions cheap. The sales secondary index implicitly includes the item/ticket primary key, so those columns are not redundantly declared.

The window alternative calculates AVG(netpaid) OVER() after the original grouping, before filtering the colour, and compares against MAX(threshold) in the outer customer/store group. It preserves NULL sums and the all-colour threshold. It is an alternative to repeated CTE evaluation, not permission to merge the two result sets or change the benchmark protocol. Both result sets were checked individually as well as together.

## Every retained version

### v0_original: Original

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: none. Trial label: `final_original`.

### v1_zip_first: Store ZIP first

Begin with the market/ZIP/address/customer restrictions before fact lookup; retain all joins and both AVG thresholds.

Optional indexes: none. Trial label: `final_zip_first`.

### v2_zip_window: ZIP first + window

Combine early ZIP filtering with one grouped CTE per result set.

Optional indexes: none. Trial label: `final_zip_window`.

### v3_index_only: ZIP/customer covering

Test index access on unchanged original SQL.

Optional indexes: idx_nf_q24_zip, idx_nf_q24_cust_store_cover. Trial label: `final_index_only`.

### v4_zip_cover: ZIP first + cover

Use ZIP lookup and covering customer/store sales lookup with the same join-order rewrite.

Optional indexes: idx_nf_q24_zip, idx_nf_q24_cust_store_cover. Trial label: `final_zip_cover`.

### v5_zip_window_cover: ZIP/window + cover

Combine both independently validated rewrites with optional covering indexes.

Optional indexes: idx_nf_q24_zip, idx_nf_q24_cust_store_cover. Trial label: `final_zip_window_cover`.


## Optional index tests and costs

| Index | Declared columns | Approximate MiB | Build seconds |
|---|---|---:|---:|
| `idx_nf_q24_zip` | `ca_zip` | 5.03 | 0.146 |
| `idx_nf_q24_cust_store_cover` | `ss_customer_sk,ss_store_sk,ss_ext_sales_price` | 469.69 | 11.876 |

Index creation is outside query timing. Sizes use persistent size statistics and 32K pages; maintenance/storage costs and effects on other queries are not established by this query study. Original SQL with provisional BEST's index availability measured **0.028716s**, range **0.027626–0.034751s**, with indexes `idx_nf_q24_zip,idx_nf_q24_cust_store_cover`. Compare that control with the rewritten version only where profiles match. The baseline-to-BEST gain includes any optional-index effect and must not all be credited to SQL rewriting.

## Benchmark protocol

MariaDB 13.0.2, SF4 seed 10, 32K pages, 8 GiB buffer pool and 160 sample pages. The base recipe has exactly 95 secondary indexes (sql/05 + sql/11 + sql/14 minus sql/drop_unreferenced_indexes.sql) pinned at cc4369c. Image and clean source mount remain ffbe5ba; index recipe alignment is recorded separately.

All this query's optional indexes were created once before the study, stayed visible and unchanged during screening/final timing, and were excluded per statement using IGNORE INDEX where required. No CREATE, DROP, ALTER visibility or ANALYZE TABLE occurred between timed conditions. Persistent statistics were saved before and after the study and are byte-identical. The database was returned to shared95 afterward. These comparisons isolate optimizer index availability under fixed statistics; excluded indexes still occupy physical storage, so they do not measure physical removal/cache/maintenance effects.

Each candidate had a discarded warm-up and three exploratory repetitions. Promising candidates had a fresh discarded warm-up and seven final repetitions, alternating forward/reverse order. Final table medians use only final rounds. Time includes MariaDB client startup, session flags, execution and output transfer. Initial inspection and ANALYZE FORMAT=JSON timings are not mixed into benchmark medians.

## Validation and rejected tests

Every timed output matches the original byte for byte. Empty and nonempty edge-case fixtures run in session-local temporary tables with original schema types. Fixtures cover original grouping/multiplicity, NULL rules, missing dimension rows and boundary conditions. Q36 additionally tests all-NULL aggregate inputs and explicit hierarchy/rank semantics. Q24 checks both result sets separately. Q36/Q45 unlimited checks preserve all rows and multiplicity, comparing full row multisets where ordering is tied. See fixture-validation.json and unlimited-validation.json in evidence.

- `window_once`: Final maximum 5.013781s is not below baseline minimum 4.972453s, or unlimited validation failed (final confirmation).



## Files and reproduction

- Versioned SQL and `.out`, BEST aliases, benchmark-results.csv (including duration components/totals and 100ns ticks), benchmark-runs.csv, screening-results.csv, and [the HTML chart](optimization-report.html).
- Evidence includes exact hinted execution SQL, EXPLAIN plans, original actual execution plans, raw trials and hashes, unchanged-statistics snapshots, temporary-table fixtures, full-result comparisons and input snapshots. Top-level original is a byte-exact copy of queries/mariadb/query24.sql; original source and SF1 work are unchanged.
- Top-level versions use only the optional index subset declared for that version. Recreate it with its indexes-version.sql or indexes-BEST.sql. Evidence's executed SQL reproduces the fixed-statistics comparison with all of this query's optional indexes installed; it is intentionally different from the unchanged source baseline because it contains IGNORE INDEX exclusions. Building/dropping a different subset can change statistics and therefore timings.
- Local study entry point: `python3 /setup/next4-sf4.py`, using the prepared /setup/next4-input and /results mounts. The copied runner is development evidence, not a portable fresh-install script. Fixture runner is next4-fixtures.py; it creates only temporary tables. Never rerun a completed output directory without archiving it under a new run identifier.
