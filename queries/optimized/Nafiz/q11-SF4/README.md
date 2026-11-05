# Q11 optimization — Docker SF4, seed 10

Overall BEST is `query11_v4_late_cover.sql`, copied exactly to `query11_BEST.sql`. Its final median is **2.733465s**, versus reference original **20.506364s**: **7.50x** faster including two new indexes.

For the agreed **same 167-index profile**, the SQL-only rewrite `query11_v3_late_customer.sql` measures **7.646691s**, a **2.68x** improvement over original. With both added covering indexes, unchanged original measures **8.620509s**, so the SQL rewrite improves that same-index comparison by **3.15x**. These are separate comparisons, not one interchangeable score.

## Final versions, decreasing median runtime

| Version | Criteria | Visible index profile | Median seconds | Min–max seconds | Reference speedup |
|---|---|---|---:|---:|---:|
| `v0_original` | Original | reference167 | 20.506364 | 20.219544–22.787763 | 1.00x |
| `v1_store_cover` | Store revenue covering | reference167 + store cover | 11.045827 | 10.979565–14.110561 | 1.86x |
| `v2_both_cover` | Both revenue coverings | reference167 + store/web covers | 8.620509 | 8.589687–9.048926 | 2.38x |
| `v3_late_customer` | Aggregate before customer | reference167 | 7.646691 | 7.468150–7.781549 | 2.68x |
| `v4_late_cover` | Late customer + covering | reference167 + store/web covers | 2.733465 | 2.676297–2.778220 | 7.50x |

Five measured rounds per final profile follow a discarded warm-up; forward/reversed order alternates. Each retained variant's range is faster than the reference original's range. Version numbers follow final medians. Some versions change only physical indexes, and the SQL-only version returns to the reference index profile. They are not all cumulative SQL edits.

## What Q11 asks

Q11 compares each customer's web-sales growth between 2001 and 2002 with store-sales growth over those years. Both first-year totals must be positive and all four year/channel groups must exist. Revenue is the sum of extended list price minus extended discount. Second-year web growth must exceed second-year store growth. The four output customer fields, original division/CASE expressions, ORDER BY and LIMIT remain.

The original groups by seven customer attributes plus year in each channel, UNION ALLs the results, then joins four instances by business customer ID. This means duplicate customer IDs with different grouped attributes can create multiple combinations; dropping those grouping attributes or replacing the four joins with an ordinary per-attribute pivot is not generally equivalent.

## Actual bottleneck and indexing first

The original repeatedly fetches store/web revenue inputs through date indexes that do not cover both price and discount, then joins wide customer rows and groups their attributes. Initial discarded warm-up took about 41s and subsequent reference runs about 20s. Cache-sensitive initial readings are preserved separately; final medians above are the comparison.

| Tested additional index | Ordered columns | Size MiB | Build + ANALYZE seconds |
|---|---|---:|---:|
| `idx_nf_q11_ss_cover` | ss_sold_date_sk,ss_customer_sk,ss_ext_list_price,ss_ext_discount_amt | 511.81 | 21.79 |
| `idx_nf_q11_ws_cover` | ws_sold_date_sk,ws_bill_customer_sk,ws_ext_list_price,ws_ext_discount_amt | 137.25 | 8.01 |

The store index covers the two revenue inputs, date and customer key; unchanged SQL improves materially with this index alone. The web equivalent removes remaining web-row fetches. The selected pair totals **649.06 MiB**. Index creation, statistics refresh and visibility switches are excluded from query timing. The reference's original 167 indexes stay visible throughout; competing new indexes are IGNORED as appropriate for each test profile.

These are Q11-specific physical-design experiments. They are additional to the team's agreed profile, not implicitly part of the reference. Their storage and write-maintenance cost must be considered before adoption for a full benchmark suite. The SQL-only winner is supplied for comparisons that must keep exactly the agreed indexes.

## What each version changes

### Original

`query11_v0_original.sql` is an exact copy of `queries/mariadb/query11.sql`; that source is untouched. All seven customer grouping fields and the original four self-joins are present.

### Store covering and both covering

The SQL files are deliberately identical to original. These versions isolate index benefits: `indexes-store.sql` supplies one index, while `indexes-BEST.sql` supplies both. Their different timings come from their recorded physical profiles, not fabricated SQL edits.

### Late customer aggregation, reference indexes

The new `fact_totals` CTE aggregates each sales channel by customer surrogate key and year using only 2001/2002, with the original date_dim join retained. It sums the same price-minus-discount expression. Customer attributes are joined after those sales aggregates, then totals are regrouped by **all seven original customer attributes**, year and channel. The final four original self-joins, positive first-year tests and ratio expressions are reused.

This reduces the number of wide customer lookups and expensive attribute-grouping inputs. The regrouping is essential: if several surrogate keys share an identical original attribute group, their fact totals must combine. If business IDs repeat with different attributes, separate groups and the original cross-group combinations must remain. This rewrite preserves both cases without assuming that the business ID is unique.

