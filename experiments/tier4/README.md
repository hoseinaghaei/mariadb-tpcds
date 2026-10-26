# Tier 4 — learning and experiment workflow

Proposed allocation: **Q82, Q37, Q65, Q70 and Q87**, in that learning order.
These are all in [Tier 4](../../queries/tiers/04_slow.sql) and outside Aysha's
reported allocation of Q43, Q27, Q35, Q38 and Q54. No allocation message has been
sent automatically. Share your five numbers with the group to avoid overlap.

**Current status:** unchanged v0 copies and reading/experiment plans are ready.
No Tier 4 candidate has been selected, timed or validated. No BEST files or
speedups are claimed. The old tier timings belong to the repository author's
machine and are only selection context.

| Order | Query / reading plan | First hypothesis | Skill to practise |
| --- | --- | --- | --- |
| 1 | [Q82](../../queries/optimized/q82/README.md) | Replace a sales join used only for existence | Recognize join multiplication hidden by GROUP BY |
| 2 | [Q37](../../queries/optimized/q37/README.md) | Apply that reasoning to catalog sales | Transfer a technique without changing the query parameters |
| 3 | [Q65](../../queries/optimized/q65/README.md) | Compute store/item revenue once and use a window average | Identify aggregation grain and preserve the average's population |
| 4 | [Q70](../../queries/optimized/q70/README.md) | Remove the redundant inner state-ranking membership test | Prove a simplification while preserving NULLs, ROLLUP and the outer RANK |
| 5 | [Q87](../../queries/optimized/q87/README.md) | Compare native EXCEPT with simpler deduplication and anti-existence | Preserve set keys, duplicates and NULL equality |

Q82 and Q37 are deliberately similar. Start with the short query, understand
why its rewrite is valid, then apply it independently to the other channel.
Q87 is last because the apparently simple COUNT hides more difficult semantics.

## Read a query before editing it

1. Read the final SELECT, ORDER BY and LIMIT. Write one sentence describing the
   returned answer, including whether it returns rows, subtotals or a count.
2. Identify the grain at each stage: a sale, an inventory observation, a
   store/item total, a county subtotal, or a distinct name/date combination.
   GROUP BY and DISTINCT change that grain.
3. Separate equality joins from filters. Record the exact date, quantity, price
   and manufacturer conditions; BETWEEN includes both endpoints. A condition
   on inventory dates does not automatically constrain sale dates.
4. Ask whether each joined table contributes values, filters rows, or only
   establishes that a related row exists. Multiplicity can be irrelevant to
   Q82/Q37's duplicate elimination but essential to a SUM in another query.
5. Look for repeated subqueries/aggregates and windows. A CTE name is not a
   promise that MariaDB computes its result only once.
6. List semantic traps before changing anything: NULLs, duplicates, orphan keys,
   arithmetic precision, ordering, ties and missing groups. The per-query plans
   give concrete cases.
7. Write a testable hypothesis: “This change should reduce X work because Y;
   EXPLAIN/ANALYZE should show Z.” Make one conceptual change per version.

## Start from the existing setup

