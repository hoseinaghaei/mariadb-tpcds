# Query 51 optimization

`v0_original` is the unchanged supplied SQL. `v1_union_pivot` replaces
MariaDB's two-branch full-outer-join emulation with `UNION ALL` and one
grouped pivot. `v2_union_range` keeps that rewrite and adds the equivalent
direct 12-month date-key range.

| Version | Recorded time | Same output |
|---|---:|---|
| `v0_original` | 26.671 s | Reference |
| `v1_union_pivot` | 17.477 s | Yes |
| `v2_union_range` | 16.887 s | Yes |

`BEST` is a copy of `v2_union_range`, the shortest valid recorded run. All
saved `.out` files match the original output (100 rows at SF=1). A later
original/BEST check measured 26.511 s versus 17.460 s and again returned
identical output. The difference between `v1` and `v2` is modest, so rerun
timings may vary.

To rerun from this folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query51_v0_original.sql`, then
`source query51_BEST.sql`. The CSV and HTML contain saved measurements;
manual reruns do not overwrite them.
