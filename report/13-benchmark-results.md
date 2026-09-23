# Step 13 — Benchmark results: baseline vs. indexed

> **NOT COMPARABLE TO TPC BENCHMARK RESULTS.** These measurements were not
> audited, were taken at scale factor 1 (a qualification-only size), and do not
> meet the requirements of any official TPC Benchmark Standard. Published under
> clause 4.c(3) of the TPC End User License Agreement.

Two full runs of all 99 queries against the SF=1 database, same queries, same
server, same session settings. The only difference is the 117 indexes from
[step 11](11-reference-repo.md).

**Zero SQL errors in either run.** All 99 queries execute on MariaDB 13.0.2.

## Headline

| Set | Base (no indexes) | Indexed | Speedup |
|---|---:|---:|---:|
| **All 99 queries** | 6418.7s | 3119.8s | **2.06x** |
| **Repo subset (83 queries)** | 5389.3s | 2691.6s | **2.00x** |
| The 16 the repo excluded | 1029.4s | 428.2s | 2.40x |

The all-99 figure and the repo-subset figure land within 3% of each other
(2.06x vs 2.00x) — as expected, since the index set is identical and only the
query population differs.

Excluding the two capped queries, the 97 that ran to completion in both
configurations went **3100.7s -> 1820.8s, a 1.70x speedup**.

### A note on comparing to the repo

`tpcds-run-tool` publishes **no timing data** — only the harness and the
`my_tpcds_result` table definition; `git log` shows no committed results. There
is no external number to compare against. What is reproduced here is its
*configuration*: its 117 indexes, and its 83-query subset measured separately.

## It is not a uniform win

| | Count |
|---|---:|
| Faster by >10% | 68 |
| **Slower by >10%** | **19** |
| Within 10% | 10 |

- Time won by the improvements: **1970.2s**
- Time lost to regressions: **690.1s**
- Net: **1280.1s**

**Roughly a quarter of the gain is given back by regressions.** Anyone
continuing this work should start there — see below.

## Biggest wins

| Query | Base | Indexed | Speedup |
|---|---:|---:|---|
| **95** | 2059.0s *(capped)* | **1.0s** | **>2000x** |
| 54 | 92.3s | 7.4s | 12.5x |
| 51 | 440.6s | 37.8s | 11.7x |
| 78 | 364.9s | 45.3s | 8.1x |
| 47 | 235.2s | 32.6s | 7.2x |
| 2 | 237.6s | 51.4s | 4.6x |
| 4 | 175.4s | 58.5s | 3.0x |
| 5 | 181.4s | 87.5s | 2.1x |

**query95 is the whole story of why indexes matter here.** It is a `web_sales`
self-join on `ws_order_number`. Without an index that join is quadratic: it was
killed after **34 minutes without completing**, so 2059s is a lower bound, not
a measurement. With `idx_ws_order_number` it runs in **1.0 second**.

Note that queries 51 and 54 are both on the repo's excluded list — 51 because
of `FULL OUTER JOIN`. The emulation from [step 10](10-adapt-queries.md) not
only runs, it benefits normally from indexing.

## Regressions — the open problem

| Query | Base | Indexed | Time lost |
|---|---:|---:|---:|
| **39** | 1.6s | **193.6s** | +192.0s |
| **31** | 33.5s | **143.1s** | +109.6s |
| **21** | 0.5s | **59.8s** | +59.3s |
| 22 | 15.3s | 70.5s | +55.2s |
| 8 | 9.4s | 51.9s | +42.5s |
| 88 | 48.2s | 83.9s | +35.7s |
| 68 | 9.3s | 44.3s | +35.0s |
| 46 | 8.8s | 42.8s | +34.0s |
| 35 | 14.9s | 44.4s | +29.5s |
| 79 | 7.7s | 31.0s | +23.3s |

query39 at **121x slower** and query21 at **120x slower** are not noise. These
are cases where the optimizer sees a newly available index, estimates it will
be selective, and chooses an index-driven nested loop where a full scan with a
hash join was far cheaper. `ANALYZE TABLE` was run on all seven fact tables
after index creation, so this is not stale statistics.

**This is the obvious next piece of work.** Concretely: `EXPLAIN` each of the 19
regressed queries in both configurations, identify which index the optimizer
switched to, and decide per case whether to drop that index, add an
`IGNORE INDEX` hint, or adjust `optimizer_switch`. The 117-index set is
inherited wholesale from the reference repo and has not been tuned — it is a
starting point, not a finished configuration.

