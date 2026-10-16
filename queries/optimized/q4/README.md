# Query 4 — step-by-step optimization

Selected version: [query4_v2_customerpivot.sql](query4_v2_customerpivot.sql).
[query4_BEST.sql](query4_BEST.sql) contains exactly the same SQL.

## What the query must return

For customers present in store, catalog and web sales in both 2001 and 2002,
compare each channel's second-year/first-year total. Return the customers whose
catalog ratio exceeds both the store and web ratios, with positive first-year
totals. The total uses the original monetary expression; it is not replaced by
a different definition of revenue. Return customer ID, first name, last name
and login in the original order, with the original `LIMIT 100`.

The local original returns **6 rows**. Fewer than 100 is legitimate because the
limit is a maximum, not a required row count.

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
| [v0](query4_v0.sql) | Unchanged original | Baseline |
| [v1](query4_v1_yearfilter.sql) | Restrict each channel to 2001/2002 | Exploratory filter-only attempt |
| [v2](query4_v2_customerpivot.sql) | Aggregate both years together by customer key; join details later | Selected rewrite |

### Step 0 — v0: identify repeated yearly work

The `year_total` CTE groups customer attributes and year for three channels.
The final query references it six times: one first-year and one second-year
copy for each channel. In the saved `EXPLAIN`, this leads to two `store_sales`,
two `catalog_sales` and two `web_sales` table nodes, plus repeated customer
lookups. A CTE name by itself does not guarantee one shared materialization.

The primary-key ordinary baseline median is **99.778 s**. That baseline, rather
than the slower first exploratory execution, is used for the repeated comparison.

### Step 1 — v1: filter the years inside each channel

The only SQL change from v0 is this predicate in each of the three branches:

```sql
AND d_year IN (2001,2002)
```

The hypothesis is that discarding unused years earlier will reduce aggregation
work. It is valid because the final query only requests those two years.
However, the saved v1 plan still has six sales-table nodes: this does not remove
the repeated yearly processing.

The saved exploratory sequence is shown separately because it is **one execution
per version**, with no controlled cache state:

| Exploratory version | Time (s), not a repeated median | Output |
| --- | ---: | --- |
| v0 | 123.880 | 6 rows; saved original |
| v1 | 88.071 | 6 rows; exact match |
| v2 | 12.002 | 6 rows; exact match |

These values come from `q4_v0_pk_probe`, `q4_v1_pk_probe` and
`q4_v2_pk_probe`. v1 has no `_r1`–`_r3` series and no indexed series. Its single
88.071 s must not be placed beside ordinary medians as equivalent evidence.
Retain v1 as an intermediate attempt; its isolated benefit remains unconfirmed.

### Step 2 — v2: replace yearly self-joins with conditional aggregation

For each channel, calculate the two yearly totals as columns in one group.
For example, the store expressions are:

```sql
SUM(CASE WHEN d_year = 2001 THEN
    ((ss_ext_list_price-ss_ext_wholesale_cost-ss_ext_discount_amt)+ss_ext_sales_price)/2
END) AS y1,
SUM(CASE WHEN d_year = 2002 THEN
    ((ss_ext_list_price-ss_ext_wholesale_cost-ss_ext_discount_amt)+ss_ext_sales_price)/2
END) AS y2
```

The grouping key becomes the channel's customer surrogate key, with
`HAVING COUNT(DISTINCT d_year) = 2`. Join the three grouped channel results and
customer details afterward. This keeps descriptive strings out of the large
aggregations. The saved plan has **three sales-table nodes instead of six**;
this is an `EXPLAIN` observation, not a measured row-read count.

The repeated primary-key median falls from **99.778 to 16.942 s (5.89×)**.
With reference indexes it falls from **54.866 to 15.209 s (3.61×)**. v2 is
selected because it has repeated comparisons under both designs, a structural
explanation and correctness checks. The year pivot, narrower grouping and late
customer join were measured together; there is no separate ablation assigning
a precise share of the speedup to each ingredient.

### Repeated primary-key results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query4_v0.sql) | 3 | 99.778 | 75.753–104.080 | 1.00× |
| [v2](query4_v2_customerpivot.sql) | 3 | 16.942 | 11.656–16.978 | 5.89× |

