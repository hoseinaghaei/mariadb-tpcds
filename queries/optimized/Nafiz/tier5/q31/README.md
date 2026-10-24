# Query 31 optimization

`v0_original` is untouched. `v1_pivot` sums quarters 1–3 in one pass for each sales channel. `v2_pivot_range` separately tests an equivalent direct Q1-Q3 date-key range.

Run `..\run-tier5-optimizations.ps1` to create `.out` files, `benchmark-results.csv`, and `optimization-report.html`. `BEST` is generated only when output matches v0 exactly.
