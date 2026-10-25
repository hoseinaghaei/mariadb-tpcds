# Query 74 optimization

`v0_original` is the untouched supplied SQL. `v1_pivot_range` calculates
the store and web yearly totals using a pivot and adds direct 1999–2000
date-key ranges. `BEST` is a copy of `v1_pivot_range`.

The saved benchmark measured 10.443 s for `v0` and 6.077 s for `v1`.
A fresh check measured 11.045 s versus 6.280 s. Both returned the same
100 rows and matched their stored `.out` files. The CSV and HTML report
show the original first, then the faster version.

The pivot-only test matched the output but took 12.686 s, slower than the
original. It was rejected and is not retained as a saved version. Its
previous files remain recoverable from the earlier Git commit.

To rerun from this query folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query74_v0_original.sql`, then
`source query74_BEST.sql`. Manual reruns do not overwrite the CSV or HTML.