## Correctness was preserved

**Every non-capped query returned exactly the same number of rows in both
runs.** Indexes changed timing, never results — which is the necessary check
before trusting any of the numbers above.

## Two capped queries

| Query | What happened |
|---|---|
| **95** (base) | killed after 2059s without completing. No index on `ws_order_number`; quadratic self-join. Indexed: 1.0s. |
| **72** (indexed) | killed after 1298s without completing. Baseline recorded 1259s, but *that* run was contaminated (see below), so the true baseline is lower and this is very likely a regression. |

Both are recorded in their JSON as `TIMEOUT_CAPPED` with the elapsed time as an
explicit lower bound, and both are excluded from the 97-query clean total.

## Measurement caveats — read before quoting these numbers

1. **The baseline run had concurrency contamination.** Subagents dispatched to
   run query batches left orphaned runner loops behind when stopped, and for a
   period queries 72, 73 and 74 were each executing **twice simultaneously**
   against the same server. Those timings are inflated. query72's 1259s
   baseline is the clearest casualty. The duplicates were found and killed, but
   the affected baseline numbers were not re-measured.
2. **The baseline ran with up to 5 concurrent queries; the indexed run was
   largely serial.** Part of the measured 2.06x is reduced contention, not
   indexing. The per-query speedups for the big wins (95, 51, 78, 47) are large
   enough that this does not change the conclusion, but the aggregate ratio is
   optimistic.
3. **`innodb_buffer_pool_size` is 128 MB** against a 3.2 GB database — under
   4%. Every run is I/O bound. A realistic buffer pool would change both
   columns, probably not equally.
4. Single run per configuration, no warm-up, no repetition. These are
   indicative, not statistically sound.

A clean re-measurement — strictly serial, no subagents, larger buffer pool,
three runs taking the median — is worth doing before using these numbers for
anything beyond direction.

## Per-query results

`x` in the second column marks a query the reference repo excludes.
`!` marks a regression; `*` marks a capped query.

