# Q10 optimization — Docker SF4, seed 10

BEST is `query10_v3_county_ranges.sql`, copied exactly to `query10_BEST.sql`. Seven final measured rounds gave **0.033464s** versus original **0.213157s**: **6.37x** faster including index changes. With the same county index, unchanged SQL measured **0.065474s**, so the SQL changes add a measured **1.96x** improvement. All versions return the original **44 ordered rows** exactly.

## Final retained versions, longest to shortest

| Version | Criteria | Index profile | Median seconds | Min–max seconds | Reference speedup |
|---|---|---|---:|---:|---:|
| `v0_original` | Original | reference167 | 0.213157 | 0.207504–0.218138 | 1.00x |
| `v1_county_first` | County-first joins | reference167 | 0.125797 | 0.124072–0.130250 | 1.69x |
| `v2_county_index` | County index | reference167 + county index | 0.065474 | 0.064428–0.066991 | 3.26x |
| `v3_county_ranges` | County + date ranges | reference167 + county index | 0.033464 | 0.032874–0.034501 | 6.37x |

Each version has seven measured runs after a discarded warm-up; adjacent retained timing ranges do not overlap. Version numbers follow final runtime, not development chronology. Only reliably faster, validated approaches become numbered versions. Index-only and SQL-only strategies are distinguished below.

## Query meaning and original bottleneck

Q10 counts customers by eight demographic attributes. A customer must have a current address in one of five named counties, a matching current demographic row, at least one store purchase in April–July 2001, and at least one web or catalog purchase in the same period. The web relationship uses **bill customer**; the catalog relationship uses **ship customer**. Counts must remain per customer rather than per sale. The six COUNT outputs all remain in their original positions.

The original actual plan starts with the 122 qualifying dates and scans about 423,000 store-sales index entries, joining tens of thousands of customers before fully using the selective county condition. Web and catalog date/customer sets also require work. Existing customer/date indexes already cover the three sales existence checks, so no new large sales index is needed.

## Indexing was tested first

| Tested index | Ordered columns | Size MiB | Build + ANALYZE seconds |
|---|---|---:|---:|
| `idx_nf_q10_county` | ca_county | 5.031 | 0.147 |
| `idx_nf_q10_addr_demo` | c_current_addr_sk,c_current_cdemo_sk | 9.031 | 0.290 |

`idx_nf_q10_county` lets MariaDB directly find county-qualified addresses. Its InnoDB secondary entries include the address primary key implicitly. The optional customer address/demographic covering index showed only a small additional benefit with overlapping timing ranges in rewrite tests; it was rejected from BEST to avoid requiring another index without a convincing gain. Only the county index is supplied in `indexes-BEST.sql`.

## What changed in every retained version

### v0_original — original reference

Original SQL, all three correlated EXISTS expressions, the OR between web/catalog eligibility, original date joins, grouping and ordering. `query10_v0_original.sql` is an exact copy of `queries/mariadb/query10.sql`; the source file is not edited.

### v1_county_first — SQL-only join ordering

Uses SELECT STRAIGHT_JOIN and lists customer_address before customer and customer_demographics. It encourages county filtering before the purchase checks and prevents the original date/store-driven join strategy from dominating. No new index is visible in this profile. All predicates, the three EXISTS, the web/catalog OR and the complete grouping keys remain intact.

### v2_county_index — physical index alternative

SQL is intentionally identical to v0. Only `idx_nf_q10_county` is added. This separates physical-design benefit from a SQL rewrite. It is an alternative to v1's SQL, not a cumulative copy of v1.

### v3_county_ranges — BEST

Combines the measured county index with v1's address-first STRAIGHT_JOIN and explicit date-key bounds in each EXISTS. Keys `2452001` through `2452122` are the 122 dates from April 1 through July 31, 2001 in this TPC-DS date dimension. The original `d_year=2001` and `d_moy BETWEEN 4 AND 7` predicates and every date_dim join are retained. Bounds help reject unrelated sales through the already-existing customer/date covering indexes before date lookups. This combines index selection, outer join order and early date filtering while preserving missing-date exclusion.

The observed rewritten plan begins with 1,211 matching addresses and approximately 2,464 customer candidates rather than scanning the period's entire store-sales population. EXISTS still prevents repeated purchases or simultaneous web/catalog eligibility from multiplying a customer's count.

## Further tests and rejected approaches

