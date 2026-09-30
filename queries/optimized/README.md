# Hand-optimised queries

One sub-folder per query. Each holds every variant tried, plus a `README.md`
with measured timings and the reasoning.

| Query | Original | Best | Speedup |
|---|---:|---:|---:|
| [`q72`](q72/) | 719.3s | **1.0s** | **719x** |
| [`q59`](q59/) | 7.3s | **1.2s** | **6.1x** |

`query<N>_BEST.sql` in each folder is the version to use.

## Ground rules

1. **Output must not change.** Every timing here is backed by a byte-identical
   diff of the full result against the unmodified query.
2. **Ablate.** Separate the contributions — for q72 the intuition was that the
   rewritten join order mattered; measurement showed it was worth 14% while the
   hint was worth 55x.
3. **Three-pass anything surprising** — measure, change, measure, revert,
   measure. A single reading is not a finding; see
   [`report/17`](../../report/17-unused-indexes-are-not-safe-to-drop.md) for
   what happens otherwise.
4. **Absolute timings vary ~±50%** with buffer-pool state. Only ratios measured
   within one controlled pass are reliable.

## Indexes

Added ones live in [`sql/11_optimizer_indexes.sql`](../../sql/11_optimizer_indexes.sql),
including a **rejected** section — `date_dim(d_month_seq)` looks obviously
useful and makes q59 10x slower.

Use `ALTER INDEX ... IGNORED` to test, never `DROP` — metadata-only, ~0.15s
each way, and the index stays built.
