# Query 7 optimization (Tier 4, SF=1)

The CSV and HTML are ordered from longest to shortest recorded runtime.

- `v0_original`: untouched TPC-DS SQL, 3.784 s.
- `v1_reordered`: exact 1998 date-key range and date-first SQL order, 1.455 s.
- `v2_date_range`: exact date-key range with original table order, 1.252 s.
- `v3_datefirst_hint`: range and date-first order with `JOIN_PREFIX`, 1.176 s.
- `BEST`: copy of `v3_datefirst_hint`.

Every saved `.out` file matches the original output. A date-dimension-removal
attempt failed SQL validation and was deliberately not saved.

To rerun from this folder in PowerShell, start MariaDB with
`& 'C:\Program Files\MariaDB 13.0\bin\mariadb.exe' --skip-ssl -u root -p tpcds`.
At its prompt enter `source query7_v0_original.sql`, then
`source query7_BEST.sql`. Manual reruns do not overwrite the CSV or HTML.
