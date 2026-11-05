# Four scale factors, twice — 2026-11-04

Raw artifacts for the re-measurement reported in
[report 25](../../../report/25-query-by-query.md). Eight runs: the 40
tier-4/5 queries at SF=1, 2, 4 and 8, each scale measured twice.

**Why these exist.** Until now no run artifacts from this line of work had
been committed — `/results/` is in `.gitignore`, so every figure reported
was unverifiable by anyone else, which is why
`report/submission_evidence.json` graded the previous four-scale table
`UNVERIFIED_TABLE_NOT_USED` with `raw_run_artifacts_available: false`. These
bundles close that gap for this campaign.

## Configuration

Identical across all eight runs, asserted by the harness before each:

| | |
|---|---|
| data | `dsdgen -RNGSEED 10` |
| page size | 32 KiB |
| buffer pool | 8 GiB |
| `innodb_stats_persistent_sample_pages` | 160 |
| secondary indexes | **95** — `index set matches sql/ exactly` verified per run |
| query set | `queries/tuned/` (40 tier-4/5) |
| `OPTIMIZE TABLE` | not used |

## Method

Two **separated** passes over all four scales — 1, 2, 4, 8 then 1, 2, 4, 8 —
rather than two adjacent runs per scale. Adjacent runs share buffer-pool
state and agree with each other, which would produce a flattering error bar;
separating them by a full sweep is what makes the spread an honest measure
of drift.

## Totals

| scale | pass a | pass b | best | spread |
|---|---:|---:|---:|---:|
| SF=1 | 141.9s | 139.8s | **139.8s** | +1.5% |
| SF=2 | 291.2s | 339.6s | **291.2s** | +16.6% |
| SF=4 | 741.2s | 793.1s | **741.2s** | +7.0% |
| SF=8 | 2736.2s | 2692.2s | **2692.2s** | +1.6% |

40/40 queries and **zero errors** in every run.

**The worst spread, 16.6%, is the resolution limit of this benchmark.** Any
cross-run difference smaller than that is not something these measurements
can settle. Eleven query/scale pairs disagree between their two runs by 1.5x
or more; they are listed in report 25 and should be distrusted individually.

## Not comparable to the 2026-10-29 campaign

The same configuration measured **81.8s** at SF=1 on 29 October and 139.8s
here. The host was 50 days up with swap at 10.1 of 11.3 GiB. All eight runs
in this bundle are one session and are comparable to each other, which is
what report 25 presents; they should not be divided against figures from any
other session.

## q70

The one query that moved for a reason rather than for drift. The NULL-rollup
correction (commit `2146dad`, with q36 and q86) is correct — the TPC-DS idiom
`(s_state is null)+(s_county is null)` cannot distinguish a `ROLLUP` NULL
from a NULL in the data — and it costs 3–6x:

| | before | after |
|---|---:|---:|
| SF=1 | 0.7s | 3.4s |
| SF=2 | 1.4s | 8.0s |
| SF=4 | 5.7s | 16.9s |
| SF=8 | 40.0s | **239.8s** |

At SF=8 that takes q70 from the eleventh slowest query to the second.

## Contents

| file | |
|---|---|
| `r2-sf<N>-<a\|b>.zip` | one run: per-query JSON with answers, `tuned.log`, `index-usage-sf<N>.tsv` |
| `measurements.csv` | every query, both runs, all four scales, plus the best of each pair |
| `summary.json` | configuration and per-scale totals with spread |
| `SHA256SUMS` | checksums for everything above |

Verify with `shasum -a 256 -c SHA256SUMS`.
