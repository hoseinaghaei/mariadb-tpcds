# InnoDB page size: 8K / 16K / 32K / 64K

Four standalone instances, identical in every respect but
`innodb_page_size`: same 8 GB buffer pool, same 158 indexes, same
scale-1 dataset, same serial 99-query run, each started cold.


## Storage

| page | data | index | total | vs 16K |
|---|---:|---:|---:|---:|
| 8K | 2,586 MB | 6,426 MB | 9,012 MB | -0.7% |
| 16K | 2,727 MB | 6,350 MB | 9,077 MB | — |
| 32K | 2,977 MB | 6,555 MB | 9,532 MB | +5.0% |
| 64K | 3,188 MB | 6,881 MB | 10,070 MB | +10.9% |

## Correctness cross-check

- **99 of 99 queries return a byte-identical result on every page size.**


## Total runtime

| page | 99-query total | vs 16K |
|---|---:|---:|
| 8K | 573.3s | -14.5% |
| 16K | 670.3s | — |
| 32K | 454.3s | -32.2% |
| 64K | 527.6s | -21.3% |


## Per query

Queries where page size moved the time by more than 20%, largest effect first.

| query | 8K | 16K | 32K | 64K | best | worst/best |
|---|---:|---:|---:|---:|---:|---:|
| query72 | 63.7s | 55.4s | 3.7s | **1.6s** | 64K | 39.81x |
| query63 | 4.4s | 7.5s | **0.5s** | **0.5s** | 32K | 15.00x |
| query53 | 3.1s | 7.4s | **0.5s** | **0.5s** | 32K | 14.80x |
| query8 | 4.2s | 4.8s | **0.4s** | **0.4s** | 32K | 12.00x |
| query89 | 3.4s | 7.1s | **0.6s** | **0.6s** | 32K | 11.83x |
| query17 | 5.2s | 9.7s | **1.0s** | 1.1s | 32K | 9.70x |
| query43 | 4.4s | 4.8s | **0.5s** | **0.5s** | 32K | 9.60x |
| query48 | 3.6s | 7.0s | 1.3s | **0.8s** | 64K | 8.75x |
| query27 | 6.7s | 4.7s | **0.9s** | 1.2s | 32K | 7.44x |
| query16 | 2.1s | 0.4s | **0.3s** | **0.3s** | 32K | 7.00x |
| query13 | 5.1s | 7.7s | 1.4s | **1.1s** | 64K | 7.00x |
| query23 | **25.5s** | 86.7s | 71.7s | 126.9s | 8K | 4.98x |
| query75 | 5.3s | 1.2s | **1.1s** | **1.1s** | 32K | 4.82x |
| query70 | 9.2s | 8.6s | **2.2s** | 2.5s | 32K | 4.18x |
| query99 | 3.6s | **0.9s** | 1.0s | 1.0s | 16K | 4.00x |
| query35 | 0.4s | 1.2s | **0.3s** | 0.4s | 32K | 4.00x |
| query88 | 1.0s | 0.8s | **0.3s** | **0.3s** | 32K | 3.33x |
| query24 | 2.7s | 2.7s | **1.0s** | **1.0s** | 32K | 2.70x |
| query28 | 0.8s | 0.4s | **0.3s** | 0.4s | 32K | 2.67x |
| query36 | 4.7s | 6.7s | **2.6s** | 2.7s | 32K | 2.58x |
| query34 | 5.9s | 4.7s | **2.3s** | **2.3s** | 32K | 2.57x |
| query68 | 6.4s | 4.8s | **2.5s** | 2.7s | 32K | 2.56x |
| query78 | 6.8s | **6.7s** | 16.2s | 16.5s | 16K | 2.46x |
| query47 | 36.5s | 57.6s | **24.5s** | 26.8s | 32K | 2.35x |
| query80 | 0.7s | 0.6s | 0.5s | **0.3s** | 64K | 2.33x |
| query31 | 0.7s | **0.3s** | **0.3s** | **0.3s** | 16K | 2.33x |
| query7 | 1.7s | 2.8s | **1.2s** | 1.7s | 32K | 2.33x |
| query65 | 0.9s | 0.6s | **0.4s** | **0.4s** | 32K | 2.25x |
| query1 | 1.8s | 1.8s | 1.4s | **0.8s** | 64K | 2.25x |
| query73 | 4.3s | 4.5s | 2.2s | **2.1s** | 64K | 2.14x |
| query79 | 4.5s | 4.9s | **2.5s** | 2.6s | 32K | 1.96x |
| query18 | **0.9s** | 1.0s | 1.7s | **0.9s** | 8K | 1.89x |
| query46 | 5.0s | 5.1s | **2.7s** | **2.7s** | 32K | 1.89x |
| query67 | 12.3s | 11.3s | **7.1s** | 7.5s | 32K | 1.73x |
| query11 | 9.5s | 14.9s | **8.9s** | 10.7s | 32K | 1.67x |
| query77 | 0.5s | 0.4s | **0.3s** | 0.4s | 32K | 1.67x |
| query87 | 1.4s | 1.2s | **0.9s** | **0.9s** | 32K | 1.56x |
| query38 | 1.4s | 1.3s | **0.9s** | 1.0s | 32K | 1.56x |
| query71 | 0.7s | **0.5s** | 0.6s | 0.6s | 16K | 1.40x |
| query49 | **0.5s** | 0.6s | 0.6s | 0.7s | 8K | 1.40x |
| query66 | 1.1s | 1.1s | 0.9s | **0.8s** | 64K | 1.38x |
| query39 | 1.3s | **1.1s** | **1.1s** | 1.5s | 16K | 1.36x |
| query57 | 13.5s | 10.6s | **10.0s** | 10.2s | 32K | 1.35x |
| query60 | 0.4s | **0.3s** | **0.3s** | **0.3s** | 16K | 1.33x |
| query21 | 0.4s | 0.4s | **0.3s** | 0.4s | 32K | 1.33x |
| query74 | 4.7s | 4.5s | **3.6s** | 4.0s | 32K | 1.31x |
| query54 | 28.3s | 22.3s | 22.2s | **22.1s** | 64K | 1.28x |
| query14 | 49.1s | 61.4s | **48.1s** | 53.8s | 32K | 1.28x |
| query86 | 0.5s | **0.4s** | **0.4s** | **0.4s** | 16K | 1.25x |
| query5 | 72.5s | 83.9s | **67.2s** | 75.6s | 32K | 1.25x |
| query76 | **0.5s** | 0.6s | **0.5s** | **0.5s** | 8K | 1.20x |