### Repeated indexed results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query4_v0.sql) | 3 | 54.866 | 54.669–55.275 | 1.00× |
| [v2](query4_v2_customerpivot.sql) | 3 | 15.209 | 15.208–15.307 | 3.61× |

## Why the rewrite preserves the answer

- `c_customer_id` must be unique and non-NULL: v0 joins on the business ID while
  v2 joins channel totals on the surrogate key. The check found 100,000 rows,
  100,000 distinct business IDs and no NULL IDs. Run
  [check_customer_identity.sql](check_customer_identity.sql) at every scale and
  after refresh; this condition is a dataset assumption, not a new constraint.
- Both year groups must exist. `COUNT(DISTINCT d_year)=2` preserves that even
  when every monetary expression in one year is NULL.
- Conditional sums have no `ELSE 0`; absent/all-NULL contributions keep their
  original NULL behavior. The original arithmetic and guarded ratio comparisons
  are preserved.
- The final inner customer join still removes orphan customer groups. The four
  returned fields, ordering and limit are unchanged.

## Compare the returned results

The comparison checks complete ordered values, column names, duplicate
columns, NULLs and result-set boundaries; equal row counts alone are
insufficient. `LIMIT`, where present, remains part of the original query.

| Version | Rows per result set on SF=1 | Full output comparison |
| --- | --- | --- |
| [v0](query4_v0.sql) | 6 | Saved original |
| [v1](query4_v1_yearfilter.sql) | 6 | 1/1 exploratory run matched; no repeated timing group |
| [v2](query4_v2_customerpivot.sql) | 6 | 6/6 ordinary runs matched the original; timings remain separated by profile |

For a concrete value comparison, the first returned row of result set 1
is shown below. The candidate is `query4_v2_customerpivot.sql`. The complete
outputs, rather than only this example, were compared.

| Output column (position) | Original v0 | Selected v2 |
| --- | --- | --- |
| customer_id (1) | `AAAAAAAACHEDAAAA` | `AAAAAAAACHEDAAAA` |
| customer_first_name (2) | `Antonio` | `Antonio` |
| customer_last_name (3) | `Wallace` | `Wallace` |
| customer_login (4) | `NULL` | `NULL` |

The selected v2 also passes a nonempty synthetic fixture: **1 baseline row and
1 identical candidate row**. It covers missing years, NULL measures, zero first-year
totals, NULL customer attributes and an orphan customer. v1's saved correctness
evidence is its full-scale exploratory comparison; it has no separate fixture.

## Reproduce the selected comparison

Run from the repository root after following the [setup guide](../../../experiments/README.md#reproduce-on-a-fresh-database).
The example assumes a loaded dedicated `$TPCDS_DB`, SF=1, seed 10, and the 117
reference indexes physically present. `--profile reference` is a label and does
not create indexes. Choose a new session directory for each attempt.

```bash
python3 scripts/build_experiment_jobs.py \
  --queries 4 --profile reference --scale 1 --data-seed 10 --repeats 3 \
  --runs experiments/local/q4_review_reference/runs \
  --output experiments/local/q4_review_reference/jobs.json

python3 scripts/run_query_batch.py \
  --database "$TPCDS_DB" \
  --jobs experiments/local/q4_review_reference/jobs.json \
  --out experiments/local/q4_review_reference/runs

python3 scripts/summarize_experiments.py \
  --runs experiments/local/q4_review_reference/runs \
  --out experiments/local/q4_review_reference/summary
```

This runs discarded warm-ups followed by three alternating v0/v2 rounds.
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
| Original output example | `runs/q4_v0_pk_probe/result.json` |
| Selected output example | `runs/q4_v2_pk_r1/result.json` |
| Original plan | `runs/q4_v0_pk_explain/plan_1.json` |
| Filter-only plan | `runs/q4_v1_pk_explain/plan_1.json` |
| Pivot plan | `runs/q4_v2_pk_explain/plan_1.json` |

Ordinary labels ending in `_r1`, `_r2` and `_r3` contain `run.json`,
`input.sql`, `result.json`, raw `output.xml` and `stderr.txt`. The archived SQL
and SHA-256 hashes identify the version that was actually executed.

The selected `query4_BEST.sql` is an exact copy of the selected source,
not a separately measured implementation. For the final report, retain the
unsuccessful steps, state the configuration beside every timing, and repeat
correctness and performance checks on Hossein's machine and at each scale.
