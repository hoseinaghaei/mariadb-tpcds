# Q74 optimization — Docker SF4, seed 10

Overall BEST is `query74_v4_early_presence.sql`, copied exactly to `query74_BEST.sql`. Five final measured rounds give **0.165994s** versus original **15.128963s**: **91.14x** faster including four optional indexes.

For the agreed **same 167-index profile**, the SQL-only late-aggregation rewrite `query74_v1_late_customer.sql` measures **6.284006s**, or **2.41x** faster. With the four optional indexes, unchanged original measures **15.384956s**; BEST's SQL gain on that same physical profile is **92.68x**. Index-only timing is a control, not a numbered optimization claim.

## Final retained versions, decreasing runtime

| Version | Criteria | Visible profile | Median seconds | Min–max seconds | Reference speedup |
|---|---|---|---:|---:|---:|
| `v0_original` | Original | reference167 | 15.128963 | 15.015977–15.416642 | 1.00x |
| `v1_late_customer` | Aggregate before customer | reference167 | 6.284006 | 5.826321–8.135451 | 2.41x |
| `v2_web_first` | Web-first eligibility | reference167 + 3 lookup indexes | 0.464069 | 0.427786–0.572270 | 32.60x |
| `v3_stream_guard` | Streaming ID guard | reference167 + 4 lookup indexes | 0.283540 | 0.283120–0.346969 | 53.36x |
| `v4_early_presence` | Early year presence | reference167 + 4 lookup indexes | 0.165994 | 0.160435–0.199845 | 91.14x |

One discarded warm-up and five measured rounds per final profile, alternating forward/reversed execution order. Retained ranges are separated and all faster than the reference original. Sequential version numbers follow final runtime; the method descriptions explain which techniques combine and which are alternatives. Final candidate labels omitted because their ranges did not establish a separate reliable step: final_guarded, final_stream_web.

## Query meaning and initial bottleneck

Q74 compares growth in each customer's **maximum net-paid sale**, rather than summed revenue, between 1999 and 2000 across store and web channels. Both first-year maxima must be positive. All four year/channel groups participate in the original four-way join; missing or NULL second-year maxima cannot satisfy the comparison. Second-year amounts need not be positive. The final output is customer ID, first name and last name, ordered by first name, ID and last name, limited to 100.

The original repeatedly scans sales, joins wide customer rows, groups yearly maxima and joins four instances of the year_total CTE. Initial ordinary reference timings were roughly 15–16 seconds after a discarded 27-second warm-up. Those exploratory readings are preserved separately from the final medians above.

## Index experiments and costs

| Optional index | Ordered columns | Size MiB | Build + ANALYZE seconds |
|---|---|---:|---:|
| `idx_nf_q74_ss_top` | ss_customer_sk,ss_net_paid,ss_sold_date_sk | 469.688 | 20.172 |
| `idx_nf_q74_ws_top` | ws_bill_customer_sk,ws_net_paid,ws_sold_date_sk | 127.219 | 14.175 |
| `idx_nf_q74_customer_order` | c_first_name,c_customer_id,c_last_name | 21.094 | 0.570 |
| `idx_nf_q74_customer_id` | c_customer_id | 9.031 | 0.361 |

The first two indexes group sales by customer and order their net-paid amounts, carrying date keys to verify the year through the original date_dim relationship. The customer output-order index covers the projected fields and implicitly includes the surrogate primary key used for probes. The last index orders business customer IDs for a streaming duplicate check.

The four-index profile costs **627.031 MiB**. Extra indexes alone did not establish a reliable improvement for unchanged SQL in the initial tests, and can move that query's plan unfavorably. They are valuable for the new ordered-lookup strategy rather than a blanket tuning prescription. The final same-index control is recorded explicitly. All original 167 indexes remain visible; none is removed to obtain the improvement.

`indexes-ordered.sql` supplies the first three indexes for the initial guarded lookup methods. `indexes-BEST.sql` supplies all four for the streaming guard variants. The latter changes the live profile to 171 secondary indexes. These additions must be evaluated separately before adoption for the team's complete suite.

