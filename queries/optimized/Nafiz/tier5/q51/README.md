# Query 51 optimization

`v0_original` is untouched. `v1_union_pivot` replaces MariaDB's two-branch full-outer-join emulation with `UNION ALL` and one grouped pivot. `v2_union_range` separately adds the equivalent direct 12-month date-key range.

Run `..\run-tier5-optimizations.ps1` to create `.out` files, `benchmark-results.csv`, and `optimization-report.html`. `BEST` is generated only when output matches v0 exactly.
