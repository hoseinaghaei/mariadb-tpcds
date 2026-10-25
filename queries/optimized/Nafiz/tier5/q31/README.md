# Query 31 optimization

`v0_original` is the unchanged supplied SQL. `v1_pivot` sums quarters
1–3 in one pass for each sales channel. `v2_pivot_range` keeps that pivot
and adds an equivalent direct Q1–Q3 date-key range.

| Version | Recorded time | Same output |
|---|---:|---|
| `v0_original` | 15.54 s | Reference |
| `v1_pivot` | 5.417 s | Yes |
| `v2_pivot_range` | 0.82 s | Yes |

`BEST` is a copy of `v2_pivot_range`, the shortest valid recorded run. All
saved `.out` files match the original output (56 rows at SF=1). A later
original/BEST check measured 17.397 s versus 0.865 s and again returned
identical output. Timings vary with system load and cache state.

To rerun from this folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query31_v0_original.sql`, then
`source query31_BEST.sql`. The CSV and HTML contain saved measurements;
manual reruns do not overwrite them.
