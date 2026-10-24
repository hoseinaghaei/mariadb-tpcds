# Query 74 optimization

`v0_original` is untouched. `v1_pivot` calculates the store/web yearly totals once and pivots the four required values per customer. `v2_pivot_range` additionally tests direct 1999-2000 date-key ranges. It returned the same output, but v1 was slower in the first SF=1 measurement; therefore `BEST` is selected by the runner from measured results.

Run `..\run-tier5-optimizations.ps1` to create `.out` files, `benchmark-results.csv`, and `optimization-report.html`. `BEST` is generated only when output matches v0 exactly.
