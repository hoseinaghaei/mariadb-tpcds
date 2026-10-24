# Query 51 — step-by-step optimization

Selected version: [query51_v1_unifieddaily.sql](query51_v1_unifieddaily.sql).
[query51_BEST.sql](query51_BEST.sql) contains exactly the same SQL.

## What the query must return

For each item and date in month sequences **1176–1187**, aggregate web and store
sales, calculate each channel's running sum, combine the channels' item/date
keys, and retain the original subsequent running maximum. Return rows whose
web cumulative value exceeds the store value, with the original six fields,
ordering and `LIMIT 100`. NULL item keys remain excluded.

The original returns **100 rows**. A channel can be absent on a date on which
the other channel is present; the returned fields must preserve that absence.

## Conditions for these comparisons

All timings below are saved **local preliminary measurements**, obtained on
14 October 2026: MariaDB 10.11.14, Ubuntu/Linux, Ryzen 5 3500U, 6.7 GiB RAM,
generator SF=1 and data seed 10. The InnoDB buffer pool was 2 GiB; temporary-table
and heap-table limits were 16 MiB. The machine had substantial swap use.

`pk` means primary keys only. `reference` means those primary keys plus all
117 secondary indexes from the repository. The SQL rewrites add no indexes.
Each ordinary timing group has three serial runs after exploratory executions
or warm-ups, with the query cache disabled. Times include client connection,
session setup, execution and complete result transfer. Diagnostics and fixtures
are excluded. Speedup = original median / candidate median **within the same
series and configuration**. No controlled cold-cache reset was performed.

