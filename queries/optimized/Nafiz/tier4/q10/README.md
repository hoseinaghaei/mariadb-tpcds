# Query 10 optimization (Tier 4, SF=1)

- `v0_original`: original correlated `EXISTS` query, 4.892 s.
- `v1_nodatedim`: exact April-July 2001 date-key ranges and removal of
  redundant `date_dim` joins, 0.281 s.
- `v2_date_range`: the same exact ranges while retaining the `date_dim`
  joins, 0.284 s. This is an alternative to `v1`, not an additional change.
- `BEST`: copy of `v1_nodatedim`, the shortest valid recorded run.

All saved `.out` files match the original output. The 0.003 s difference
between `v1` and `v2` is small and may change on another run.

To rerun from this folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query10_v0_original.sql`, then
`source query10_BEST.sql`. Manual reruns do not overwrite the CSV or HTML.