## How each method works

### Original reference

The saved v0 is an exact copy of `queries/mariadb/query74.sql`; source SQL, old SF1 files and tuned-query mapping remain unchanged. It groups by customer business ID, first name, last name and year separately for store/web, then joins four totals by business ID.

### Aggregate facts before customer lookup — SQL-only

Sales first aggregate by surrogate customer key and year using MAX with the original date join. Customer names are joined after fact aggregation, and MAX is taken again over **all original customer grouping attributes**, year and channel. The original four self-joins and CASE/division conditions remain. MAX of these partial maxima reproduces the original grouping, including repeated business IDs and all-NULL groups. This version uses the unchanged 167-index profile.

### Guarded ordered maxima — three added indexes

The query performs a runtime check that customer business IDs are unique and non-NULL. On that path, each surrogate customer key represents exactly one original business-ID/name group, so four correlated lookups obtain the 1999/2000 store/web maxima. Each lookup reads the customer-specific net-paid index backward, verifying the date dimension and requested year, and stops at its first qualifying amount. This is equivalent to MAX, including NULL behavior and skipped amounts from other years.

Customers are scanned in the original output order. After 100 customers satisfy the unchanged positive-first-year and CASE/division comparison, the fast branch can stop. Initial actual analysis examined 17,865 customer index rows to emit 100 matches. It does not simply select the first 100 customers before applying the conditions.

If the runtime check finds repeated or NULL business IDs, the slow branch executes the original query, preserving its cross-group combinations and multiplicities. The two branches are mutually exclusive. Each branch applies the original ORDER BY/LIMIT, and the final UNION ALL is ordered and limited again. Since only one branch is active, that branch-local top-100 is valid. This avoids assuming uniqueness just because the current dataset happens to have it.

The first guard uses COUNT(*) versus COUNT(DISTINCT business ID), with the customer output-order index covering its scan. The fallback is the unchanged original semantics with only the branch-selection predicate added.

### Web-first eligibility

Keeps the three-index guarded strategy but checks the positive first-year web maximum before the positive store maximum. On this workload web eligibility is more selective, so the measured plan avoids store probes for many customers without a qualifying web year. SQL does not promise a universal left-to-right speedup; the result here is established by repeated execution on this MariaDB version. The logical conjunction and ratio expressions are unchanged.

### Streaming customer-ID guard

Adds the customer-ID index and replaces COUNT(DISTINCT) work with an ordered GROUP BY/HAVING COUNT(*)>1 existence check, plus an explicit NULL-ID check. This checks the same guard condition while reducing its cost. It is an alternative guard optimization, initially measured with the original store-first eligibility order to isolate its contribution.

### Streaming guard + web-first checks

Combines the faster guard with the more selective first-year web test. Both the ordered MAX probes and original-query fallback remain.

### Early second-year presence — BEST

Keeps the streaming guard and web-first test, then explicitly rejects missing/all-NULL second-year maxima before later expensive probes: web first-year positive, web second-year non-NULL, store first-year positive, store second-year non-NULL, then the original comparison. A missing/NULL second-year maximum would make the original comparison UNKNOWN and reject the row anyway, so this adds no new result restriction. It does not require second-year maxima to be positive; negative and zero second-year cases are tested.

BEST combines these validated refinements. It keeps all date joins in the probes and fallback, the exact MAX input fields and original decimal CASE/division expressions. It does not replace ratio comparison with cross multiplication or remove customer-ID multiplicity handling.

## Other tested approaches

- Late MAX aggregation with direct date-key bounds was tested, but did not add a useful reliable improvement over the simpler original-year predicates. The selected late aggregation keeps only the actual date join/year test.
- The historical pivot matched the real LIMIT-100 sample but fails the repeated-business-ID fixture, because grouping the pivot by one customer name group loses original cross-group combinations. It is not retained here.
- An unforced ordered-lookup query tied the pinned access strategy in repetition. It was not saved as an extra speedup version. Explicit FORCE INDEX clauses make the required access paths and setup clear.
- Index-only tests are recorded even when slower. They are not represented as successful numbered improvements.

