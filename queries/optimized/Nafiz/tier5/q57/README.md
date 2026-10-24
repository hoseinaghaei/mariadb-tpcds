# Query 57 optimization

`v0_original` is the unchanged TPC-DS query. `v1_window` replaces three
self-joins of the monthly aggregate with `LAG` and `LEAD`.
`v2_window_range` keeps the window rewrite and adds an equivalent direct
date-key range. `v3_datefirst` keeps both changes and adds a date-first
join-prefix hint.

| Version | Recorded time | Same output |
|---|---:|---|
| `v0_original` | 8.377 s | Reference |
| `v1_window` | 2.432 s | Yes |
| `v2_window_range` | 1.879 s | Yes |
| `v3_datefirst` | 1.8 s | Yes |

`BEST` is a copy of `v3_datefirst`, the shortest valid recorded run. All
saved `.out` files match the original output (100 rows at SF=1). A later
original/BEST check measured 8.379 s versus 1.969 s and again returned
identical output. Timings vary with system load and cache state.

To rerun from this folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query57_v0_original.sql`, then
`source query57_BEST.sql`. The CSV and HTML contain saved measurements;
manual reruns do not overwrite them.
