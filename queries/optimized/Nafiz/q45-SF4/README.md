# Q45 optimization — Docker SF4

BEST is `v5_fact_eligibility_cover`, copied exactly to `query45_BEST.sql`: **0.050040s** versus original **0.421818s**, **8.43x** faster in this controlled study. Optional index storage for BEST is approximately **127.22 MiB**. These are measured client times, not official TPC scores or proof of a global optimum.

The fastest retained version needing no additional indexes is `v4_fact_eligibility` at **0.160199s**. BEST requires `indexes-BEST.sql` if it lists indexes; its result must not be quoted as running on the unmodified shared95 recipe.

## Results, original first and improvements slowest to fastest

| Version | Approach | Median seconds | Observed range | Speedup |
|---|---|---:|---:|---:|
| `v0_original` | Original | 0.421818 | 0.388743–0.456928 | 1.00x |
| `v1_union_cover` | Disjoint branches + cover | 0.240103 | 0.219169–0.258156 | 1.76x |
| `v2_bounded_cover` | Bounds + date cover | 0.167107 | 0.149636–0.194126 | 2.52x |
| `v3_index_only` | Date price covering | 0.163126 | 0.146486–0.164598 | 2.59x |
| `v4_fact_eligibility` | Early fact eligibility | 0.160199 | 0.152734–0.164708 | 2.63x |
| `v5_fact_eligibility_cover` | Fact eligibility + cover | 0.050040 | 0.045930–0.051931 | 8.43x |

Only versions with exact SF4 results, passing semantic fixtures, and a maximum of seven final timings below the baseline minimum are retained. This observed-range rule is conservative, not a statistical guarantee across hosts. Version numbers are sequential; individual methods may be alternatives rather than cumulative edits. Rejected SQL is retained only as diagnostic evidence, not numbered improvements.

## Meaning, bottlenecks and correctness

Q45 totals web sales by current customer ZIP/county when either a ZIP prefix matches or the sold item's **business ID** appears among ten chosen surrogate keys. Other historical item versions sharing those business IDs must remain eligible; replacing the membership test with ten surrogate keys would be wrong.

The actual selected date_dim quarter has 91 keys, 2451911–2452001. The bounds are verified from data, not assumed to end on 31 March; original year/quarter and date existence predicates remain.

The disjoint UNION ALL rewrite separates ZIP-matching rows from item-matching rows whose ZIP condition IS NOT TRUE. This includes NULL ZIPs and avoids double-counting rows satisfying both branches. Branch sums are regrouped by the original ZIP/county key with SUM, preserving all-NULL amounts. A selective variant starts the ZIP branch at address/customer and the item branch at item versions. Prefix LIKE ranges supplement, rather than replace, the original SUBSTR membership condition. Optional date-, customer-, item-leading sales covers and a ZIP index are compared under fixed statistics.

The fact-eligibility refinement builds eligible customer keys from the ZIP test and eligible item surrogate keys from the original business-ID membership. It adds a necessary OR predicate directly on web_sales' customer/item foreign keys, allowing earlier rejection before dimension lookups. The original OR, all dimension joins, date/year/quarter tests and grouping are retained as guards. It does not restrict items to the ten chosen surrogate keys; all matching business-ID versions remain eligible. The earlier completed Q45 batch is preserved in evidence/before-fact-eligibility/; final medians come entirely from the new batch containing this refinement.

## Every retained version

### v0_original: Original

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: none. Trial label: `final_original`.

### v1_union_cover: Disjoint branches + cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q45_date_cover. Trial label: `final_union_cover`.

### v2_bounded_cover: Bounds + date cover

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q45_date_cover. Trial label: `final_bounded_cover`.

### v3_index_only: Date price covering

Unchanged source SQL; its recorded optional-index availability is the experimental difference.

Optional indexes: idx_nf_q45_date_cover. Trial label: `final_index_only`.

### v4_fact_eligibility: Early fact eligibility

Apply necessary ZIP-customer/item-key eligibility on fact foreign keys before expensive dimension lookups; retain original OR, all joins and the verified quarter predicates.

Optional indexes: none. Trial label: `final_fact_eligibility`.

### v5_fact_eligibility_cover: Fact eligibility + cover

Combine early fact-key eligibility with the date/customer/item/price covering index.

Optional indexes: idx_nf_q45_date_cover. Trial label: `final_fact_eligibility_cover`.


## Optional index tests and costs

