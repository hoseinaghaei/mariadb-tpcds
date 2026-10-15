# Query 39: local optimization experiment

Selected candidate: `query39_v6_sourcefirst.sql` (the indexed correction). The primary-key table below predates v6; v4 was the selected independent-statement candidate in that phase.

## Primary-key measurements

Linux, MariaDB 10.11.14, SF=1, data seed 10; three serial ordinary trials after exploratory warm-ups. Query cache disabled, buffer pool 2 GiB, temporary-table limits 16 MiB. These are local preliminary measurements, not final Mac or four-scale results.

| Variant | n | Median (s) | Min–max (s) | Speedup vs v0 |
| --- | ---: | ---: | ---: | ---: |
| v0 | 3 | 3.280 | 3.177–3.479 | 1.00× |
| v1 | 3 | 3.226 | 3.176–3.229 | 1.02× |
| v2 | 3 | 3.881 | 3.878–3.881 | 0.85× |
| v3 | 3 | 0.769 | 0.768–0.818 | 4.27× |
| v4 | 3 | 0.818 | 0.817–0.917 | 4.01× |

All recorded repetitions matched the complete saved original result exactly, including NULLs, row order, duplicate column names and result-set boundaries. Returned rows per result set: [141, 2].

## Evidence and reproduction

See [the experiment guide](../../../experiments/README.md). Raw session: `experiments/local/takeover_20261014T180419Z/`; ordinary timings are separate from probes, fixtures and diagnostics. Re-run both versions after changing physical design, scale, settings or query parameters.

## Why this rewrite is valid

The coefficient of variation is STDDEV_SAMP(quantity) / AVG(quantity); it is not covariance. The original looks up item and warehouse details for individual inventory observations before grouping. The late-join variants group by inventory item/warehouse keys and month first, then retain both inner dimension joins. Dimension primary keys make those lookups one-to-one, and orphan groups still disappear.

The actual primary-key plan for the first original SELECT performs 405,000 item lookups across April and May. The combined aggregation used by `v3` performs 5,235 item lookups after filtering grouped coefficients. Both dimensions remain part of the query, and warehouse names need not be unique. Means, sample standard deviations, coefficient thresholds, two outputs, repeated column names and ordering are preserved.

`v1` adds month filters; the baseline already receives useful month predicate pushdown and this made little difference. `v2` shares a temporary table but retains early dimension lookups and is slower. `v3` combines late lookups with shared temporary results and is fast, but assumes unchanged data between outputs. `v4` was the initial general candidate: it keeps the original independent SELECT statements and needs no temporary table. Its three additional primary-key trials were run after the main series, rather than as an alternating pair with the original; use the indexed alternating rounds and final-machine reruns to strengthen the comparison.

The fixture checks missing months, zero/NULL means, a single observation, both coefficient thresholds, duplicate warehouse names with distinct keys and orphan facts. Do not replace STDDEV_SAMP with STDDEV_POP.

## Indexed measurements

All 117 reference indexes remained visible. Q39 has a separate final correction series under the same physical design; keep its baseline separate from the earlier v4 series.

| Series | Variant | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | --- | ---: | ---: | ---: | ---: |
| reference | v0 | 3 | 80.035 | 79.887–84.667 | 1.00× |
| reference | v4 | 3 | 44.234 | 43.781–50.320 | 1.81× |
| reference_q39_final | v0 | 3 | 81.236 | 81.092–83.618 | 1.00× |
| reference_q39_final | v5 | 3 | 0.867 | 0.817–0.867 | 93.72× |
| reference_q39_final | v6 | 3 | 0.817 | 0.816–0.817 | 99.44× |

`query39_BEST.sql` is an exact copy of the selected candidate, with the tested SQL hash. All indexed repetitions matched the saved original results. Revalidate the candidate at each scale and on the final machine.

The indexed v4 plan allows warehouse/item-driven lateral evaluation of the grouped inventory results and chooses `idx_inv_warehouse_sk` and `idx_inv_item_sk`. These filters reach the narrow date condition late. `v5` retains late dimension joins and adds `FORCE INDEX (PRIMARY)` to inventory; `v6` instead uses `STRAIGHT_JOIN` to keep the grouped source before item and warehouse. The v6 plan uses date_dim then inventory PRIMARY by inv_date_sk, with no lateral materializations. Both fixes pass the full output comparison and nonempty fixtures. The final three-round series compares both fixes to fresh original runs. Source-first v6 is selected without hardcoding an index name.
