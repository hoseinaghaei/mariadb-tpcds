# Step 17 — "Never read" does not mean "safe to drop"

> **NOT COMPARABLE TO TPC BENCHMARK RESULTS.**

[Step 15](15-index-statistics.md) found that 81 of the 117 indexes were never
read, and recommended dropping them as pure overhead. **That recommendation was
wrong**, and this step is the experiment that disproved it.

## The experiment

All 80 indexes with zero `ROWS_READ` were made `IGNORED` — hidden from the
optimizer, left built on disk — and all 99 queries re-run serially on the same
data and the same 8 GB buffer pool.

Hiding them took **17.7 seconds** for all 80 (~0.22s each), no rebuilds.

## The aggregate result: no change, as expected

| Run | 96 queries completing in all three |
|---|---:|
| base (no indexes) | 1204.7s |
| indexed (117) | 1189.4s |
| **ignored80 (37 visible)** | **1179.6s** |

**−0.8% versus the indexed run.** 10 queries faster by >10%, 9 slower, 77
unchanged — noise in both directions. Row counts identical across all three
runs.

On the aggregate, the conclusion looked confirmed: the 80 indexes contribute
nothing.

## The result that overturned it

| Query | base | indexed | **ignored80** |
|---|---:|---:|---:|
| **78** | 72.1s | 73.4s | **911.6s, killed at the cap** |

Query 78 went from 73 seconds to not completing. Restoring the indexes brought
it straight back — **44.0s** on re-measurement.

It is excluded from the 96-query aggregate above precisely because it was
capped, which is how a 12x blow-up hid inside a −0.8% headline.

## Why it happened

Diffing `EXPLAIN` for query 78 with and without the hidden indexes, the
**chosen** key never changes. What changes is `possible_keys`:

```
 with all 117          store_returns   PRIMARY,idx_sr_item_sk,idx_sr_ticket_number   -> key: idx_sr_item_sk
 with 80 hidden        store_returns   PRIMARY,idx_sr_item_sk                        -> key: idx_sr_item_sk

 with all 117          web_sales       PRIMARY,idx_ws_sold_date_sk,idx_ws_item_sk,idx_ws_bill_customer_sk
 with 80 hidden        web_sales       PRIMARY

 with all 117          catalog_sales   PRIMARY,idx_cs_sold_date_sk,idx_cs_bill_customer_sk,idx_cs_item_sk
 with 80 hidden        catalog_sales   PRIMARY,idx_cs_bill_customer_sk

 with all 117          catalog_returns PRIMARY,idx_cr_item_sk,idx_cr_order_number    -> key: idx_cr_item_sk
 with 80 hidden        catalog_returns PRIMARY,idx_cr_item_sk                        -> key: idx_cr_item_sk
```

`idx_sr_ticket_number`, `idx_ws_sold_date_sk`, `idx_ws_item_sk`,
`idx_cs_sold_date_sk`, `idx_cs_item_sk` and `idx_cr_order_number` are never
*chosen*. But their **availability changes the optimizer's cost estimates**,
and therefore the join order it picks. Remove them as candidates and it commits
to a different, far worse join order.

**`INDEX_STATISTICS.ROWS_READ` counts rows read *through* an index. An index
can shape a plan without ever being read.** The two are not the same
measurement, and only one of them is recorded.

## What this means for the drop script

`sql/06_drop_unused_indexes.sql` removes 81 indexes and would have caused this
regression — irreversibly, since dropping is not free to undo on an 11.7M-row
table.

The script is kept, because the storage case is real:

| | |
|---|---:|
| All secondary indexes on disk | 3.74 GB |
| The 80 "unused" ones | **2.49 GB** |
| Datadir total | 6.5 GB |

Two thirds of the index footprint, and the corresponding write amplification on
every insert, is attributable to indexes no query reads. That is a genuine cost.

But it now carries a warning, and the recommended procedure is different:

1. **Use `IGNORED`, never `DROP`, to test.** `sql/09_ignore_unused_indexes.sql`
   and `sql/10_unignore_unused_indexes.sql` — 17.7s each way for all 80.
2. **Run the full query set after hiding them**, and check *every* query, not
   the aggregate. The aggregate moved −0.8% while one query blew up 12x.
3. **Watch for queries that hit the statement-time cap.** A capped query is
   excluded from totals, so a catastrophic regression can vanish from the
   headline. That is exactly what happened here.
4. Only drop what survives that, and only if the storage matters.

## Current state

All 117 indexes are restored and visible; nothing is ignored.

## The broader lesson

Two recommendations in this project have now been overturned by testing them:

- "Indexing gives a 2.06x speedup" — an artefact of a 128 MB buffer pool
  ([step 16](16-buffer-pool-and-root-cause.md)). Real figure: 1.01x.
- "81 indexes are unused and safe to drop" — this step. They are unread, but
  one of them is load-bearing for query 78.

Both looked well-evidenced. Both were wrong in the same way: a metric was
trusted as a proxy for the thing that actually mattered.
