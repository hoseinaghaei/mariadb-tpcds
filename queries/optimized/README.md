# Hand-optimised queries

One sub-folder per query. Each holds every variant tried, plus a `README.md`
with measured timings and the reasoning.

Riccardo's separately measured Q4, Q5, Q31, Q39 and Q51 work is documented in
[`experiments/README.md`](../../experiments/README.md), with evidence in
[`experiments/evidence/riccio_sf1_20261014/`](../../experiments/evidence/riccio_sf1_20261014/).
Those Linux/SF=1 measurements use their own baselines; the historical table below
belongs to the original repository author.

The step-by-step documents for [Q4](q4/README.md), [Q5](q5/README.md),
[Q31](q31/README.md), [Q39](q39/README.md) and [Q51](q51/README.md) compare every
retained SQL version, its output and performance, the plan evidence, and the
reason for selection or rejection. The [report chapter](../../report/riccardo-query-experiments.md#development-history-and-alternatives)
collects the version history into one table for report assembly.

| Query | Original | Best | Speedup |
|---|---:|---:|---:|
| [`q72`](q72/) | 719.3s | **1.0s** | **719x** |
| [`q59`](q59/) | 7.3s | **1.2s** | **6.1x** |
| [`q22`](q22/) | 23.0s | **4.3s** | **5.3x** |

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