| Q | repo excl. | Base (s) | Indexed (s) | Speedup |
|---|---|---:|---:|---|
| 1 |  | 2.0 | 1.6 | 1.25x  |
| 2 |  | 237.6 | 51.4 | 4.62x  |
| 3 |  | 0.1 | 0.1 | 1.00x  |
| 4 |  | 175.4 | 58.5 | 3.00x  |
| 5 | x | 181.4 | 87.5 | 2.07x  |
| 6 |  | 2.7 | 2.1 | 1.29x  |
| 7 |  | 44.8 | 36.1 | 1.24x  |
| 8 | x | 9.4 | 51.9 | 0.18x ! |
| 9 |  | 19.0 | 6.1 | 3.11x  |
| 10 |  | 22.8 | 43.9 | 0.52x ! |
| 11 |  | 67.6 | 26.3 | 2.57x  |
| 12 |  | 0.6 | 0.4 | 1.50x  |
| 13 |  | 2.6 | 12.6 | 0.21x ! |
| 14 | x | 133.0 | 83.3 | 1.60x  |
| 15 |  | 5.4 | 21.4 | 0.25x ! |
| 16 |  | 27.5 | 0.9 | 30.56x  |
| 17 |  | 3.1 | 2.8 | 1.11x  |
| 18 | x | 22.1 | 2.9 | 7.62x  |
| 19 |  | 0.2 | 0.1 | 2.00x  |
| 20 |  | 0.7 | 0.6 | 1.17x  |
| 21 |  | 0.5 | 59.8 | 0.01x ! |
| 22 | x | 15.3 | 70.5 | 0.22x ! |
| 23 |  | 267.9 | 173.0 | 1.55x  |
| 24 |  | 18.6 | 0.2 | 93.00x  |
| 25 |  | 8.5 | 8.4 | 1.01x  |
| 26 |  | 20.2 | 16.0 | 1.26x  |
| 27 | x | 35.7 | 31.5 | 1.13x  |
| 28 |  | 35.4 | 0.4 | 88.50x  |
| 29 |  | 5.4 | 8.3 | 0.65x ! |
| 30 |  | 0.6 | 0.5 | 1.20x  |
| 31 |  | 33.5 | 143.1 | 0.23x ! |
| 32 |  | 0.1 | 0.1 | 1.00x  |
| 33 |  | 11.1 | 5.1 | 2.18x  |
| 34 |  | 7.7 | 6.9 | 1.12x  |
| 35 |  | 14.9 | 44.4 | 0.34x ! |
| 36 | x | 8.2 | 3.7 | 2.22x  |
| 37 |  | 9.6 | 8.4 | 1.14x  |
| 38 | x | 14.6 | 7.3 | 2.00x  |
| 39 |  | 1.6 | 193.6 | 0.01x ! |
| 40 |  | 0.4 | 0.4 | 1.00x  |
| 41 |  | 0.7 | 0.5 | 1.40x  |
| 42 |  | 0.2 | 0.2 | 1.00x  |
| 43 |  | 8.6 | 6.9 | 1.25x  |
| 44 |  | 17.8 | 2.9 | 6.14x  |
| 45 |  | 5.4 | 2.2 | 2.45x  |
| 46 |  | 8.8 | 42.8 | 0.21x ! |
| 47 |  | 235.2 | 32.6 | 7.21x  |
| 48 |  | 8.2 | 14.6 | 0.56x ! |
| 49 |  | 1.5 | 1.5 | 1.00x  |
| 50 |  | 2.2 | 1.1 | 2.00x  |
| 51 | x | 440.6 | 37.8 | 11.66x  |
| 52 |  | 0.2 | 0.1 | 2.00x  |
| 53 |  | 0.2 | 0.2 | 1.00x  |
| 54 | x | 92.3 | 7.4 | 12.47x  |
| 55 |  | 0.1 | 0.1 | 1.00x  |
| 56 |  | 1.1 | 0.4 | 2.75x  |
| 57 |  | 36.5 | 13.8 | 2.64x  |
| 58 |  | 14.3 | 6.0 | 2.38x  |
| 59 |  | 17.8 | 8.1 | 2.20x  |
| 60 |  | 5.1 | 1.3 | 3.92x  |
| 61 |  | 1.0 | 0.5 | 2.00x  |
| 62 |  | 7.3 | 7.9 | 0.92x  |
| 63 |  | 0.5 | 0.2 | 2.50x  |
| 64 |  | 20.6 | 1.3 | 15.85x  |
| 65 |  | 23.6 | 5.9 | 4.00x  |
| 66 |  | 6.9 | 4.3 | 1.60x  |
| 67 |  | 20.7 | 8.1 | 2.56x  |
| 68 |  | 9.3 | 44.3 | 0.21x ! |
| 69 |  | 12.5 | 7.8 | 1.60x  |
| 70 | x | 15.3 | 7.2 | 2.12x  |
| 71 |  | 11.6 | 5.4 | 2.15x  |
| 72 |  | 1259.0 | 1298.0 |  * |
| 73 |  | 10.6 | 15.2 | 0.70x ! |
| 74 |  | 38.7 | 24.6 | 1.57x  |
| 75 |  | 3.5 | 2.3 | 1.52x  |
| 76 |  | 12.1 | 1.2 | 10.08x  |
| 77 | x | 14.7 | 17.8 | 0.83x ! |
| 78 |  | 364.9 | 45.3 | 8.06x  |
| 79 |  | 7.7 | 31.0 | 0.25x ! |
| 80 | x | 1.8 | 0.8 | 2.25x  |
| 81 |  | 0.8 | 0.4 | 2.00x  |
| 82 |  | 10.3 | 9.0 | 1.14x  |
| 83 |  | 2.4 | 1.7 | 1.41x  |
| 84 |  | 13.0 | 0.4 | 32.50x  |
| 85 |  | 3.3 | 1.3 | 2.54x  |
| 86 | x | 3.1 | 2.1 | 1.48x  |
| 87 | x | 15.4 | 7.1 | 2.17x  |
| 88 |  | 48.2 | 83.9 | 0.57x ! |
| 89 |  | 0.6 | 0.4 | 1.50x  |
| 90 |  | 9.0 | 0.5 | 18.00x  |
| 91 |  | 0.4 | 1.6 | 0.25x ! |
| 92 |  | 0.2 | 0.0 | -  |
| 93 |  | 2.7 | 0.5 | 5.40x  |
| 94 |  | 3.1 | 1.0 | 3.10x  |
| 95 |  | 2059.0 | 1.0 |  * |
| 96 |  | 9.1 | 4.8 | 1.90x  |
| 97 | x | 26.5 | 9.4 | 2.82x  |
| 98 |  | 1.7 | 1.3 | 1.31x  |
| 99 |  | 3.0 | 11.7 | 0.26x ! |

Raw results: `queries/results/base/` and `queries/results/indexed/`, one JSON
and one `.out` per query. Regenerate this comparison with
`python3 queries/compare.py`.
