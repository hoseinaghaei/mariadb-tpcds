# Query 11 optimization

`v0_original` is the unchanged supplied SQL. `v1_pivot` aggregates only
2001 and 2002, then pivots the four required store/web totals per customer.
`v2_pivot_range` keeps that pivot and adds direct source date-key ranges.

| Version | Recorded time | Same output |
|---|---:|---|
| `v0_original` | 17.343 s | Reference |
| `v1_pivot` | 13.804 s | Yes |
| `v2_pivot_range` | 7.163 s | Yes |

`BEST` is a copy of `v2_pivot_range`, the shortest valid recorded run. The
saved `.out` files match the original output (88 rows at SF=1). A later
original/BEST check measured 17.788 s versus 11.351 s and again returned
identical output. Timings vary with system load and cache state.

To rerun from this folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query11_v0_original.sql`, then
`source query11_BEST.sql`. The CSV and HTML contain saved measurements;
manual reruns do not overwrite them.