51 of 60 measurable queries move by 20% or more.


## Which page size wins

| page | queries fastest | queries slowest |
|---|---:|---:|
| 8K | 6 | 36 |
| 16K | 10 | 26 |
| 32K | 42 | 3 |
| 64K | 32 | 7 |

(of 60 queries that run long enough to measure)


## Reproducibility: two independent passes

| page | pass 1 | pass 2 | mean | run-to-run |
|---|---:|---:|---:|---:|
| 8K | 573.3s | 548.5s | **560.9s** | 4.5% |
| 16K | 670.3s | 620.5s | **645.4s** | 8.0% |
| 32K | 454.3s | 471.6s | **463.0s** | 3.8% |
| 64K | 527.6s | 538.4s | **533.0s** | 2.0% |

Run-to-run variation is 3.8–8.0%. The spread between page sizes is
1.39x, far outside that, so the
differences are real and not measurement noise. The ordering — 32K fastest,
16K slowest — held in both passes.


## Why: page size changes the optimizer's plan, not the I/O

The timing differences are far too large and too bidirectional to be I/O
economics. `EXPLAIN` on the same query against two instances shows why —
the plans are not the same query executed at different speeds, they are
different queries.

**query53** (7.4s at 16K, 0.5s at 32K):

| | 16K | 32K |
|---|---|---|
| drive table | `store`, index scan | `date_dim` range, 365 rows |
| `store_sales` | `idx_ss_store_hdemo_time`, 2123 rows | `idx_ss_date_item_store_cover`, **Using index** |
| join order | store → store_sales → item → date_dim | date_dim → store_sales → item → store |

**query72** (55.4s at 16K, 3.7s at 32K): the join order inverts completely.
16K drives `warehouse → inventory → item`, reaching `catalog_sales` seventh
behind a rowid filter. 32K drives `item → catalog_sales` and reaches
`inventory` ninth by PRIMARY.

