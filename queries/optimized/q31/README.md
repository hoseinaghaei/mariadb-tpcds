# Query 31 — step-by-step optimization

Selected version: [query31_v2_pivot.sql](query31_v2_pivot.sql).
[query31_BEST.sql](query31_BEST.sql) contains exactly the same SQL.

## What the query must return

For each county, compare web and store sales ratios from Q1 to Q2 and from Q2
to Q3 in **2001**. Return counties where the web ratio exceeds the store ratio
for both transitions, using the original positive-denominator guards. A higher
ratio does not require positive growth: both channels can fall, with web falling
less. The result contains county, year and four ratios, ordered by the web
Q2-to-Q3 ratio. The original returns **44 rows**, with no LIMIT.

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
| [v0](query31_v0.sql) | Reference each channel aggregate three times | Baseline |
| [v1](query31_v1_earlyfilters.sql) | Restrict both aggregates to 2001 and quarters 1–3 | Filter-only attempt |
| [v2](query31_v2_pivot.sql) | Keep those filters and pivot the quarterly totals into one row per county/year | Selected rewrite |

### Step 0 — v0: inspect the six aggregate references

The `ss` and `ws` CTEs each calculate county/year/quarter totals. The outer query
joins three copies of `ss` and three copies of `ws`. The actual saved primary-key
plan executes three full `store_sales` scans and three full `web_sales` scans.
It already pushes individual year/quarter predicates into the derived results.
The costly feature is repeated access, not simply the absence of a WHERE clause
inside the original CTE text.

Primary-key median: **27.572 s**. Indexed median: **46.947 s**.

### Step 1 — v1: make the required period explicit earlier

Add these predicates to both channel CTEs, retaining the original outer query:

```sql
AND d_year = 2001
AND d_qoy IN (1,2,3)
```

The hypothesis is to discard unnecessary groups earlier. This remains valid
because no other year or quarter contributes to the final result. Its primary-key
median is **23.508 s**, or **1.17×** relative to v0. However, its 21.848–28.114 s
range overlaps the original 22.044–31.434 s range. The existing optimizer
pushdown and unchanged six-reference shape give little evidence of a large
independent benefit. There is no indexed v1 timing series.

### Step 2 — v2: pivot existing quarter totals instead of self-joining them

First calculate each channel's quarterly totals once. Then select the three
already-calculated values into columns:

```sql
SELECT ca_county, d_year,
       MAX(CASE WHEN d_qoy = 1 THEN store_sales END) AS q1,
       MAX(CASE WHEN d_qoy = 2 THEN store_sales END) AS q2,
       MAX(CASE WHEN d_qoy = 3 THEN store_sales END) AS q3
FROM ss_quarter
GROUP BY ca_county, d_year
HAVING COUNT(DISTINCT d_qoy) = 3
```

The web channel uses the same structure. Join the resulting two channel rows,
then evaluate the unchanged ratio predicates. `MAX` selects the one existing
quarter total; it does not calculate a maximum over individual sales.

The primary-key median falls from **23.508 s in v1 to 12.009 s in v2**, a
**1.96× ratio of medians** for that development step, and **2.30× vs v0**.
The actual plans provide a direct mechanism check:

| Fact table | v0 full scans | v2 full scans | Actual rows per scan |
| --- | ---: | ---: | ---: |
| `store_sales` | 3 | 1 | 2,879,152 |
| `web_sales` | 3 | 1 | 720,378 |

Those values come from `r_loops` and `r_rows` in the saved `ANALYZE` plans,
not the estimated `rows` field. They exclude dimension lookups and temporary
result processing. Combined fact-row visits fall from **10,798,590 to 3,599,530**.
With reference indexes, v2 also wins against a fresh same-design
baseline: **46.947 to 15.957 s (2.94×)**.

### Repeated primary-key results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query31_v0.sql) | 3 | 27.572 | 22.044–31.434 | 1.00× |
| [v1](query31_v1_earlyfilters.sql) | 3 | 23.508 | 21.848–28.114 | 1.17× |
| [v2](query31_v2_pivot.sql) | 3 | 12.009 | 9.146–12.162 | 2.30× |

### Repeated indexed results

| Version | n | Median (s) | Min–max (s) | Speedup vs same-series v0 |
| --- | ---: | ---: | ---: | ---: |
| [v0](query31_v0.sql) | 3 | 46.947 | 46.644–47.496 | 1.00× |
| [v2](query31_v2_pivot.sql) | 3 | 15.957 | 15.908–15.959 | 2.94× |