`screening-results.csv` summarizes exploratory stages, including their repetition counts. `benchmark-runs.csv` and `evidence/runs.json` preserve every successful warm-up, exploratory and final trial with SQL/output hashes. No elapsed times are supplied by TPC-DS or estimated from EXPLAIN. These are actual local client wall times. The tests do not prove that no further optimization exists.

## Validation

Every final execution returns exactly the same **100 ordered rows** as original. Output SHA-256: `1e5a0a85ebc38ececfa11b3013d029e9ded454ab3e247e4f4cd7c2bfeb73e491`. Original, the reference SQL-only rewrite and overall BEST were also run without LIMIT and matched all **1228 ordered output rows**, including duplicates. For the guarded query, all branch-level and final LIMIT 100 clauses were removed for that separate complete-result comparison; scalar lookup LIMIT 1 clauses remained. Complete-result checking is not the reported LIMIT-query timing.

Fixtures separately exercise the unique-ID fast branch, duplicate-ID original fallback and empty results. They cover duplicate purchases (MAX rather than SUM), NULL maxima, zero/negative first-year totals, missing second years, negative and zero second-year amounts, missing date/customer joins, high amounts in the wrong year, valid boundary dates, NULL first-name ordering and repeated IDs with both equal and different names. All safe rewrites match original. The historical pivot's duplicate-ID mismatch is recorded, not hidden.

The live SF4 data contains 233000 customer rows and 233000 distinct business IDs, so the fast branch is eligible. This is verified at runtime by the saved SQL rather than an external assumption. On data with duplicate IDs the original fallback can be much slower; correctness is retained, not the same speedup. The huge gain also depends on the requested top-100 limit and this dataset's eligibility distribution; no such gain is claimed for processing every customer or for other scales without measurement.

Fixture tables existed only inside their sessions; warehouse data was not edited. Fixture SQLs and outputs, branch checks, complete outputs, actual plans, index costs and the study runner are in `evidence/`.

## Measurement protocol and restoration

MariaDB 13.0.2 Docker; SF4 seed 10; 8 GiB buffer pool; 32 KiB pages; query cache OFF; 160 persistent-statistics sample pages. Exact initial settings/index definitions are in `evidence/metadata.json`; all 13 standing settings and the original 167-index set are verified. No no-index baseline is used.

One discarded warm-up per final profile, five serial measured rounds alternating forward/reversed order, median and min/max client wall times. Timers include connection, session setup and output transfer. Index creation, statistics refresh, visibility changes and diagnostics are outside timing. No forced cache clearing is used. Original indexes stay visible and experiment-owned indexes are IGNORED when excluded from a profile. Their physical presence during trials and cache effects are documented; this is a local warmed experiment, not an official TPC-DS score.

After testing only the four experiment-owned indexes are removed, restoring **167 visible indexes** with the 8 GiB pool. Apply `indexes-BEST.sql` to run overall BEST; use the SQL-only late aggregation directly for the agreed unchanged-index comparison. Each retained SQL has its checked `.out`; BEST is an exact alias. CSV duration ticks are derived 100-nanosecond units, not CPU cycles. The HTML chart/table follow decreasing final median. Build cost and repeated full-result checks are not mixed into the query score.

## Run again

From the repository root in PowerShell:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q74-SF4 "$($container):/tmp/q74-SF4"
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot tpcds < /tmp/q74-SF4/indexes-BEST.sql'
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q74-SF4/query74_BEST.sql'
```

For the reference profile use `query74_v1_late_customer.sql` before adding the optional indexes. Restore the shared profile afterward by removing only your own additions or using a clean reference instance. The evidence runner records development commands and mounted paths; it is not a general fresh-database installer.
