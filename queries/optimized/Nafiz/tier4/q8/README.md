# Query 8 optimization

- `v0_original`: original TPC-DS SQL.
- `v1_date_range`: adds only the equivalent 2000-Q2 date-key range.
- `BEST`: a copy of `v1_date_range`.

The original took 4.121 s in the saved benchmark; `v1` took 0.246 s.
A fresh run took 4.296 s versus 0.267 s. Both versions returned the same
**empty result** on this SF=1 dataset. The CSV and HTML report list the
original first and the faster version second.

Two further methods were tested but not kept: join reordering tied `v1` at
0.246 s, while a date-first `JOIN_PREFIX` hint took 0.255 s. Neither gave a
reliable improvement over `v1`. The removed files remain recoverable from
the earlier Git commit.

To rerun from this query folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query8_v0_original.sql`, then
`source query8_BEST.sql`. Manual reruns do not overwrite the CSV or HTML.
