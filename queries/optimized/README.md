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
| [`q2`](q2/) | 84s | **25.9s** | **3.2x** |
| [`q88`](q88/) | 33s | **0.25s** | **~130x** |
| [`q78`](q78/) | 27.2s | **8.5s** | **3.2x** |

`query<N>_BEST.sql` in each completed folder is its selected version.

## Riccardo's Tier 4 results — local SF=4, seed=10

The five folders now contain selected `query<N>_BEST.sql` files and READMEs
with the query's meaning, development comparisons, plan observations,
correctness checks and rerun commands. The selected files were renamed from
the latest measured candidates without changing their SQL. The `v0` originals
remain unchanged; the `v1` files are baseline-copy placeholders.

| Query | Original | Selected | Observed ratio | Final correctness check |
|---|---:|---:|---:|---|
| [Q82](q82/README.md) | 0.732s | **0.687s** | 1.07x | 5 identical ordered rows |
| [Q37](q37/README.md) | 1.049s | **0.804s** | 1.30x | 4 identical ordered rows |
| [Q65](q65/README.md) | 91.718s | **45.167s** | 2.03x | Same 100-row multiset; tied-row order differs |
| [Q70](q70/README.md) | 93.248s | **24.549s** | 3.80x | 3 identical ordered rows |
| [Q87](q87/README.md) | 145.224s | **55.183s** | 2.63x | Identical scalar count: 184693 |

These are separate **single original-then-selected pairs**, not medians, on
Riccardo's Linux/MariaDB 10.11.14 database with primary keys only and a 2 GiB
buffer pool. Do not combine them with the author's indexed/SF=1 timings above.
The final pairs were checked interactively without saving raw trial artifacts.
All five also passed session-local nonempty fixtures. Remeasure on the final
group machine and datasets before using the ratios as final benchmark results.
Q82's small final difference needs repetition; its rejected v2 was much slower.

**Q65 has not passed the strict ordered-result comparator.** Its complete
100-row multiset matched, while rows tied on the original ORDER BY keys changed
order. Its README explains the LIMIT/tie caveat; do not label it byte-identical.
The [earlier Tier 4 workflow](../../experiments/tier4/README.md) remains a
preparation guide; use the per-query READMEs for the current files and findings.

## Ground rules

1. **Output must not change.** The original author's timings above use a
   byte-identical diff against the unmodified query. Riccardo's SF=4 checks
   distinguish exact ordered agreement from the explicitly documented Q65
   tie-order difference; that query has not passed the strict comparator.
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