- Date ranges alone on the reference indexes did not improve reliably over original; join order and the county index matter.
- An extra customer address/demographic covering index did not add a clear enough rewrite gain to justify another required index. It was removed after testing.
- The previous SF1 no-date-join version matched the current SF4 output, but failed the missing-date edge case described below. It is not retained here. Its existing SF1 files remain unchanged.
- Disabling `exists_to_in` on the reference profile was much slower. With the county index, correlated EXISTS tied or lost to the simpler selected approach. These session-switch experiments were not saved as final SQL variants.
- Swapping web/catalog OR order did not produce a reliable improvement.
- A UNION ALL inside EXISTS preserves channel eligibility and can short-circuit, but did not improve reliably over the selected original OR structure in repeated tests.
- Checking web/catalog before store eligibility did not improve the actual plan's overall time.
- Disabling join buffering for the channel-first variant was slower.

Every test and index profile has raw successful timings in `benchmark-runs.csv`, with exploratory medians in `screening-results.csv`. Rejected SQL is kept only as investigation evidence in the candidate JSON files, not as extra numbered optimized SQL. Tiny tied differences were not presented as improvements. This search found no further meaningful reliable gain among these tested methods; it does not prove a global optimum.

## Result validation and historical date-join caveat

Each final timed run matched original bytes exactly: all 14 columns, all six counts, ordered rows and values. Original and BEST were also executed without LIMIT and returned the same complete 44 groups. Output SHA-256: `0a313102322cce7d74cc8caac5cc4090253152e973a93085a8b71992f81c72cb`.

A separate nonempty temporary-table fixture checks duplicate purchases, customers qualifying through both web and catalog, a required store purchase, the web/catalog OR, shipping versus billing customer keys, April/July endpoints, excluded months and year, NULL dates/keys, missing addresses and demographics, and an absent date_dim row whose numeric key lies within the selected date range. The original yields two demographic groups with customer counts 3 and 2. Every new retained approach matches it exactly.

The historical `previous_nodate` candidate admits an orphan date key on that fixture because numeric bounds alone cannot establish that a matching date_dim row exists. Its successful current SF4 match depends on the complete date dimension in this dataset. This is a portability assumption exposed by the fixture, not evidence that the SF4 database is corrupt. The new BEST retains all date joins and passes this check. `evidence/fixture-validation.json` explicitly records the historical rejection rather than claiming every tested candidate passed.

Fixture tables existed only inside their client session; no warehouse data was edited. The fixture SQL and output, complete real-data outputs, actual plans and hashes are preserved under `evidence/`.

## Measurement protocol

MariaDB 13.0.2 Docker; SF4 seed 10; 8 GiB buffer pool; 32 KiB pages; query cache OFF; persistent-statistics sample pages 160. All 13 standing reference settings and the original 167-index definitions are checked. Exact settings and initial index columns are saved in `evidence/metadata.json`.

One discarded warm-up per final version, then seven rounds in forward/reversed order. Timings are client wall time including connection, session preamble and result transfer. Index creation, statistics refresh, visibility changes and diagnostic EXPLAIN/ANALYZE runs are excluded. No forced cache clearing was used. Experiments ran serially and preserve all original 167 visible indexes; competing new indexes were IGNORED when testing another profile. This measures the local warmed workload. Millisecond-scale differences close to client overhead are not evidence of universal performance improvements.

## Files and index restoration

Each numbered version has SQL and the checked `.out`. BEST is byte-identical to v3. `benchmark-results.csv` records median/range, profile, repetitions, validation and duration components/totals. Ticks are derived 100-nanosecond units, not CPU cycles. `benchmark-runs.csv` records every successful exploratory/warm-up/final run with SQL/output hashes. `optimization-report.html` orders bars and table longest to shortest with original first. Evidence contains unrounded timings, plans, fixture checks, index costs and the study runner.

After the study only the two experiment-owned indexes are removed, restoring the shared **167 secondary indexes, none ignored**, and 8 GiB buffer pool. Apply `indexes-BEST.sql` to recreate the one selected county index before expecting BEST's recorded runtime. That changes the live profile to 168 secondary indexes. Record it for subsequent comparisons; a Q10 benefit does not establish improvement for other queries. No reference index or original query was altered.

## Run BEST again

From the repository root in PowerShell:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q10-SF4 "$($container):/tmp/q10-SF4"
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot tpcds < /tmp/q10-SF4/indexes-BEST.sql'
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q10-SF4/query10_BEST.sql'
```

For reference-profile timings use the clean 167-index setup. After testing, remove only your experiment-owned addition if restoring that profile. `evidence/study-runner.py` documents the development commands and mounted Docker paths; it is not a general fresh-database installer. Remeasure on other scales and configurations before drawing conclusions about them.