## Why the rewrite preserves the answer

- `COUNT(DISTINCT d_qoy)=3` requires all three original quarter groups. Missing
  quarters stay missing rather than becoming zero sales.
- `MAX(CASE...)` selects an already aggregated value without summing it again
  and widening its decimal precision. NULL totals keep their original meaning.
- County/year grouping and the original address joins remain. Multiple addresses
  in one county are aggregated together; a NULL county still fails the final
  ordinary equality join, as in v0.
- The original guarded ratios, four returned ratio expressions and ordering are
  retained. Negative Q3 totals are allowed; no extra positivity rule is added.

## Compare the returned results

The comparison checks complete ordered values, column names, duplicate
columns, NULLs and result-set boundaries; equal row counts alone are
insufficient. `LIMIT`, where present, remains part of the original query.

| Version | Rows per result set on SF=1 | Full output comparison |
| --- | --- | --- |
| [v0](query31_v0.sql) | 44 | Saved original |
| [v1](query31_v1_earlyfilters.sql) | 44 | 3/3 ordinary runs matched the original; timings remain separated by profile |
| [v2](query31_v2_pivot.sql) | 44 | 6/6 ordinary runs matched the original; timings remain separated by profile |

For a concrete value comparison, the first returned row of result set 1
is shown below. The candidate is `query31_v2_pivot.sql`. The complete
outputs, rather than only this example, were compared.

| Output column (position) | Original v0 | Selected v2 |
| --- | --- | --- |
| ca_county (1) | `Seneca County` | `Seneca County` |
| d_year (2) | `2001` | `2001` |
| web_q1_q2_increase (3) | `1.878820` | `1.878820` |
| store_q1_q2_increase (4) | `0.970115` | `0.970115` |
| web_q2_q3_increase (5) | `0.644541` | `0.644541` |
| store_q2_q3_increase (6) | `0.233123` | `0.233123` |

The selected v2 passes a synthetic fixture with **2 baseline rows and 2
identical candidate rows**. It covers a missing quarter, NULL totals and county,
multiple addresses per county, negative Q3 sales, an out-of-year fact and orphan
facts. v1's full-scale repeated comparisons are saved; a separate v1 fixture
was not recorded.

The original primary-key rounds used the same v0/v1/v2 order each time. v1's
small apparent gain is therefore especially weak evidence. Use alternating or
balanced orders when repeating all three on the final machine.

## Reproduce the selected comparison

Run from the repository root after following the [setup guide](../../../experiments/README.md#reproduce-on-a-fresh-database).
The example assumes a loaded dedicated `$TPCDS_DB`, SF=1, seed 10, and the 117
reference indexes physically present. `--profile reference` is a label and does
not create indexes. Choose a new session directory for each attempt.

```bash
python3 scripts/build_experiment_jobs.py \
  --queries 31 --profile reference --scale 1 --data-seed 10 --repeats 3 \
  --runs experiments/local/q31_review_reference/runs \
  --output experiments/local/q31_review_reference/jobs.json

python3 scripts/run_query_batch.py \
  --database "$TPCDS_DB" \
  --jobs experiments/local/q31_review_reference/jobs.json \
  --out experiments/local/q31_review_reference/runs

python3 scripts/summarize_experiments.py \
  --runs experiments/local/q31_review_reference/runs \
  --out experiments/local/q31_review_reference/summary
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
| Original output example | `runs/q31_v0_pk_probe/result.json` |
| Selected output example | `runs/q31_v2_pk_r1/result.json` |
| Original actual plan | `runs/q31_v0_pk_analyze/plan_1.json` |
| Pivot actual plan | `runs/q31_v2_pk_analyze/plan_1.json` |
| Original indexed estimate | `runs/q31_v0_reference_explain/plan_1.json` |
| Pivot indexed estimate | `runs/q31_v2_reference_explain/plan_1.json` |

Ordinary labels ending in `_r1`, `_r2` and `_r3` contain `run.json`,
`input.sql`, `result.json`, raw `output.xml` and `stderr.txt`. The archived SQL
and SHA-256 hashes identify the version that was actually executed.

The selected `query31_BEST.sql` is an exact copy of the selected source,
not a separately measured implementation. For the final report, retain the
unsuccessful steps, state the configuration beside every timing, and repeat
correctness and performance checks on Hossein's machine and at each scale.
