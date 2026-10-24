# Query 11 optimization

`v0_original` is untouched. `v1_pivot` aggregates only 2001 and 2002, then pivots the four required store/web totals per customer. `v2_pivot_range` separately tests direct source date-key ranges.

Run `..\run-tier5-optimizations.ps1` to create `.out` files, `benchmark-results.csv`, and `optimization-report.html`. `BEST` is generated only when output matches v0 exactly.
