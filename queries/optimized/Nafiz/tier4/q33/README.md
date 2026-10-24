# Q33 optimization record

## Objective

Q33 totals July 2000 sales by manufacturer across `store_sales`,
`catalog_sales`, and `web_sales`, restricted to manufacturers that sell Books
and customers in GMT offset -5.  The optimization must return exactly the
same 100 result rows as the supplied TPC-DS query.

## Plan finding

The original plan applies `d_year = 2000` and `d_moy = 7` through a join to
`date_dim` in each of the three sales branches.  It does not give the fact
tables a direct date-key range, so the date restriction is reached later than
necessary.  `date_dim` confirms that July 2000 is exactly key range
`2451727` through `2451757` (31 days).

## Kept versions

| Version | Method | Measured time | Output validation |
|---|---|---:|---|
| `v0_original` | Supplied TPC-DS SQL, unchanged | 2.899 s | Reference output |
| `v1_date_range` | Add the exact July date-key range in each fact branch; retain the original `date_dim` predicates | 0.171 s | Exact SHA-256 match; 100 rows |
| `BEST` | Copy of `v1_date_range` | 0.171 s | Exact SHA-256 match |

`v1_date_range` is about 94% faster in the recorded run.  It is the only
saved candidate because it is both substantially faster and exactly equal to
the original output.

## Rejected test

`date_dim` removal was tested after adding the exact ranges.  Its output was
identical, but five alternating runs averaged 0.170 s compared with 0.174 s
for the range version.  That difference is too small to call reliable, so it
was not saved as another version.

## Files

- `query33_v0_original.sql` and `.out`: untouched baseline and its result.
- `query33_v1_date_range.sql` and `.out`: validated improvement and result.
- `query33_BEST.sql`: selected best SQL.
- `benchmark-results.csv`: machine-readable timing/result summary.
- `optimization-report.html`: visual bar-chart report ordered from longest to
  shortest recorded time.

## Re-run

From this query folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query33_v0_original.sql`, then
`source query33_BEST.sql`. This reruns the SQL; it does not overwrite the
saved `.out`, CSV, or HTML benchmark artifacts.
