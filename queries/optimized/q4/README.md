# Query 4: local optimization experiment

Selected portable candidate: `query4_v2_customerpivot.sql`.

## Primary-key measurements

Linux, MariaDB 10.11.14, SF=1, data seed 10; three serial ordinary trials after exploratory warm-ups. Query cache disabled, buffer pool 2 GiB, temporary-table limits 16 MiB. These are local preliminary measurements, not final Mac or four-scale results.

| Variant | n | Median (s) | Min–max (s) | Speedup vs v0 |
| --- | ---: | ---: | ---: | ---: |
| v0 | 3 | 99.778 | 75.753–104.080 | 1.00× |
| v2 | 3 | 16.942 | 11.656–16.978 | 5.89× |

All recorded repetitions matched the complete saved original result exactly, including NULLs, row order, duplicate column names and result-set boundaries. Returned rows per result set: [6].

## Evidence and reproduction

See [the experiment guide](../../../experiments/README.md). Raw session: `experiments/local/takeover_20261014T180419Z/`; ordinary timings are separate from probes, fixtures and diagnostics. Re-run both versions after changing physical design, scale, settings or query parameters.

## Why this rewrite is valid

The original materializes two yearly results per channel and carries several customer attributes through each grouping. `v2` computes the same monetary expression for 2001 and 2002 in one grouped scan per channel. It groups by the fact's customer surrogate key and joins customer details afterward. The plan contains three sales-table nodes instead of six.

This requires unique, non-NULL `customer.c_customer_id`. The identity check found 100,000 customers and 100,000 distinct IDs at this scale. Repeat that check for every new dataset. Both year groups must exist; `HAVING COUNT(DISTINCT d_year)=2` preserves that condition even when a year's total is NULL. The first-year positivity tests, guarded divisions, exact arithmetic, four output fields, ordering and LIMIT remain unchanged. The synthetic test includes a missing year, all-NULL measures, zero denominators, NULL customer attributes and orphan customers.

`v1` only adds year filters. Its initial probe is retained, but it did not receive three measured repetitions; do not treat its single timing as a robust result.

## Indexed measurements

All 117 reference indexes remained visible. Q39 has a separate final correction series under the same physical design; keep its baseline separate from the earlier v4 series.

| Series | Variant | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | --- | ---: | ---: | ---: | ---: |
| reference | v0 | 3 | 54.866 | 54.669–55.275 | 1.00× |
| reference | v2 | 3 | 15.209 | 15.208–15.307 | 3.61× |

`query4_BEST.sql` is an exact copy of the selected candidate, with the tested SQL hash. All indexed repetitions matched the saved original results. Revalidate the candidate at each scale and on the final machine.