The final benchmark is planned on Hossein's computer. These Linux results must
be repeated there and at the four agreed scales; they are not measurements of
that final machine. See the [measurement protocol](../../../experiments/README.md#run-controlled-comparisons)
for ordering details and limitations.

## Version-by-version comparison

| Version | Change | Role |
| --- | --- | --- |
| [v0](query51_v0.sql) | Emulate the full outer join with two join/UNION branches | Baseline |
| [v1](query51_v1_unifieddaily.sql) | Combine daily keys once, then compute and mask the running values | Selected rewrite |

### Step 0 — v0: locate duplicated channel processing

The original computes channel aggregates with running sums. It emulates a full
outer join as a left-join branch plus a right-join branch containing only
unmatched rows. Each branch references the channel results. The saved primary-key
`EXPLAIN` has **two web_sales and two store_sales table nodes**: the SQL CTE names
do not guarantee that these results are calculated once and reused.

Another running window, `MAX`, is then applied over the combined result.
The baseline medians are **77.282 s with primary keys** and **60.528 s with
reference indexes**.

### Step 1 — v1: combine daily keys before computing the windows

The selected SQL consists of five stages:

| CTE | Input and purpose |
| --- | --- |
| `channel_daily` | Aggregate one row per item/date/channel from each fact table, then UNION ALL the two channels. |
| `daily` | Pivot those daily values into web/store columns and retain `has_web` / `has_store` presence flags. |
| `running` | Compute each channel's running SUM on the combined item/date calendar. |
| `masked` | Return NULL for that channel's current value on dates with no original channel row. |
| `y` | Apply the original running MAX, then use the unchanged final filter/order/limit. |

The saved v1 `EXPLAIN` has **one web_sales and one store_sales table node**.
That supports the explanation of removing repeated channel processing. It is
not an actual row-read count: no Q51 ANALYZE diagnostic is saved. Window sorting
and temporary-result work remain possible costs, and their separate runtime
shares were not measured.

The primary-key median becomes **58.484 s (1.32× vs v0)**. The indexed median
becomes **48.549 s (1.25×)**. There is one candidate version; the five internal
CTE stages are not five separately measured optimization steps. No intermediate
stage is assigned an invented standalone speedup.

### Repeated primary-key results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query51_v0.sql) | 3 | 77.282 | 59.333–83.267 | 1.00× |
| [v1](query51_v1_unifieddaily.sql) | 3 | 58.484 | 46.695–62.934 | 1.32× |

### Repeated indexed results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query51_v0.sql) | 3 | 60.528 | 59.977–61.027 | 1.00× |
| [v1](query51_v1_unifieddaily.sql) | 3 | 48.549 | 47.593–50.957 | 1.25× |

The primary-key ranges overlap: v0 is 59.333–83.267 s and v1 is 46.695–62.934 s.
The ratio of medians is preliminary evidence, not a precise or universal gain.
The indexed ranges are narrower in this local series; repeat them on the final
machine before reporting a final conclusion.

## Why presence flags and both window operations are necessary

A cumulative sum on the combined calendar exists even on a date with no web
row. The original full outer join would return NULL for `web_sales` on that
date. The `masked` CTE restores that behavior:

```sql
CASE WHEN has_web = 1 THEN web_running END AS web_sales,
CASE WHEN has_store = 1 THEN store_running END AS store_sales
```

The following is a **teaching example, not a measured benchmark output**.
For one item, let web daily sales be 10, absent, then -8; the middle date exists
because store sales occurred there:

| Date step | Web daily value | has_web | Internal web running SUM | Returned web_sales | Original running MAX |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 10 | 1 | 10 | 10 | 10 |
| 2 | absent / NULL | 0 | 10 | NULL | 10 |
| 3 | -8 | 1 | 2 | 2 | 10 |

At step 2, the presence flag preserves a NULL in the returned channel field.
At step 3, the running sum is 2 while the required running maximum is still 10.
Keeping both operations is therefore necessary even if the generated data often
happen to have positive increments. Presence is also separate from an all-NULL
daily measure or a genuine zero; it is not inferred from the sum's numeric value.

The rewrite preserves one daily row per item/date/channel before combining
keys, the original month filter and NULL-item exclusion, the final six fields,
the comparison, ordering and limit. Duplicate facts on one date still contribute
to that date's SUM.

## Compare the returned results

The comparison checks complete ordered values, column names, duplicate
columns, NULLs and result-set boundaries; equal row counts alone are
insufficient. `LIMIT`, where present, remains part of the original query.

| Version | Rows per result set on SF=1 | Full output comparison |
| --- | --- | --- |
| [v0](query51_v0.sql) | 100 | Saved original |
| [v1](query51_v1_unifieddaily.sql) | 100 | 6/6 ordinary runs matched the original; timings remain separated by profile |

For a concrete value comparison, the first returned row of result set 1
is shown below. The candidate is `query51_v1_unifieddaily.sql`. The complete
outputs, rather than only this example, were compared.

| Output column (position) | Original v0 | Selected v1 |
| --- | --- | --- |
| item_sk (1) | `1` | `1` |
| d_date (2) | `1998-01-22` | `1998-01-22` |
| web_sales (3) | `166.57` | `166.57` |
| store_sales (4) | `49.97` | `49.97` |
| web_cumulative (5) | `166.57` | `166.57` |
| store_cumulative (6) | `49.97` | `49.97` |

The initial fixture returns **3 baseline and 3 identical candidate rows**.
An extended fixture adds the distinction between a genuine zero and NULL and
returns **4 baseline and 4 identical candidate rows**; this is the fixture
produced by the current `build_semantic_fixture.py`. Together they cover
channel-only dates, NULL measures, negative increments, multiple daily facts,
out-of-window rows and NULL item keys.

## Reproduce the selected comparison

Run from the repository root after following the [setup guide](../../../experiments/README.md#reproduce-on-a-fresh-database).
The example assumes a loaded dedicated `$TPCDS_DB`, SF=1, seed 10, and the 117
reference indexes physically present. `--profile reference` is a label and does
not create indexes. Choose a new session directory for each attempt.

```bash
python3 scripts/build_experiment_jobs.py \
  --queries 51 --profile reference --scale 1 --data-seed 10 --repeats 3 \
  --runs experiments/local/q51_review_reference/runs \
  --output experiments/local/q51_review_reference/jobs.json

python3 scripts/run_query_batch.py \
  --database "$TPCDS_DB" \
  --jobs experiments/local/q51_review_reference/jobs.json \
  --out experiments/local/q51_review_reference/runs

python3 scripts/summarize_experiments.py \
  --runs experiments/local/q51_review_reference/runs \
  --out experiments/local/q51_review_reference/summary
```

This runs discarded warm-ups followed by three alternating v0/v1 rounds.
It compares against a fresh local original, not an output copied from the Linux
machine. For another retained version, use the [manual comparison example](../../../experiments/README.md#compare-an-intermediate-version).
Repeat under `pk` only after verifying that secondary indexes are absent; keep
its results in a separate session. Preserve the same query parameters in both
versions at each scale.

## Evidence for the report

The [measurement CSV](../../../experiments/evidence/riccio_sf1_20261014/measurements.csv)
and [raw archive](../../../experiments/evidence/riccio_sf1_20261014/raw_trials.zip)
are committed. The [archive inspection instructions](../../../experiments/README.md#inspect-the-committed-evidence-without-a-database)
explain how to extract them without running MariaDB. Paths below are members
inside that archive:

| Evidence | Archive path |
| --- | --- |
| Original output example | `runs/q51_v0_pk_probe/result.json` |
| Selected output example | `runs/q51_v1_pk_r1/result.json` |
| Original primary-key estimate | `runs/q51_v0_pk_explain/plan_1.json` |
| Unified-daily primary-key estimate | `runs/q51_v1_pk_explain/plan_1.json` |
| Original indexed estimate | `runs/q51_v0_reference_explain/plan_1.json` |
| Unified-daily indexed estimate | `runs/q51_v1_reference_explain/plan_1.json` |

Ordinary labels ending in `_r1`, `_r2` and `_r3` contain `run.json`,
`input.sql`, `result.json`, raw `output.xml` and `stderr.txt`. The archived SQL
and SHA-256 hashes identify the version that was actually executed.

The selected `query51_BEST.sql` is an exact copy of the selected source,
not a separately measured implementation. For the final report, retain the
unsuccessful steps, state the configuration beside every timing, and repeat
correctness and performance checks on Hossein's machine and at each scale.
