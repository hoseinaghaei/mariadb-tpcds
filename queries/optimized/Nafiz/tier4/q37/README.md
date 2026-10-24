# Q37 optimization (Tier 4, SF=1)

Q37 finds items that meet price, manufacturer, inventory and date conditions
and have at least one catalog sale. The supplied SQL is preserved as
`query37_v0_original.sql`.

## Plan and bottleneck

The original `EXPLAIN FORMAT=JSON` starts with a full scan of approximately
11.5 million `inventory` rows. It then looks up `item`, `date_dim`, and
`catalog_sales` for each inventory row. The date condition is written on
`date_dim.d_date`, so the optimizer does not initially use the inventory date
index. After adding an exact range on `inv_date_sk`, the plan starts with the
61 matching `date_dim` rows and uses the inventory primary key by date.

`date_dim` confirms that 2002-03-06 through 2002-05-05, inclusive, maps
exactly to date keys `2452340` through `2452400` (61 dates).

## Saved versions

| Version | Change from previous version | Recorded time | Same output |
|---|---|---:|---|
| `v0_original` | Unchanged supplied query | 2.277 s | Reference |
| `v1_date_range` | Add the exact inventory date-key range; retain the original date join and filter | 0.114 s | Yes |
| `v2_range_semijoin` | Keep the range and replace the catalog join with `EXISTS` | 0.111 s | Yes |
| `BEST` | Copy of `v2_range_semijoin` | 0.111 s | Yes |

All three `.out` files have identical SHA-256 hashes. The final result has
one row in this SF=1 dataset. The recorded best run is about 95% faster than
the original. Timings can vary with the buffer cache and other machine load.

The `EXISTS` test is valid here because no catalog column is selected or
aggregated. The original `GROUP BY` removes duplicate rows caused by multiple
catalog sales for the same item; `EXISTS` retains exactly the items that have
at least one catalog sale. In five alternating trials, `v1` took 0.114–0.117 s
and `v2` took 0.110–0.112 s, with matching output each time.

## Rejected test

Removing `date_dim` after adding the key range also returned the same output,
but five alternating runs took 0.117–0.119 s, slower than `v1` at
0.114–0.117 s. It was not saved as a version. No new database index was
needed: the existing primary-key date prefix handles the selective range.

## Files and rerun

Each saved version has a `.sql` and matching `.out` file. The folder also has
`query37_BEST.sql`, `benchmark-results.csv`, and an HTML report with bars
ordered from longest to shortest recorded time.

From this query folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query37_v0_original.sql`, then
`source query37_BEST.sql`. This reruns the SQL; it does not overwrite the
saved `.out`, CSV, or HTML benchmark artifacts.
