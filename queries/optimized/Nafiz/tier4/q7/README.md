# Query 7 optimization

Versions are ordered from longest to shortest measured runtime.

- `v0_original`: untouched TPC-DS SQL.
- `v1_reordered`: date-first SQL table order, retaining the exact date range.
- `v2_date_range`: direct 1998 date-key range only.
- `v3_datefirst_hint`: date-first order plus a MariaDB join-prefix hint.

Every saved version returns byte-identical output. A date-dimension-removal attempt failed SQL validation and was deliberately not saved.
