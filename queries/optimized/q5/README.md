# Query 5 — step-by-step optimization

Selected version: [query5_v1_branchfilters.sql](query5_v1_branchfilters.sql).
[query5_BEST.sql](query5_BEST.sql) contains exactly the same SQL.

## What the query must return

Combine sales and returns for stores, catalog pages and web sites during the
inclusive interval **28 August–11 September 1998**. Compute the original sales,
returns and profit measures, then produce the original channel/entity rollup,
ordering and `LIMIT 100`. The interval includes both endpoints: an offset of
14 days gives 15 calendar dates.

The original returns **100 rows**. Its first row is the grand total, whose
channel and entity ID are NULL because they identify a rollup level.

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
| [v0](query5_v0.sql) | Union sales/returns, then filter dates outside each union | Baseline |
| [v1](query5_v1_branchfilters.sql) | Also apply the date interval inside all six branches | Selected rewrite |

### Step 0 — v0: locate filtering after the union

Each channel combines sales and returns through `UNION ALL`. Its date lookup
and interval filter appear outside that union. The saved plan materializes
union-derived results and accesses the fact tables without a branch-local date
filter. Large intermediate inputs are therefore a plausible bottleneck even
when only a short interval is requested.

Primary-key median: **145.402 s**. Indexed median: **112.735 s**.

### Step 1 — v1: filter each branch before materialization

Add a `date_dim filtered_date` join and the same interval predicate inside
each sales/returns branch. For store sales, the inserted lines are:

```sql
JOIN date_dim filtered_date ON ss_sold_date_sk = filtered_date.d_date_sk
WHERE filtered_date.d_date BETWEEN CAST('1998-08-28' AS DATE)
    AND (CAST('1998-08-28' AS DATE) + INTERVAL 14 DAY)
```

The branch date keys are deliberately different:

| Branch | Date key used to filter that branch |
| --- | --- |
| Store sales | `ss_sold_date_sk` |
| Store returns | `sr_returned_date_sk` |
| Catalog sales | `cs_sold_date_sk` |
| Catalog returns | `cr_returned_date_sk` |
| Web sales | `ws_sold_date_sk` |
| Web returns | `wr_returned_date_sk` |

The original outer date predicates remain. The saved v1 plan places
`filtered_date` inside the union branches; the primary-key plan still scans
fact tables, so the explanation is **less data passed into the union and later
aggregation**, not an invented reduction in full scans. No `ANALYZE` row counts
were saved for Q5, so no exact intermediate-row reduction is claimed.

The repeated primary-key median becomes **11.309 s (12.86× vs v0)**. With all
reference indexes it becomes **10.144 s (11.11×)**. This is the only candidate
version; there are no separately measured store-only/catalog-only/web-only
filter ablations.

### Repeated primary-key results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query5_v0.sql) | 3 | 145.402 | 144.140–159.790 | 1.00× |
| [v1](query5_v1_branchfilters.sql) | 3 | 11.309 | 10.299–14.070 | 12.86× |

### Repeated indexed results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query5_v0.sql) | 3 | 112.735 | 112.385–113.031 | 1.00× |
| [v1](query5_v1_branchfilters.sql) | 3 | 10.144 | 10.143–10.446 | 11.11× |

## Why the rewrite preserves the answer

The most delicate branch is web returns. It still finds the original sale by
`(wr_item_sk, wr_order_number)` through the existing left join. The date filter
uses the **return date**, and no sale-date interval is added to that lookup.
A sale from before 28 August can therefore still contribute a return inside
the reporting interval.

`UNION ALL`, literal zero contributions, NULL handling and the original entity
business-ID grouping remain intact. Those business IDs are not replaced with
surrogate keys: multiple dimension rows can share an ID. The rollup and final
ordering are retained, including the NULL fields identifying subtotals.

The session requires `PIPES_AS_CONCAT`: the baseline's `||` constructs entity
identifiers. This is a correctness prerequisite for both versions, not a query
optimization. The trial runner sets it automatically.

## Compare the returned results

The comparison checks complete ordered values, column names, duplicate
columns, NULLs and result-set boundaries; equal row counts alone are
insufficient. `LIMIT`, where present, remains part of the original query.

| Version | Rows per result set on SF=1 | Full output comparison |
| --- | --- | --- |
| [v0](query5_v0.sql) | 100 | Saved original |
| [v1](query5_v1_branchfilters.sql) | 100 | 6/6 ordinary runs matched the original; timings remain separated by profile |

For a concrete value comparison, the first returned row of result set 1
is shown below. The candidate is `query5_v1_branchfilters.sql`. The complete
outputs, rather than only this example, were compared.

| Output column (position) | Original v0 | Selected v1 |
| --- | --- | --- |
| channel (1) | `NULL` | `NULL` |
| id (2) | `NULL` | `NULL` |
| sales (3) | `114809663.23` | `114809663.23` |
| returns (4) | `2871869.43` | `2871869.43` |
| profit (5) | `-31231945.54` | `-31231945.54` |

The nonempty synthetic fixture returns **10 baseline rows and 10 identical
candidate rows**. It tests both date endpoints, a return from an older sale,
an unmatched return, duplicate store business IDs, NULL measures and rollup rows.
These checks complement the 100 returned SF=1 rows; they do not remove the
original `LIMIT` to claim equivalence of an unbounded output.

## Reproduce the selected comparison

Run from the repository root after following the [setup guide](../../../experiments/README.md#reproduce-on-a-fresh-database).
The example assumes a loaded dedicated `$TPCDS_DB`, SF=1, seed 10, and the 117
reference indexes physically present. `--profile reference` is a label and does
not create indexes. Choose a new session directory for each attempt.

```bash
python3 scripts/build_experiment_jobs.py \
  --queries 5 --profile reference --scale 1 --data-seed 10 --repeats 3 \
  --runs experiments/local/q5_review_reference/runs \
  --output experiments/local/q5_review_reference/jobs.json

python3 scripts/run_query_batch.py \
  --database "$TPCDS_DB" \
  --jobs experiments/local/q5_review_reference/jobs.json \
  --out experiments/local/q5_review_reference/runs

python3 scripts/summarize_experiments.py \
  --runs experiments/local/q5_review_reference/runs \
  --out experiments/local/q5_review_reference/summary
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
| Original output example | `runs/q5_v0_pk_probe/result.json` |
| Selected output example | `runs/q5_v1_pk_r1/result.json` |
| Original plan | `runs/q5_v0_pk_explain/plan_1.json` |
| Branch-filter plan | `runs/q5_v1_pk_explain/plan_1.json` |

Ordinary labels ending in `_r1`, `_r2` and `_r3` contain `run.json`,
`input.sql`, `result.json`, raw `output.xml` and `stderr.txt`. The archived SQL
and SHA-256 hashes identify the version that was actually executed.

The selected `query5_BEST.sql` is an exact copy of the selected source,
not a separately measured implementation. For the final report, retain the
unsuccessful steps, state the configuration beside every timing, and repeat
correctness and performance checks on Hossein's machine and at each scale.
