# Step 13 — Benchmark results

> **NOT COMPARABLE TO TPC BENCHMARK RESULTS.** Unaudited, scale factor 1 (a
> qualification-only size), not meeting any official TPC Benchmark Standard.
> Published under clause 4.c(3) of the TPC End User License Agreement.

All earlier measurements in this project have been **discarded**. They mixed
three variables at once — buffer pool size, dataset seed, and run concurrency —
and are not recoverable as clean data. Everything below comes from a single
controlled pair of runs.

## Configuration

Matched to the reference implementation
[`spetrunia/tpcds-run-tool`](https://github.com/spetrunia/tpcds-run-tool), whose
`setup-mariadb-current.sh` contains exactly one performance setting.

| | Value | Source |
|---|---|---|
| Scale factor | 1 | `01-generate-dataset.sh:34` |
| **Dataset seed** | **`-rngseed 10`** | `01-generate-dataset.sh:34` |
| **Query seed** | **`-rngseed 10`** | `10-prepare-queries.sh` |
| **`innodb_buffer_pool_size`** | **8G** | `setup-mariadb-current.sh:71` |
| `max_statement_time` | 300s | **ours** — a guard, not in the repo |
| Server | MariaDB 13.0.2, restarted before the runs so all counters start at zero |
| Execution | **strictly serial**, one query at a time, quiet machine |

Both runs used the identical dataset. The only difference between them is the
117 indexes from `sql/05_indexes.sql`.

### Why the seed matters

`-rngseed` changes the generated data, not just its ordering. Verified
directly — with seed 10 versus the default, `item`, `customer_address` and
`store` all differ byte-for-byte, and the fact tables even differ in
cardinality:

| Table | Default seed | Seed 10 |
|---|---:|---:|
| `store_sales` | 2,880,404 | **2,879,152** |
| `catalog_sales` | 1,441,548 | **1,441,837** |
| `web_sales` | 719,384 | **720,378** |

The published SF=1 reference cardinalities correspond to the **default** seed,
so under the repo's configuration the TPC answer sets cannot match by
construction. The repo never compares against them — its harness only records
`query_time_ms`.

## Headline: the indexes buy almost nothing

| Set | Base | Indexed | Speedup |
|---|---:|---:|---:|
| All 99 (incl. capped) | 1877.0s | 1563.0s | 1.20x |
| **97 queries that completed in both** | **1276.8s** | **1262.8s** | **1.01x** |
| Repo's 83-query subset | 1437.8s | 1151.1s | 1.25x |

**With an adequate buffer pool, 117 indexes deliver a 1% aggregate
improvement.** 25 queries got faster, 18 got slower, and 54 were unchanged.
Time won: 188.4s. Time lost: 154.2s. **Net: 34.2s across 97 queries.**

The all-99 figure of 1.20x is carried almost entirely by one query — see below.

This is the single most important correction to the earlier work. A previous
run reported "2.06x", but that was measured against a **128 MB** buffer pool —
4% of the database. Most of that apparent gain was the indexes compensating
for a memory shortage, not adding value.

## The one enormous win

| Query | Base | Indexed |
|---|---:|---:|
| **95** | **300.1s (killed at the cap)** | **0.1s** |

Query 95 is a `web_sales` self-join on `ws_order_number`. Without an index the
join is quadratic and it never completes. With `idx_ws_order_number` it returns
in a tenth of a second. It alone accounts for essentially the whole all-99
speedup.

Other genuine wins: query 16 (20.3s -> 0.2s), query 84 (10.3s -> 0.1s),
query 54 (47.6s -> 10.9s), query 28 (4.7s -> 0.5s), query 23 (222.2s -> 139.0s).

## 18 queries got slower

| Query | Base | Indexed | Factor | Lost |
|---|---:|---:|---:|---:|
| **39** | 1.7s | **92.5s** | **54.4x** | +90.8s |
| **21** | 0.4s | **23.7s** | **59.2x** | +23.3s |
| 31 | 14.8s | 26.0s | 1.8x | +11.2s |
| 22 | 12.0s | 19.8s | 1.7x | +7.8s |
| 68 | 4.5s | 8.3s | 1.8x | +3.8s |
| 46 | 5.1s | 8.5s | 1.7x | +3.4s |
| 74 | 21.6s | 24.1s | 1.1x | +2.5s |
| 66 | 3.4s | 5.8s | 1.7x | +2.4s |
| 10, 8, 35, 77, 70, 99, 62, 91, 53, 63 | | | 1.1–1.5x | +7.9s total |

Queries 39 and 21 account for **74% of all time lost**.

## Root cause, confirmed by experiment

`EXPLAIN` on the four worst:

```
query39  ->  inventory.idx_inv_warehouse_sk
query21  ->  inventory.idx_inv_warehouse_sk
query22  ->  inventory.idx_inv_item_sk
query31  ->  store_sales.idx_ss_addr_sk        <- different index
```

Making the three `inventory` indexes `IGNORED` and re-running.

This was re-measured as a **controlled three-pass test** — visible, ignored,
visible again — so that a single anomalous reading could not be mistaken for a
finding (as happened in [step 17](17-unused-indexes-are-not-safe-to-drop.md)):

| Query | Base | A: visible | **B: inventory ignored** | C: visible again |
|---|---:|---:|---:|---:|
| **39** | 1.7s | 58.3s | **1.1s** | 58.9s |
| **21** | 0.4s | 14.3s | **0.2s** | 14.5s |
| **22** | 12.0s | 14.3s | **7.5s** | 12.9s |
| 31 | 14.8s | 18.1s | 17.6s | 17.8s |

**A and C agree closely** (within 1–10%), and B is dramatically different for
39, 21 and 22. The effect is the indexes, not drift.

Queries 39 and 21 return to their pre-index baselines; query 22 ends up
*faster* than its baseline. Query 31 is unchanged across all three passes —
correctly predicted, since its plan uses `store_sales.idx_ss_addr_sk` rather
than an inventory index. That the experiment discriminates between the two is
what makes the diagnosis credible rather than coincidental.

### These absolute numbers drifted from the main run

The A/C readings above are **1.45–1.65x faster** than the same queries in the
indexed run tabulated earlier in this document:

| Query | indexed run | A/C re-measure | ratio |
|---|---:|---:|---:|
| 39 | 92.5s | 58.3 / 58.9s | 1.58x |
| 21 | 23.7s | 14.3 / 14.5s | 1.65x |
| 22 | 19.8s | 14.3 / 12.9s | 1.46x |
| 31 | 26.0s | 18.1 / 17.8s | 1.45x |

The re-measurements were taken after many further runs had warmed the 8 GB
buffer pool, while the indexed run began closer to cold. **Absolute timings in
this project carry roughly ±50% depending on cache state**, and should be read
as such. Ratios measured within a single controlled pass — A vs B vs C above —
are the trustworthy part.

**Three indexes on one table cause 74% of all regression time.**

## Why those three indexes hurt

`INDEX_STATISTICS` from the indexed run:

| Index | Rows read | Table rows | Amplification |
|---|---|---:|---:|
| `store_sales.idx_ss_addr_sk` | 23,305,757 | 2,879,152 | **6.2x** |
| `inventory.idx_inv_warehouse_sk` | 64,279,786 | 11,745,000 | **4.9x** |
| `item.idx_item_2` | 89,960 | 18,000 | 5.2x |

`idx_inv_warehouse_sk` reads **64 million rows from an 11.7 million row
table** — five complete passes, each as random lookups. The optimizer
estimates a few thousand rows, picks a nested loop, and the real access pattern
touches most of the table one row at a time. A single sequential scan would
have read each row once.

## 81 of the 117 indexes were never read

| | |
|---|---:|
| Secondary indexes defined | 117 |
| Actually read | **36** |
| **Never touched** | **81 (69%)** |

Unchanged from the earlier measurement, which is a useful consistency check
across a completely different dataset. `sql/06_drop_unused_indexes.sql` removes
them. They cost storage and write throughput and contribute nothing.

## Two queries hit the 300s cap

| Query | Base | Indexed |
|---|---|---|
| 72 | killed at 300s | killed at 300s |
| 95 | killed at 300s | **0.1s** |

`max_statement_time = 300` is not in the repo's config; it was added because
query 72 previously consumed 21 and then 29 minutes without completing. It
bounds a run without affecting any query that finishes.

Query 72 does not complete in five minutes in **either** configuration, so
indexes neither help nor hurt it. It remains unexplained.

## Correctness

Every query that completed in both runs returned **the same number of rows in
both**. The only difference is query 95, which produced no rows in base because
it was killed. Indexes changed timing, never results.

## Caveats

1. **Single run per configuration**, no warm-up, no repetition. Indicative, not
   statistically sound.
2. **The buffer pool was cold at the start of the base run** and warm by the
   indexed run, which flatters the indexed column slightly. Since the indexed
   column is the *slower* one on the clean 97, this works against the
   conclusion rather than for it.
3. Results cannot be compared to TPC answer sets under this configuration —
   see the seed discussion above.