### Late customer aggregation with coverings — BEST

Exactly the same validated SQL rewrite, measured with the two revenue-covering indexes. It combines early fact aggregation with index-only revenue reads. It does not retain the historical pivot, date-key bounds, narrower grouping keys or optimizer session switches. It keeps the actual date joins and year predicates, so orphan dates do not qualify.

## Other tests and why they were not retained

- Explicit 2001/2002 filtering in the original CTE alone did not add a reliable gain; predicate pushdown already limits much of the work.
- Removing unused projected customer fields while keeping their original grouping fields did not help enough. Removing those fields from GROUP BY would be a semantic change and is not used.
- Date-key bounds on the late aggregation were tested repeatedly, but their timings overlapped the simpler year-filtered version. BEST therefore keeps the simpler date-join/year predicates.
- `split_materialized=off` was tested for original and late aggregation. It did not produce a useful reliable extra gain for the new rewrite. Session switches were restored within their client sessions and do not change the standing server configuration.
- The historical SF1 pivot and its split-materialization variant matched this real SF4 output but failed the duplicate-business-ID fixture. They were not copied into the new numbered variants.

Every successful exploratory result and its physical profile is preserved in `benchmark-runs.csv`; `screening-results.csv` summarizes those stages separately. Small/tied readings are not presented as extra improvement steps. More optimization may be possible on other data or hardware; these experiments do not prove a global optimum.

## Validation and historical pivot assumption

All final executions returned exactly the same 100 ordered rows as original. Original and both late-customer profiles were also run without LIMIT and matched **all 1292 output rows**, including multiplicity and the original ordering. Output SHA-256 for the LIMIT query: `b9bdbcf00776c93899ef4be0fc57ecc7b0c6364b3c99ba9e2af50875c8dd0b47`.

A session-local temporary-table fixture checks duplicate purchases, discount subtraction, NULL revenue, zero/negative first-year totals, missing second-year groups, unrelated years, orphan dates, missing customers, duplicate business IDs with different visible attributes, and equal visible attributes with different original hidden grouping fields. It also preserves the original ratio expressions instead of substituting cross multiplication. Every retained-capable safe rewrite matches the original fixture exactly.

The historical pivot collapses or separates groups differently when business IDs repeat, so its fixture result differs. The actual SF4 data has **233000 customer rows and 233000 distinct business IDs**; this explains why the historical pivot can still match the real dataset. The fixture reveals an assumption, not corruption of the SF4 data. Existing SF1 files and the team's tuned-query mapping were not changed. The new rewrite avoids relying on that uniqueness assumption.

`evidence/fixture-validation.json` records the historical rejections explicitly. Fixture SQL/output, complete real outputs, original/rewritten plans, index sizes, SQL hashes and unrounded times are saved under `evidence/`. Fixture tables exist only in their client session; no SF4 base data was edited.

## Measurement protocol and files

MariaDB 13.0.2 Docker; SF4 seed 10; 8 GiB buffer pool; 32 KiB pages; query cache OFF; 160 persistent-statistics sample pages. Exact initial settings and index columns are in `evidence/metadata.json`; all 13 standing reference settings are verified. There is no no-index baseline.

One discarded warm-up per final profile, then five serial rounds alternating forward/reversed order. Client wall time includes connection, session preamble and output transfer. Index builds, ANALYZE, index-visibility changes and EXPLAIN/ANALYZE diagnostics are outside the timer. No forced cache clearing is performed; results describe this local warmed workload and include observed min/max variability. Physical experimental indexes exist but are ignored in the reference-profile trials; that storage/cache condition is documented.

Each numbered SQL has the checked `.out`; BEST is an exact alias. `benchmark-results.csv` contains final medians/ranges, profiles and duration components/totals; ticks are derived 100-nanosecond units, not CPU cycles. `benchmark-runs.csv` records all successful stages and hashes. HTML bars and rows are ordered longest to shortest, original first. The study runner is preserved as evidence, not a general fresh-database installer.

After testing, only the two experiment-owned indexes are removed, restoring the original **167 visible indexes** and keeping the 8 GiB pool. Apply the saved pair before expecting overall BEST's measured runtime; that changes the live profile to 169 secondary indexes. For an unchanged reference profile, use `query11_v3_late_customer.sql` directly.

## Run again

From the repository root in PowerShell:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q11-SF4 "$($container):/tmp/q11-SF4"
# Optional overall BEST profile; index construction is not query timing.
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot tpcds < /tmp/q11-SF4/indexes-BEST.sql'
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q11-SF4/query11_BEST.sql'
```

To compare with the team's 167-index baseline, use the SQL-only file before adding the optional indexes. After testing, restore the reference only by removing your own additions or using a clean reference database. Remeasure other scales and configurations independently.
