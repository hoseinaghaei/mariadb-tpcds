# Query 57 optimization

`v0_original` is the untouched TPC-DS query. `v1_window` replaces three self-joins of the monthly aggregate with `LAG` and `LEAD`. `v2_window_range` adds an equivalent direct date-key range. `v3_datefirst` additionally tests a date-first join prefix.

Run `..\run-tier5-optimizations.ps1` to create `.out` files, `benchmark-results.csv`, and `optimization-report.html`. `BEST` is generated only when output matches v0 exactly.
