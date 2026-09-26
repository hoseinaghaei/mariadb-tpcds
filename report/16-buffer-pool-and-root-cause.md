# Step 16 — What the buffer pool was hiding

> **NOT COMPARABLE TO TPC BENCHMARK RESULTS.**

This step exists to record a methodological mistake and its correction, because
the mistake produced a conclusion that looked solid and was not.

## The mistake

Everything up to step 15 was measured with `innodb_buffer_pool_size = 128M`
against a 3.2 GB database — **under 4%**. That was never a deliberate choice;
it was the Homebrew default, and it went unexamined.

On that configuration, adding 117 indexes appeared to produce a **2.06x**
speedup, and 19 queries appeared to regress. Both numbers were largely
artefacts. The indexes were compensating for a memory shortage, and the
"regressions" were random index lookups missing a cache far too small to hold
the working set.

The reference implementation this project builds on sets
`innodb_buffer_pool_size=8G` — the **only** performance line in its entire
server config. We were running at 1/64th of it.

## The correction

Everything was rebuilt on the reference configuration: data regenerated with
`-rngseed 10`, 8 GB pool, server restarted so every counter started at zero,
and both runs executed **strictly serially** on a quiet machine.

On that footing the indexes deliver **1.01x** across the 97 queries that
complete in both configurations — a 1% aggregate improvement. Full numbers in
[13-benchmark-results.md](13-benchmark-results.md).

## What survived the correction

Three findings held up on completely different data:

1. **Query 95 is transformed by indexing** — from not completing in 300s to
   0.1s. A `web_sales` self-join is quadratic without an index on
   `ws_order_number`.

2. **Three `inventory` indexes cause most of the regression time.** Confirmed
   by experiment: making them `IGNORED` returns query 39 from 92.5s to 1.7s and
   query 21 from 23.7s to 0.3s. Query 31 was predicted *not* to improve
   (its plan uses `store_sales.idx_ss_addr_sk`) and did not — the prediction
   discriminating between the two is what makes the diagnosis credible.

3. **81 of the 117 indexes are never read.** Same count on both datasets.

## What did not survive

- The **2.06x speedup** was a memory artefact. Real figure: 1.01x.
- The **19 regressions** were mostly a memory artefact too. On the corrected
  configuration 18 queries regress, but 16 of them lose under 4 seconds each;
  only 39 and 21 are serious, and they account for 74% of all time lost.
- The claim that a bigger pool "fixed 15 of 19 regressions" measured a
  comparison between two differently-contended runs and should be disregarded.

## Method note

The failure mode was changing several variables at once and comparing across
runs with different concurrency. Any future measurement here should keep the
dataset, the pool size and the concurrency fixed, and vary exactly one thing.

Use `ALTER INDEX ... IGNORED` rather than `DROP` for index experiments —
metadata-only, measured at 0.15s in each direction, and the index stays built.
`sql/07_ignore_inventory_indexes.sql` and `sql/08_unignore_inventory_indexes.sql`.
