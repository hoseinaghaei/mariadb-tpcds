# Query 31: local optimization experiment

Selected portable candidate: `query31_v2_pivot.sql`.

## Primary-key measurements

Linux, MariaDB 10.11.14, SF=1, data seed 10; three serial ordinary trials after exploratory warm-ups. Query cache disabled, buffer pool 2 GiB, temporary-table limits 16 MiB. These are local preliminary measurements, not final Mac or four-scale results.

| Variant | n | Median (s) | Min–max (s) | Speedup vs v0 |
| --- | ---: | ---: | ---: | ---: |
| v0 | 3 | 27.572 | 22.044–31.434 | 1.00× |
| v1 | 3 | 23.508 | 21.848–28.114 | 1.17× |
| v2 | 3 | 12.009 | 9.146–12.162 | 2.30× |

All recorded repetitions matched the complete saved original result exactly, including NULLs, row order, duplicate column names and result-set boundaries. Returned rows per result set: [44].

## Evidence and reproduction

See [the experiment guide](../../../experiments/README.md). Raw session: `experiments/local/takeover_20261014T180419Z/`; ordinary timings are separate from probes, fixtures and diagnostics. Re-run both versions after changing physical design, scale, settings or query parameters.

## Why this rewrite is valid

The original joins three quarter-specific copies of each channel's aggregate. On the primary-key design its actual plan scans store_sales three times and web_sales three times. `v2` computes each channel's three quarterly groups once and pivots them, leaving one fact-table scan per channel. The actual plans, rather than estimated row counts, support this observation.

All three original groups must exist. `HAVING COUNT(DISTINCT d_qoy)=3` preserves that requirement; absent quarters are not converted into zero totals. MAX selects an existing quarterly aggregate instead of summing it again and widening decimal precision. County/year joins, NULL county behavior, positive-denominator CASE guards, ratio comparisons and output ordering remain unchanged. The fixture includes duplicate addresses in one county, a missing quarter, NULL totals, a NULL county and a negative third-quarter total.

`v1` pushes year/quarter predicates earlier, but the original optimizer already pushes individual quarter filters into its derived results. Its three timings overlap the baseline substantially. Treat that small apparent gain cautiously; the pivot has a structural explanation and a much larger measured difference.

## Indexed measurements

All 117 reference indexes remained visible. Q39 has a separate final correction series under the same physical design; keep its baseline separate from the earlier v4 series.

| Series | Variant | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | --- | ---: | ---: | ---: | ---: |
| reference | v0 | 3 | 46.947 | 46.644–47.496 | 1.00× |
| reference | v2 | 3 | 15.957 | 15.908–15.959 | 2.94× |

`query31_BEST.sql` is an exact copy of the selected candidate, with the tested SQL hash. All indexed repetitions matched the saved original results. Revalidate the candidate at each scale and on the final machine.
