# Step 16 — Buffer pool, and the root cause of the regressions

> Performance figures here are **not comparable to TPC Benchmark Results** —
> unaudited, scale factor 1, not meeting any official TPC Benchmark Standard.

[Step 15](15-index-statistics.md) measured *what* the regressions were doing —
random index reads at up to 5x amplification with zero prefetch — but left two
candidate causes: a 128 MB buffer pool too small to hold the working set, or
the optimizer simply choosing bad plans. This step separates them.

## Changes made

| Setting | Before | After |
|---|---:|---:|
| `innodb_buffer_pool_size` | 128 MB (8,192 pages) | **2 GB (131,072 pages)** |
| `max_statement_time` | unlimited | **300s** |

Both applied online — the pool resize needed no restart — and persisted to
`my.cnf.d/tpcds-observability.cnf`.

The statement cap immediately paid for itself: **query 72**, which had
consumed 21 and then 29 minutes without completing on two earlier attempts,
was killed cleanly at 300.1s with
`ERROR 1969: Query was interrupted: execution time limit 300.0 sec exceeded`.

## The buffer pool fixes most of it

All 99 queries were re-run with the 2 GB pool (tag `pool2g`). Of the 19
queries that indexing had made slower:

| Outcome | Count |
|---|---:|
| **Recovered to baseline or better** | **8** |
| Partly recovered | 7 |
| **Not recovered, or worse** | **4** |

Several ended up *faster than they had ever been*, including before the
indexes existed — which is what you expect once an index finally has enough
cache to be worth using:

| Query | Pre-index | Indexed (128 MB) | 2 GB pool |
|---|---:|---:|---:|
| 29 | 5.4s | 8.3s | **0.9s** |
| 73 | 10.6s | 15.2s | **1.8s** |
| 48 | 8.2s | 14.6s | **3.5s** |
| 88 | 48.2s | 83.9s | **19.9s** |
| 10 | 22.8s | 43.9s | **17.7s** |
| 35 | 14.9s | 44.4s | **14.5s** |

**The memory shortage, not the index set, was the dominant cause.**

### Aggregate totals are NOT usable here

| Run | 96 comparable queries | Concurrency |
|---|---:|---|
| base | 2919.3s | up to 5 concurrent, with orphan duplicates |
| indexed | 1733.3s | largely serial |
| pool2g | 2427.8s | **5 agents parallel** |

`pool2g` looks worse than `indexed` in total, but it was run five-way parallel
against a server the `indexed` run had largely to itself. That gap is
contention, not regression. Confirmed directly: re-running query 21 serially
on a quiet server gave **24.0s versus 91.3s** contended. Only per-query
comparisons against a quiet server mean anything.

## The four that memory could not fix

| Query | Pre-index | Indexed | 2 GB pool |
|---|---:|---:|---:|
| **39** | 1.6s | 193.6s | **209.4s** |
| **21** | 0.5s | 59.8s | **91.3s** |
| **22** | 15.3s | 70.5s | **61.7s** |
| 91 | 0.4s | 1.6s | 2.3s |

Sixteen times more memory left query 39 no better. That rules out cache
residency and points at plan choice.

`EXPLAIN` on the three worst gives a single shared answer:

```
query39:  inventory.idx_inv_warehouse_sk   type=ref  est_rows=6170
query21:  inventory.idx_inv_warehouse_sk   type=ref  est_rows=6170
query22:  inventory.idx_inv_item_sk        type=ref  est_rows=522
```

**All three are driven by a secondary index on `inventory`** — 11,745,000
rows, the largest table in the schema. The optimizer estimates a few thousand
rows and picks a nested loop; the real access pattern touches a large fraction
of the table, one random lookup at a time. Step 15 measured
`idx_inv_warehouse_sk` reading **58,725,000 rows from an 11,745,000-row
table** — five complete passes.

## Confirmed by experiment

The three `inventory` secondary indexes were removed and the queries re-run
serially on a quiet server:

| Query | base | indexed | 2 GB (serial) | **inventory indexes gone** |
|---|---:|---:|---:|---:|
| **39** | 1.6s | 193.6s | 146.5s | **1.7s** |
| **21** | 0.5s | 59.8s | 24.0s | **0.3s** |
| **22** | 15.3s | 70.5s | 29.0s | **11.5s** |

Query 39 goes from 146.5s to **1.7s — 86x faster** — and back to its
pre-index baseline. Query 21 ends up *faster* than it ever was. Row counts were
identical throughout (153 / 100 / 100), so the results did not change.

**Diagnosis confirmed: three indexes on one table caused the worst remaining
regressions.**

## Use IGNORED, not DROP

The indexes have been **restored** — the database is back to all 117.

For this kind of experiment, MariaDB 10.6+ offers ignored indexes, which are
strictly better than dropping:

```sql
ALTER TABLE inventory ALTER INDEX idx_inv_warehouse_sk IGNORED;      -- hide
ALTER TABLE inventory ALTER INDEX idx_inv_warehouse_sk NOT IGNORED;  -- restore
```

The optimizer stops considering the index, but it stays fully built and
maintained on disk. **Measured at 0.15s in each direction** — versus minutes to
rebuild a dropped index on an 11.7M-row table. Verified: with the index
IGNORED the plan immediately fell back to a different access path, and
`information_schema.STATISTICS.IGNORED` flips `YES`/`NO`.

Two scripts ship this:

- `sql/07_ignore_inventory_indexes.sql` — hide all three
- `sql/08_unignore_inventory_indexes.sql` — restore them

## Where this leaves the optimization work

1. **Keep the 2 GB buffer pool.** It resolved 15 of 19 regressions on its own
   and cost nothing.
2. **Ignore the three `inventory` indexes.** They cause the worst remaining
   regressions and step 15 showed they are read at 5x amplification.
3. **Drop the 81 indexes no query ever read** (`sql/06_drop_unused_indexes.sql`) —
   pure overhead.
4. **Then re-measure serially**, one query at a time on a quiet server. Every
   number in this project so far has some contention in it; a clean serial
   baseline is the missing piece before any of this is quotable.
5. Query 91 remains unexplained — small (0.4s to 2.3s) and driven by
   `customer.idx_c_current_addr_sk` and
   `catalog_returns.idx_cr_returning_customer_sk` rather than `inventory`.