| Index | Declared columns | Approximate MiB | Build seconds |
|---|---|---:|---:|
| `idx_nf_q45_date_cover` | `ws_sold_date_sk,ws_bill_customer_sk,ws_item_sk,ws_sales_price` | 127.22 | 3.915 |
| `idx_nf_q45_customer_cover` | `ws_bill_customer_sk,ws_sold_date_sk,ws_item_sk,ws_sales_price` | 127.22 | 3.097 |
| `idx_nf_q45_item_cover` | `ws_item_sk,ws_sold_date_sk,ws_bill_customer_sk,ws_sales_price` | 127.22 | 2.825 |
| `idx_nf_q45_zip` | `ca_zip` | 5.03 | 0.110 |

Index creation is outside query timing. Sizes use persistent size statistics and 32K pages; maintenance/storage costs and effects on other queries are not established by this query study. Original SQL with provisional BEST's index availability measured **0.162068s**, range **0.147987–0.167263s**, with indexes `idx_nf_q45_date_cover`. Compare that control with the rewritten version only where profiles match. The baseline-to-BEST gain includes any optional-index effect and must not all be credited to SQL rewriting.

## Benchmark protocol

MariaDB 13.0.2, SF4 seed 10, 32K pages, 8 GiB buffer pool and 160 sample pages. The base recipe has exactly 95 secondary indexes (sql/05 + sql/11 + sql/14 minus sql/drop_unreferenced_indexes.sql) pinned at cc4369c. Image and clean source mount remain ffbe5ba; index recipe alignment is recorded separately.

All this query's optional indexes were created once before the study, stayed visible and unchanged during screening/final timing, and were excluded per statement using IGNORE INDEX where required. No CREATE, DROP, ALTER visibility or ANALYZE TABLE occurred between timed conditions. Persistent statistics were saved before and after the study and are byte-identical. The database was returned to shared95 afterward. These comparisons isolate optimizer index availability under fixed statistics; excluded indexes still occupy physical storage, so they do not measure physical removal/cache/maintenance effects.

Each candidate had a discarded warm-up and three exploratory repetitions. Promising candidates had a fresh discarded warm-up and seven final repetitions, alternating forward/reverse order. Final table medians use only final rounds. Time includes MariaDB client startup, session flags, execution and output transfer. Initial inspection and ANALYZE FORMAT=JSON timings are not mixed into benchmark medians.

## Validation and rejected tests

Every timed output matches the original byte for byte. Empty and nonempty edge-case fixtures run in session-local temporary tables with original schema types. Fixtures cover original grouping/multiplicity, NULL rules, missing dimension rows and boundary conditions. Q36 additionally tests all-NULL aggregate inputs and explicit hierarchy/rank semantics. Q24 checks both result sets separately. Q36/Q45 unlimited checks preserve all rows and multiplicity, comparing full row multisets where ordering is tied. See fixture-validation.json and unlimited-validation.json in evidence.

- `bounds`: Less than 3% exploratory improvement, or slower (screening speed).
- `disjoint_union`: Less than 3% exploratory improvement, or slower (screening speed).
- `selective_union`: Less than 3% exploratory improvement, or slower (screening speed).
- `selective_cover`: Less than 3% exploratory improvement, or slower (screening speed).
- `all_cover`: Less than 3% exploratory improvement, or slower (screening speed).



## Files and reproduction

- Versioned SQL and `.out`, BEST aliases, benchmark-results.csv (including duration components/totals and 100ns ticks), benchmark-runs.csv, screening-results.csv, and [the HTML chart](optimization-report.html).
- Evidence includes exact hinted execution SQL, EXPLAIN plans, original actual execution plans, raw trials and hashes, unchanged-statistics snapshots, temporary-table fixtures, full-result comparisons and input snapshots. Top-level original is a byte-exact copy of queries/mariadb/query45.sql; original source and SF1 work are unchanged.
- Top-level versions use only the optional index subset declared for that version. Recreate it with its indexes-version.sql or indexes-BEST.sql. Evidence's executed SQL reproduces the fixed-statistics comparison with all of this query's optional indexes installed; it is intentionally different from the unchanged source baseline because it contains IGNORE INDEX exclusions. Building/dropping a different subset can change statistics and therefore timings.
- Local study entry point: `python3 /setup/next4-sf4.py`, using the prepared /setup/next4-input and /results mounts. The copied runner is development evidence, not a portable fresh-install script. Fixture runner is next4-fixtures.py; it creates only temporary tables. Never rerun a completed output directory without archiving it under a new run identifier.
