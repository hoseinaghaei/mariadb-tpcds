# Scanning the unoptimized queries for structural defects

Twelve of the 40 tier-4/5 queries had no optimized version. This is what a
structural scan found, and which of them it correctly cleared.

> **Read the outcome table below before the method.** The scan's calls were
> later tested by rewriting all twelve regardless
> (`report/26-the-last-eleven.md`), and it cleared three queries that turned
> out to be improvable. The method section is kept because the method is
> still right for what it detects — it just does not detect everything.

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

| query | SF=4 | finding | scan's call | outcome |
|---|---:|---|---|---|
| **q68** | 20.8s | **full scan `store_sales`, 11,519,024 rows** | act | **4.9x** |
| **q46** | 12.5s | **same defect, same five tables** | act | **1.9x** |
| **q23** | 173.6s | **re-materialisation, 55,882 loops** | diagnosed, no fix | **3.60x** |
| **q70** | 13.7s | 365 loops, nothing large | no | **3.22x** |
| **q82** | 1.1s | 419,684 `item` lookups, but 1.1s total | no | **8.00x** |
| **q35** | — | index-only contribution, no query to substitute | n/a | **1.31x** |
| q66 | 14.5s | 365 loops, nothing large | no | 1.01x / 0.91x |
| q58 | 0.3s | trivial | no | 1.00x |
| q65 | 3.5s | small derived scan | no | 0.97x |
| q38 | — | index-only contribution, no query to substitute | n/a | 0.80x |
| q87 | 4.7s | scans are derived tables, not base | no | 0.80x |
| q71 | 6.2s | 823 loops on a derived table | no | 0.77x |
| q77 | 17.9s | six CTEs, each `loops=1`, time spread evenly | no | 0.73x |

## The scan under-predicted, and it is worth saying why

This page originally concluded "**only two of the twelve had anything
actionable**". All twelve were subsequently rewritten anyway
(`report/26-the-last-eleven.md`), and **six** turned out to be improvable —
q68, q46, q23, q70, q82 and q35 — including three the scan had explicitly
cleared.

The scan was not wrong about what it measured. It was looking for one kind of
defect: a node doing obviously too much work, visible as an oversized scan or
a loop count in the thousands. Three of the four misses were a different kind
of problem entirely, invisible to that test:

- **q70** — a subquery that filters nothing. Its loop counts are unremarkable
  because the second pass over `store_sales` is *legitimate work for a
  predicate that turns out to be a tautology*. Nothing in the plan says so;
  it takes reading the SQL and noticing that `group by s_state` followed by
  `partition by s_state` makes `rank()` constant.
- **q82** — a `GROUP BY` with no aggregate, i.e. a DISTINCT, building 3.6M
  intermediate rows to emit one. The scan saw 419,684 cheap lookups totalling
  1.1s and moved on. The waste was in the shape of the statement, not the
  cost of any node.
- **q35** — dismissed as "no query to substitute" because the contributed
  file held only `CREATE INDEX`. That is a fact about the *contribution*, not
  about the query, and it should never have ended the enquiry.

And q23 was marked "diagnosed, no fix" because the one obvious lever,
`split_materialized=off`, had measured +54.0s. The lever was wrong; the fix
was to make the re-materialised CTE cheap enough that the choice stopped
mattering.

**The lesson: a structural scan is a good way to find work that is too
expensive, and a poor way to find work that should not be happening at all.**
Reading the statement still matters.

q77 remains the one genuine "looked like a candidate, wasn't" — the scan
flagged `store` probed 240,716 times, and those are primary-key lookups
costing **0ms** in total. Its real problem is a non-covering index, which
needs DDL. A loop count alone is not a defect.

## What was fixed from this scan

The two the scan found. For the four found later by reading the statements —
q23 (3.60x), q70 (3.22x), q82 (8.00x), q35 (1.31x) — see
`report/26-the-last-eleven.md` and each query's own directory.

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
