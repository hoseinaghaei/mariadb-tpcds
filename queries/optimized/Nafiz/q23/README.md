# Q23 optimization (Tier 5, SF=1)

Q23 finds catalog and web sales in July 1999 for customers whose store-sales
total exceeds 95% of the largest 1999–2002 customer store-sales total, restricted
to items sold more than four times in a store on the same day. The supplied SQL
contains **two result-producing SELECTs**: a sales total, then customer/name
rows. `query23_v0_original.sql` is a line-for-line copy of
`queries/mariadb/query23.sql`; that source file was not modified.

## Baseline and plan

The original plan scans/aggregates approximately 3.5 million `store_sales`
rows repeatedly for the frequent-item and customer filters. Those CTEs occur
in each of the two SELECTs and in both catalog/web branches. A full local
original run took 54.250–54.335 s in the controlled comparison.

At SF=1, the original first SELECT outputs `NULL` and the second SELECT
returns no rows. The exact original CTE produces 14 qualifying customers;
none has a qualifying July catalog/web item. An empty result is therefore not
by itself evidence of a broken query. The earlier informal estimate of one
qualifying customer was incorrect.

## Saved versions

| Version | Change from previous | Full-file trials (s) | Median (s) | Exact original output? |
|---|---|---|---:|---|
| `v0_original` | Unchanged supplied query | 54.335, 54.250 | 54.293 | Reference |
| `v1_reuse_filters` | Materialize frequent items and best customers once, reuse for both SELECTs | 19.224, 19.290 | 19.257 | Yes |
| `v2_customer_first` | Find best customers and their July channel items first; frequency-test only those items | 8.046, 7.757 | 7.902 | Yes |
| `v3_single_customer_scan` | Compute all-time and 1999–2002 customer totals in one grouped store-sales scan | 3.846, 3.895, 3.658, 3.634, 3.629 | 3.658 | Yes |
| `v4_late_customer_join` | Group store sales before joining customer; apply the join to both max and qualifying sets | 1.427, 1.427, 1.438 | 1.427 | Yes |
| `BEST` | Exact copy of `v4_late_customer_join` | same SQL | 1.427 | Yes |

Each saved version has a matching `.sql` and `.out`; `query23_BEST.sql` and
`query23_BEST.out` duplicate v4. The report HTML and CSV show all saved
versions in descending runtime order. BEST is about **38.0× faster**, or
**97.4% less wall-clock time**, than the local original median.

## Why the rewrite preserves the result

- Temporary tables exist only for the current connection. They do not change
  permanent tables or indexes. `IN` uses set membership, so deduplicating
  candidate/frequent item keys does not change row multiplicity in final sales.
- A final item must be among July channel items bought by a qualifying
  customer; restricting the expensive frequency check to these candidates
  cannot remove a possible final row.
- Grouping by `ss_customer_sk` before joining the unique customer key gives
  the same sums for customers present in `customer`. Both the maximum
  1999–2002 total and the qualifying-customer list join to `customer` in v4.
- `date_dim` was checked: date keys 2451180–2452640 cover exactly 1,461
  rows from 1999-01-01 through 2002-12-31, with no extra dates. This
  substitution applies to the project's current date dimension.
- The original 95% output matched byte-for-byte in every recorded run.
  As a non-empty stress test, both original and v4 were run in memory with
  the threshold changed to 50%; each returned the same three lines
  (aggregate 18769.80 plus two customer rows). Saved SQL retains 95%.

## Rejected tests

- Pre-aggregating numeric item/date keys before the item/date joins took
  18.548 s in one run. It was only a marginal change from v1 and was
  superseded by the much faster customer-first approach.
- Forcing `idx_ss_customer_sk` in v4 took 5.375 s versus about 1.43 s
  without the hint; not kept.
- Adding the July date-key range to v4 took 1.442 s once, no reliable
  improvement over 1.427–1.438 s; not kept.
- No persistent index or permanent schema change was made.

## Validation limit

The existing `queries/results/indexed/query23.json` says the supplied Q23
returns one row versus four in its external reference answer set
(`ROWS_DIFF`). These optimizations reproduce the **supplied MariaDB
query's output**, but they do not resolve that separate reference-answer
mismatch. The course report should not claim official TPC-DS answer-set
qualification from this comparison alone.

## Re-run

From this folder, open the MariaDB client in a fresh connection:

```powershell
& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds
```

At its prompt, run `source query23_v0_original.sql` or
`source query23_BEST.sql`. The BEST file creates and drops connection-local
temporary tables. Both statements must run in the **same MariaDB session**.
If a run is interrupted before the drops, disconnect and reconnect before
rerunning. Timings vary with cache and system load; the CSV records the
measurements made on 25 October 2026.