Use the already loaded dedicated SF=1/seed-10 database for local experiments.
Starting a new query does not require generating or reloading the warehouse.
For a new machine/database, follow the [existing setup guide](../README.md#reproduce-on-a-fresh-database).

Run commands from the repository root. The examples below assume the 117
reference indexes are actually present; change the profile name if the physical
configuration differs. Read the metadata recorded by the runner and record the
actual machine, server version, scale, seed and settings. The flags label a run;
they do not change the dataset or install indexes.

```bash
export TPCDS_DB=tpcds_riccio_sf1
export TPCDS_PROFILE=reference
export TPCDS_SESSION="experiments/local/tier4/q82_v1_${TPCDS_PROFILE}_attempt01"
export TPCDS_RUNS="$TPCDS_SESSION/runs"
```

Use your own loaded dedicated database name if different. Choose a new session
name for another attempt; the tools refuse to overwrite run directories or job
files. Keep v0 immutable. After a version has repeated measurements, make a new
version for subsequent changes so the source and evidence remain identifiable.

The working tree started on the earlier query branch. Put this new work on a
separate Tier 4 branch before pushing. If the previous PR is still open, choose
its branch as the base for a stacked PR, or wait for it to merge and branch from
updated main. Avoid presenting the previous commits as new Tier 4 changes.

## Establish an original result and inspect the plan

The five v0 files are already byte-for-byte copies of their originals. For Q82:

```bash
cmp queries/mariadb/query82.sql queries/optimized/q82/query82_v0.sql

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q82/query82_v0.sql \
  --label "q82_v0_${TPCDS_PROFILE}_probe" --profile "$TPCDS_PROFILE" \
  --scale 1 --data-seed 10 --out "$TPCDS_RUNS"

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q82/query82_v0.sql \
  --label "q82_v0_${TPCDS_PROFILE}_explain" --profile "$TPCDS_PROFILE" \
  --mode explain --out "$TPCDS_RUNS"

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q82/query82_v0.sql \
  --label "q82_v0_${TPCDS_PROFILE}_analyze" --profile "$TPCDS_PROFILE" \
  --mode analyze --out "$TPCDS_RUNS"
```

Open `result.json` for values and `plan_1.json` for each diagnostic. EXPLAIN gives
estimates; ANALYZE executes the query and records actual behavior. Neither
diagnostic is an ordinary timing repetition.

Look for fact-table nodes, full scans (`ALL`), the chosen `key`, repeated
materializations, and where selective filters are applied. In actual plans,
`r_rows` is an average per loop: interpret it with `r_loops` and calculate their
product when estimating total rows visited. Fewer lines of SQL or a different
join spelling alone do not establish less work. See the
[ANALYZE FORMAT=JSON reference](https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/analyze-and-explain-statements/analyze-format-json)
for the meanings of its runtime fields.

## Write and check a first candidate

For Q82, use the sales-EXISTS hint in its reading plan:

```bash
cp -n queries/optimized/q82/query82_v0.sql \
  queries/optimized/q82/query82_v1_sales_exists.sql
```

Edit that new file. Replace only the store_sales join with EXISTS; keep the
inventory/date joins, literals, GROUP BY, output fields and ordering. The copy
command creates a starting point, not an optimized implementation. Inspect your
diff before running it. Preserve output column names/aliases as well as values.

```bash
git diff --no-index -- \
  queries/optimized/q82/query82_v0.sql \
  queries/optimized/q82/query82_v1_sales_exists.sql

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q82/query82_v1_sales_exists.sql \
  --label "q82_v1_${TPCDS_PROFILE}_probe" --profile "$TPCDS_PROFILE" \
  --expect "$TPCDS_RUNS/q82_v0_${TPCDS_PROFILE}_probe/result.json" \
  --scale 1 --data-seed 10 --out "$TPCDS_RUNS"
```

`git diff --no-index` returns 1 when it finds differences; that is expected.
The candidate trial must have status `OK` and `strict_result_match: true`.
Any mismatch needs investigation before performance claims. Compare complete
ordered outputs, not rounded numbers or only row counts. The historical
`VALUES_DIFF`/`ROWS_DIFF` statuses in `queries/results/` concern comparisons with
published answer sets; they are separate from comparing your candidate with the
original on the same data. Use the experiment runner for this work.

If a strict mismatch comes only from order, inspect tied ORDER BY keys and the
LIMIT boundary before deciding whether the rewrite is wrong. Q82/Q37 order by
item ID without ordering all projected attributes. Use separate diagnostic
copies to compare complete row multisets while preserving duplicates and NULLs.
Do not silently weaken the benchmark checker; document any ordering policy
agreed for both versions. For Q87, also compare the underlying member sets,
because equal scalar counts alone can hide different members.

## Test a nonempty fixture

The older `build_semantic_fixture.py` supports the earlier five queries, not
these new ones. For Q82, a small [temporary-table setup](../../queries/optimized/q82/fixture_setup.sql)
is provided. It covers join multiplication, duplicate item attributes, inclusive
bounds, absent facts, NULLs and an orphan date. The expected original output is
**4 rows: A, B, C and K**. This expected result has not yet been verified on
MariaDB; verify it before using the fixture as evidence.

After writing v1, combine setup and both SELECTs into one file/session:

```bash
mkdir -p "$TPCDS_SESSION/fixtures"
cat queries/optimized/q82/fixture_setup.sql \
  queries/optimized/q82/query82_v0.sql \
  queries/optimized/q82/query82_v1_sales_exists.sql \
  > "$TPCDS_SESSION/fixtures/q82_v0_v1.sql"

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file "$TPCDS_SESSION/fixtures/q82_v0_v1.sql" \
  --label q82_v1_semantic_fixture --profile semantic_fixture \
  --out "$TPCDS_RUNS"

python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["TPCDS_RUNS"]) / "q82_v1_semantic_fixture/result.json"
sets = json.loads(path.read_text())
assert [len(s["rows"]) for s in sets] == [4, 4], "Unexpected original/candidate fixture size"
assert sets[0] == sets[1], "Fixture answers differ"
print("Both nonempty fixture answers match exactly")
PY
```

Temporary tables shadow permanent names for that connection only. The test does
not alter the loaded warehouse. Fixture setup, queries and cleanup are not
performance evidence. Adapt the cases in each query plan for its own fixture;
do not reuse Q82's literal inputs unchanged for Q37. Add a new fixture label for
another version and retain the old artifact.

## Measure ordinary repetitions

Once the candidate passes the result checks, create a job manifest. The new
`--variants` option discovers one file per label, such as `query82_v1.sql` or
`query82_v1_sales_exists.sql`, in that query's folder. It requires v0 first and
rejects missing or ambiguous versions. No candidate file is selected by default
for the new Tier 4 queries.

```bash
python3 scripts/build_experiment_jobs.py \
  --queries 82 --variants v0,v1 \
  --profile "$TPCDS_PROFILE" --scale 1 --data-seed 10 --repeats 3 \
  --runs "$TPCDS_RUNS" --output "$TPCDS_SESSION/jobs.json"

python3 scripts/run_query_batch.py \
  --database "$TPCDS_DB" \
  --jobs "$TPCDS_SESSION/jobs.json" --out "$TPCDS_RUNS"

python3 scripts/summarize_experiments.py \
  --runs "$TPCDS_RUNS" --out "$TPCDS_SESSION/summary"
```

The eight jobs are v0/v1 warm-ups followed by rounds v0–v1, v1–v0, v0–v1.
Each ordinary execution checks against the fresh original warm-up. Run serially
on unchanged data with the same indexes/settings and a quiet machine. Plans,
probes and fixtures have different labels and are excluded from the summary.
Three repetitions give a preliminary comparison; retain the individual times
and investigate variability rather than reporting only the fastest execution.

Read `summary/measurements.csv`: require three repetitions and exact matches
for the compared groups. Calculate speedup as original median / candidate
median under the same configuration. Values below 1 mean a slower candidate.
The timer includes connection, session setup, SQL and complete result transfer;
metadata collection is outside it. This uses warm-ups without a controlled
cold-cache reset, and does not prove all data stayed in memory.

For v2, create a new SQL file and session, then use `--variants v0,v1,v2`.
After the three warm-ups, three-version order rotates v0–v1–v2, v1–v2–v0,
v2–v0–v1. This exposes the incremental change and avoids always placing one
version first. For more/fewer repetitions the positional balance may differ.
Keep v0 controls in each new configuration or series.

For the other queries change the query number and file/label names. Once all
five have v1 files, `--queries 37,65,70,82,87 --variants v0,v1` builds a serial
batch for all five. It checks every source before writing the job file. The
earlier five-query default selections remain unchanged when `--variants` is
omitted. Filenames must use unique version labels; two different v1 files are
ambiguous, so name the next experiment v2.

## Separate SQL and index experiments

Start with the existing reference indexes. If the SQL rewrite is correct but
still expensive, use its actual plan to choose one index experiment. Inspect
existing definitions first, including optimizer indexes that may already exist.
Use a dedicated local database; keep new indexes in separate scripts targeting
that database rather than changing the group's common profile silently.

| SQL version | Reference indexes | Reference + candidate index |
| --- | --- | --- |
| v0 | Fresh original repetitions | Fresh original repetitions |
| Candidate | Fresh candidate repetitions | Fresh candidate repetitions |

This separates the index's benefit from the SQL rewrite and their interaction.
Use different profile/session names; retain index definitions, build time and
storage. If an index effect is surprising, use a visible/ignored/visible control
sequence where supported, preserving the actual configuration in every run.
Final adoption requires checking effects on the group's other queries.

## Document each step as you work

The five query READMEs already contain a version log and correctness-case list.
Before running a new version, add the exact change and predicted plan effect.
Afterward, add:

1. The source filename and parent version. A branch alternative is not always
   a cumulative improvement over the preceding version number.
2. Data scale/seed, machine/server/configuration, physical index profile and run
   labels. Use actual settings, not only labels.
3. Result-set and row counts, exact comparison outcome, nonempty fixture cases
   and concrete matching values. For Q87, record the count value and member-set
   check, not merely “one output row”.
4. Individual times, n, median, min–max and speedup relative to the original
   under that same configuration. Keep primary-key/indexed and scale results
   separate. Record failed trials and explain exclusions.
5. Plan evidence: actual reads/loops where recorded, materializations, selected
   indexes, or estimates clearly labeled as estimates. Distinguish what the
   SQL suggests from what the plan actually demonstrates.
6. A decision: keep, reject, or inconclusive, with the reason. A shorter query
   or correct rewrite need not be faster.

The existing [Q31 documentation](../../queries/optimized/q31/README.md) is a
completed example. Q39 demonstrates why failed attempts and profile-specific
corrections belong in the report. Copy its structure, not its numbers.

Only after validation choose a BEST file: copy the exact winning SQL, preserve
its source/version hash and leave v0 intact. If no candidate wins, document
that outcome instead of claiming an improvement. Save a new dated evidence
directory with CSV/JSON summaries, raw trials/outputs, plans and a short README.
Integrate the findings into the report as a new experiment series.

Final measurements belong on Hossein's machine and all four agreed scales.
Changing `--scale` alone does not generate/load a different warehouse. Confirm
the actual dataset for each run and repeat correctness at each scale.

## Technical references

- [EXISTS semantics](https://mariadb.com/docs/server/reference/sql-statements/data-manipulation/selecting-data/subqueries/subqueries-and-exists)
- [AVG and window use](https://mariadb.com/docs/server/reference/sql-functions/aggregate-functions/avg)
- [RANK partitions and ties](https://mariadb.com/docs/server/reference/sql-functions/special-functions/window-functions/rank)
- [EXCEPT distinct set difference](https://mariadb.com/docs/server/reference/sql-statements/data-manipulation/selecting-data/set-operations/except)
- [NULL-safe equality](https://mariadb.com/docs/server/reference/sql-structure/operators/comparison-operators/null-safe-equal)
