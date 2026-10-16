# TPC-DS Query 67: Optimization

## Overview

Query 67 calculates sales by product and store over a 12-month period, generates subtotals using `WITH ROLLUP`, ranks results within each product category and returns the first 100 rows.

## Optimization Approaches

### Version 1 — Pre-aggregation

* Computes the joins, sales aggregation and rollup once.
* Stores the results in `q67_rollup`.
* The main query ranks, filters and sorts the pre-aggregated rows.
* **Reported runtime:** ~3 seconds, excluding table creation and population.

### Version 2 — Runtime Optimization

* Uses explicit `JOIN` syntax.
* Finds the minimum and maximum date keys for the target period.
* Increases session sort-buffer and temporary-table limits.
* Performs the joins, aggregation and rollup during each execution.
* **Reported runtime:** ~7–8 seconds.

## Performance Comparison

| Version   | Reported runtime | Main technique                        |
| --------- | ---------------: | ------------------------------------- |
| Original  |      ~15 seconds | Direct aggregation                    |
| Version 1 |       ~3 seconds | Pre-aggregation                       |
| Version 2 |     ~7–8 seconds | Date-key filtering and session tuning |

## Correctness

Both optimized versions retain the ranking logic and `WITH ROLLUP`. Validate the output against the original query, including the rollup rows, data types and final ordering. Version 1 requires refreshing `q67_rollup` when source data changes.

*Note: Timings depend on the environment and whether preprocessing time is included.*
