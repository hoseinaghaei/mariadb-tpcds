# Scanning the unoptimized queries for structural defects

Twelve of the 40 tier-4/5 queries had no optimized version. This is what a
structural scan found, and why most of them were left alone.

## Method, and why not timing

`ANALYZE FORMAT=JSON` on each query, looking for:

- nodes with `r_loops` in the thousands (repeated materialisation)
- full scans over large base tables
- where the time actually concentrates

**Loop counts and row counts are deterministic.** A node executing 55,882
times is a finding regardless of how noisy the clock is. Timing on this host
is not: q23 measured 171.5–198s across four identical runs, and a rewrite of
it measured 162.9–240s. Nothing under about 30% is resolvable on a long query
here.

So the scan came first, and a rewrite was only written where there was a
concrete defect to fix. Five minutes of scanning replaced what would
otherwise have been hours of inconclusive measurement.

## Findings

| query | SF=4 | finding | acted on |
|---|---:|---|---|
| **q68** | 20.8s | **full scan `store_sales`, 11,519,024 rows** | **yes — 4.9x** |
| **q46** | 12.5s | **same defect, same five tables** | **yes — 1.9x** |
| q77 | 17.9s | six CTEs, each `loops=1`, time spread evenly | no |
| q66 | 14.5s | 365 loops, nothing large | no |
| q70 | 13.7s | 365 loops, nothing large | no |
| q71 | 6.2s | 823 loops on a derived table | no |
| q87 | 4.7s | scans are derived tables, not base | no |
| q65 | 3.5s | small derived scan | no |
| q82 | 1.1s | 419,684 `item` lookups, but 1.1s total | no |
| q58 | 0.3s | trivial | no |
| q23 | 173.6s | re-materialisation, 55,882 loops | **diagnosed, no fix** |
| q35, q38 | — | index-only contributions, no query to substitute | n/a |

**Only two of the twelve had anything actionable.** Seven are doing the work
they describe — six aggregations, a few hundred loops, no oversized scan —
and rewriting them would be inventing problems.

q77 deserves a note because it looked like a candidate: the scan flagged
`store` probed 240,716 times. Those are primary-key lookups costing **0ms**
in total. Its 17.9s is six fact-table aggregations over a 31-day window, each
materialised once. A loop count alone is not a defect.

q23 is the opposite case — a real defect with no reachable fix. See
`../q23-sf4/README.md`.

## What was fixed

q68 and q46 both read all 11.5M rows of `store_sales` and discarded nearly
all of it. `STRAIGHT_JOIN` from `date_dim` resolves the dates first and
reaches the fact table through `idx_ss_sold_date_sk`.

The gains differ by selectivity, which was predicted before measuring:

| | predicate | dates | gain |
|---|---|---:|---:|
| q68 | `d_dom between 1 and 2`, three years | 1.6% | **4.9x** |
| q46 | `d_dow in (6,0)`, three years | 28% | **1.9x** |

The gain comes from the predicate being selective, not from `STRAIGHT_JOIN`.

## Reproducing

```bash
queries/optimized/unoptimized-scan/analyze-all.sh [query ...]
```

Defaults to the ten scanned here. Prints, per query, the hot node, any node
with more than 100 loops, and full scans over 100k rows.
