# Query 51: local optimization experiment

Selected portable candidate: `query51_v1_unifieddaily.sql`.

## Primary-key measurements

Linux, MariaDB 10.11.14, SF=1, data seed 10; three serial ordinary trials after exploratory warm-ups. Query cache disabled, buffer pool 2 GiB, temporary-table limits 16 MiB. These are local preliminary measurements, not final Mac or four-scale results.

| Variant | n | Median (s) | Min–max (s) | Speedup vs v0 |
| --- | ---: | ---: | ---: | ---: |
| v0 | 3 | 77.282 | 59.333–83.267 | 1.00× |
| v1 | 3 | 58.484 | 46.695–62.934 | 1.32× |

All recorded repetitions matched the complete saved original result exactly, including NULLs, row order, duplicate column names and result-set boundaries. Returned rows per result set: [100].

## Evidence and reproduction

See [the experiment guide](../../../experiments/README.md). Raw session: `experiments/local/takeover_20261014T180419Z/`; ordinary timings are separate from probes, fixtures and diagnostics. Re-run both versions after changing physical design, scale, settings or query parameters.

## Why this rewrite is valid

The baseline emulates FULL OUTER JOIN using two UNION branches, causing repeated materialization of the channel aggregates. `v1` creates each channel's daily aggregate once and combines the unique item/date keys before computing the windows.

Channel-presence flags are essential: a cumulative value computed on the combined calendar must be masked to NULL when that channel has no row on that date. The rewrite retains the original running SUM followed by running MAX; replacing MAX with the latest cumulative sum would change results when increments are negative. The fixture checks channel-only dates, multiple facts per day, all-NULL daily measures, a genuine zero after a NULL, negative increments, out-of-window facts and NULL item keys. It preserves the final six fields, comparison, order and LIMIT 100.

The primary-key timing ranges are broad. The 1.32x ratio of medians is preliminary evidence; do not describe it as a universal or precisely known gain. Window sorting and temporary-table work remain possible bottlenecks, and indexes can change the balance.

## Indexed measurements

All 117 reference indexes remained visible. Q39 has a separate final correction series under the same physical design; keep its baseline separate from the earlier v4 series.

| Series | Variant | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | --- | ---: | ---: | ---: | ---: |
| reference | v0 | 3 | 60.528 | 59.977–61.027 | 1.00× |
| reference | v1 | 3 | 48.549 | 47.593–50.957 | 1.25× |

`query51_BEST.sql` is an exact copy of the selected candidate, with the tested SQL hash. All indexed repetitions matched the saved original results. Revalidate the candidate at each scale and on the final machine.
