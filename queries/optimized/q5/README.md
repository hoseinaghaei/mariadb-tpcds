# Query 5: local optimization experiment

Selected portable candidate: `query5_v1_branchfilters.sql`.

## Primary-key measurements

Linux, MariaDB 10.11.14, SF=1, data seed 10; three serial ordinary trials after exploratory warm-ups. Query cache disabled, buffer pool 2 GiB, temporary-table limits 16 MiB. These are local preliminary measurements, not final Mac or four-scale results.

| Variant | n | Median (s) | Min–max (s) | Speedup vs v0 |
| --- | ---: | ---: | ---: | ---: |
| v0 | 3 | 145.402 | 144.140–159.790 | 1.00× |
| v1 | 3 | 11.309 | 10.299–14.070 | 12.86× |

All recorded repetitions matched the complete saved original result exactly, including NULLs, row order, duplicate column names and result-set boundaries. Returned rows per result set: [100].

## Evidence and reproduction

See [the experiment guide](../../../experiments/README.md). Raw session: `experiments/local/takeover_20261014T180419Z/`; ordinary timings are separate from probes, fixtures and diagnostics. Re-run both versions after changing physical design, scale, settings or query parameters.

## Why this rewrite is valid

The date predicate moves into all six sales/returns UNION branches. The original outer date filters remain, so rows are removed earlier without broadening the result. This reduces the rows materialized before grouping, while retaining UNION ALL, the literal zero contributions, NULL behavior, dimension business-ID grouping and rollup totals.

The interval is inclusive: 28 August through 11 September 1998. Web returns are filtered by their return date, and their lookup into web_sales remains unrestricted by sale date. Filtering that lookup by the sale interval would lose legitimate returns from earlier sales. The synthetic test covers both endpoints, an older sale returned within the interval, unmatched returns, duplicate store business IDs, NULL measures and all rollup levels. Q5 also requires the runner's PIPES_AS_CONCAT mode because the baseline uses `||` for entity IDs.

## Indexed measurements

All 117 reference indexes remained visible. Q39 has a separate final correction series under the same physical design; keep its baseline separate from the earlier v4 series.

| Series | Variant | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | --- | ---: | ---: | ---: | ---: |
| reference | v0 | 3 | 112.735 | 112.385–113.031 | 1.00× |
| reference | v1 | 3 | 10.144 | 10.143–10.446 | 11.11× |

`query5_BEST.sql` is an exact copy of the selected candidate, with the tested SQL hash. All indexed repetitions matched the saved original results. Revalidate the candidate at each scale and on the final machine.