The date-first, covering-index plan is the same shape that every successful
hand optimization in `report/19-three-way-comparison.md` converged on. At 32K
the optimizer finds it unaided.

### The mechanism is statistics sampling, mostly

`innodb_stats_persistent_sample_pages` defaults to **20 pages** — a fixed page
count, not a fixed row count. A 32K page holds twice the index entries of a
16K page, so the same 20-page sample covers twice as many rows and produces
better cardinality estimates. Larger pages were buying better statistics.

Tested directly: setting `innodb_stats_persistent_sample_pages = 160` on the
**16K** instance and re-running `ANALYZE` makes it choose the 32K plan for
query53 — `date_dim` first, `store_sales` covering. Across the full suite:

| configuration | 99-query total |
|---|---:|
| 16K, default sampling (20) | 645.4s |
| **16K, sampling 160** | **508.2s** |
| 32K, default sampling | 463.0s |

Deeper sampling on 16K recovers **21%** — most of the gap to 32K — with a
one-line config change and no datadir rebuild. Per query:

| query | 8K | 16K | 16K+stats | 32K | 64K |
|---|---:|---:|---:|---:|---:|
| query17 | 5.2s | 9.7s | **1.1s** | 1.0s | 1.1s |
| query63 | 4.4s | 7.5s | **0.7s** | 0.5s | 0.5s |
| query53 | 3.1s | 7.4s | **0.7s** | 0.5s | 0.5s |
| query89 | 3.4s | 7.1s | **0.8s** | 0.6s | 0.6s |
| query70 | 9.2s | 8.6s | **2.6s** | 2.2s | 2.5s |
| query47 | 36.5s | 57.6s | **28.9s** | 24.5s | 26.8s |
| query72 | 63.7s | 55.4s | 21.6s | 3.7s | **1.6s** |

Every one of those lands at or near its 32K time once 16K samples deeply
enough — **except query72**, which stays 6x off (21.6s vs 3.7s). So statistics
sampling explains most of the effect but not all of it; query72 has a residual
page-size dependence this experiment does not isolate.


## What to actually do

1. **Do not rebuild the datadir for page size.** Set
   `innodb_stats_persistent_sample_pages = 160` on the existing 16K server and
   re-run `ANALYZE TABLE`. That captures most of the available gain for the
   cost of one config line, and it is reversible.
2. **If you do rebuild, 32K is the pick, not 64K.** 32K was fastest in both
   passes and fastest on 42 of 60 measurable queries. 64K is slower overall and
   costs 10.9% more disk.
3. **8K is not worth it.** Slightly smaller on disk (-0.7%) but 21% slower than
   32K, and slowest on 36 of 60 queries.
4. **Re-check the hand-tuned queries afterwards.** Several of the optimizations
   in report 19 exist to force the plan that better statistics now produce on
   their own — query72 above all. Deeper sampling may make some of them
   redundant, and a rewrite that forces a join order can become a liability
   once the optimizer's unaided choice is the good one.

### Caveats

- Scale factor 1 with an 8 GB buffer pool means the whole 9 GB database very
  nearly fits in memory. Page size governs I/O granularity, and there is
  almost no I/O here. At a scale where the data does not fit, the ranking
  could differ — this result should not be extrapolated to a larger dataset
  without re-measuring.
- All four copies carry all 158 indexes with none ignored, so these totals are
  not comparable to the 1563s in report 13, which had 80 indexes ignored.
- `information_schema.TABLES.table_rows` differs across the copies
  (19.3M–21.0M) because it is sampled, not counted. The storage figures are
  exact; the row estimates are not.


## Reproducing

```bash
pagesize/build-instance.sh 32     # init datadir, load, index, analyze
pagesize/ctl.sh start|stop|status 32
pagesize/run-all.sh [--tag TAG]   # all four, serial, one at a time
python3 pagesize/compare.py
```

Each instance is self-contained under `pagesize/` with its own datadir, config,
port (3400+KB) and socket. The Homebrew server on 3306 is never touched. The
four datadirs total ~37 GB and are gitignored; delete with
`rm -rf pagesize/data-*`.
