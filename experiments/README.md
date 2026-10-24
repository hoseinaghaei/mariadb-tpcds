# Riccardo's query experiments: Q4, Q5, Q31, Q39 and Q51

These experiments use the checked-in MariaDB query instances and a dedicated
database. They are a contribution to Part I of the course project, not a complete
TPC-DS implementation or an audited TPC result. The original repository's
measurements belong to its author and must not be presented as this group's runs.

## What each experiment tests

| Query | Main candidate | Reason for the change |
| --- | --- | --- |
| 4 | `query4_v2_customerpivot.sql` | Read each channel once; aggregate both years by customer key; join customer attributes afterward. |
| 5 | `query5_v1_branchfilters.sql` | Filter dates inside all six UNION branches before materializing their rows. |
| 31 | `query31_v2_pivot.sql` | Read each channel once and pivot three quarterly totals instead of self-joining three copies. |
| 39 | `query39_v6_sourcefirst.sql` | Aggregate inventory before dimension lookups and preserve that join order, retaining two independent SELECTs. |
| 51 | `query51_v1_unifieddaily.sql` | Combine daily channel keys once, replacing the repeated full-join emulation while preserving both window operations. |

The per-query folders retain the original `v0` and the unsuccessful candidates.
Use measured results under the same index profile to choose a winner. A profile
name is a label: the runner does not create or change indexes automatically.

Completed local results, raw evidence and the selected SQL hashes are in
[`evidence/riccio_sf1_20261014/`](evidence/riccio_sf1_20261014/). The report chapter
is [`report/riccardo-query-experiments.md`](../report/riccardo-query-experiments.md).
Each query folder now has a `query<N>_BEST.sql` alias containing the selected
candidate exactly. These aliases are locally validated starting points for the
group's final-machine and four-scale experiments.

## Read the optimization history for each query

Each query has its own step-by-step document. Read the original SQL, then follow
the versions in that document: hypothesis, exact change, timing and output
comparison, plan evidence, and the reason to keep or reject it. Version numbers
describe development history; they do not imply that every later version keeps
every earlier change.

| Query document | Versions explained | Important comparison |
| --- | --- | --- |
| [Q4](../queries/optimized/q4/README.md) | v0, v1, v2 | Year filtering versus the two-year/customer-key rewrite; v1 has only a single exploratory execution. |
| [Q5](../queries/optimized/q5/README.md) | v0, v1 | Outer date filtering versus filtering all six union branches, preserving return-date semantics. |
| [Q31](../queries/optimized/q31/README.md) | v0, v1, v2 | Filter-only attempt versus quarter pivot; actual fact-table scans fall from six to two. |
| [Q39](../queries/optimized/q39/README.md) | v0 through v6 | Shared results, late joins, independent statements and two alternative corrections for the indexed plan. |
| [Q51](../queries/optimized/q51/README.md) | v0, v1 | Repeated outer-join emulation versus unified daily keys, with presence flags and both windows preserved. |

The per-query tables distinguish primary-key and indexed results, ordinary
repetitions and exploratory executions, and actual ANALYZE observations and
EXPLAIN estimates. Every document compares returned values as well as time.
The report chapter includes a shorter all-version table for final-report assembly.

## What the scripts do

The normal sequence is preparation, data generation/loading, job creation,
serial execution, then summarization. SQL variants remain ordinary `.sql` files;
the Python tools organize and record their execution.

| Script | What you provide | What it produces or does |
| --- | --- | --- |
| [prepare_experiments.py](../scripts/prepare_experiments.py) | Dedicated DB name, scale and seed; optional repository location | Creates isolated schema/load/index SQL, table-count SQL and setup metadata. Does not connect to MariaDB. |
| [build_experiment_jobs.py](../scripts/build_experiment_jobs.py) | Query numbers, profile label, runs directory and new job-file location | Writes the execution order: original/candidate warm-ups and repeated alternating rounds. Uses the selected candidate map at the top of the script. Does not run SQL. |
| [run_query_batch.py](../scripts/run_query_batch.py) | Job JSON, DB name and output directory | Calls `query_trial.py` once per job, serially; stops on the first failure. |
| [query_trial.py](../scripts/query_trial.py) | SQL file, DB, label/profile and optional saved original result | Records metadata, executes the SQL, saves results/timing and optionally checks exact equality. EXPLAIN/ANALYZE modes capture a diagnostic instead of an ordinary timing. |
| [summarize_experiments.py](../scripts/summarize_experiments.py) | Completed runs directory | Writes CSV/JSON with medians, ranges and same-configuration speedups for ordinary `_rN` repetitions. |
| [build_semantic_fixture.py](../scripts/build_semantic_fixture.py) | Query number, baseline SQL and candidate SQL | Builds a small temporary-table SQL fixture that executes both versions; running and comparing its outputs is a separate step. |
| [build_ri_check.py](../scripts/build_ri_check.py) | Output filename | Derives read-only orphan-check SQL from the declared foreign keys; it does not add constraints or change indexes. |

The four `test_*.py` files check helper behavior such as XML parsing, batch
failure handling, summary grouping and relationship generation. They are not
substitutes for executing SQL and checking its results.

For one ordinary trial, metadata collection happens before the timer. The timed
client then executes the session preamble and complete SQL file and transfers
the output. Read `run.json` for status, seconds, row counts and
`strict_result_match`; read `result.json` for the actual returned values. A first
baseline without `--expect` has no strict-match flag because it establishes the
reference. A profile/scale/seed argument labels a run; it does not change the
physical indexes or regenerate the warehouse. Check the actual setup and
`dbgen_version` before using those labels.

## Reproduce on a fresh database

Requirements: the toolkit built for the host OS, Python 3, and a local MariaDB
server/client. MariaDB 10.11.14 and Python 3.12 were used for the Linux experiments.
The client must be able to connect without an interactive password prompt, using
your normal MariaDB client configuration or local socket authentication. Keep
credentials outside the repository and submission archive.

Run commands from the repository root. Choose a new database name; the generated
schema deliberately refuses to recreate an existing database.

The preparation script locates the checkout from its own file; `--repo` is
optional. Generated loader paths and `setup.json` directories are relative to
the repository root, including after moving or renaming the checkout. Start the
MariaDB client from that root when loading: SQL file location does not determine
the base directory for `LOAD DATA LOCAL INFILE`.

```bash
export TPCDS_DB=tpcds_student_sf1
python3 scripts/prepare_experiments.py \
  --database "$TPCDS_DB" --scale 1 --seed 10
```

Generate data from the toolkit directory so it can find `tpcds.idx`. If that
dataset already exists, reuse it after checking `dbgen_version.dat`; do not
overwrite it during measurements.

```bash
cd DSGen-software-code-4.0.0/tools
./dsdgen -SCALE 1 -RNGSEED 10 -DIR ../data/sf1_seed10
cd ../..

mariadb < "experiments/local/${TPCDS_DB}_sql/01_schema.sql"
mariadb --local-infile=1 --show-warnings \
  < "experiments/local/${TPCDS_DB}_sql/04_load_data.sql" \
  > experiments/local/load.log 2>&1
mariadb "$TPCDS_DB" \
  < "experiments/local/${TPCDS_DB}_sql/table_counts.sql" \
  > experiments/local/loaded_counts.tsv
```

Read the entire load log, check every table's row count against its generated
`.dat` file, and confirm the generation arguments in `dbgen_version`. The client
and server must both permit LOCAL INFILE for this loader. If setup fails, inspect
the error before rerunning anything that could append duplicate rows. Run
`ANALYZE TABLE` for the loaded tables outside the timed workload. Record its log.

Record the actual database version, SQL mode, buffer pool size, temporary-table
limits, optimizer switches and index definitions. Record CPU, RAM, OS, free disk,
background workloads and whether the client and server share a machine. On Linux
use `lscpu`, `free -h`, `uname -a` and `df -h`; on macOS use `sysctl -n hw.model`,
`sysctl -n hw.memsize`, `uname -a` and `df -h`. The trial runner records database
settings and indexes for every run; hardware information remains part of the
experiment's environment record.

## Run controlled comparisons

Create a new output directory name for every experiment session. The job builder
creates one discarded baseline warm-up, one checked candidate warm-up, and three
alternating baseline/candidate rounds per query. `--queries 31` selects just Q31.

New job entries declare `"path_base": "manifest"`: their `file` and `expect`
paths are relative to the job JSON's directory. Move the checkout with its
experiment directory to keep these references valid. Existing job lists without
`path_base` retain repository-relative paths; explicit absolute paths are still
accepted for manually configured external files. Command-line paths such as
`--jobs`, `--runs` and `--out` are relative to the shell's working directory.
The trial runner's default output directory is inside the checkout.

```bash
python3 scripts/build_experiment_jobs.py \
  --runs experiments/local/my_session/runs \
  --output experiments/local/my_session/jobs_pk.json \
  --profile pk --scale 1 --data-seed 10 --repeats 3

python3 scripts/run_query_batch.py \
  --database "$TPCDS_DB" \
  --jobs experiments/local/my_session/jobs_pk.json \
  --out experiments/local/my_session/runs

python3 scripts/summarize_experiments.py \
  --runs experiments/local/my_session/runs \
  --out experiments/local/my_session/summary
```

The batch runs serially and stops on its first failure. Each trial directory must
be new; rerunning the same label refuses to overwrite evidence. To resume, create
a manifest containing only the uncompleted jobs after addressing the failure.
Do not rerun a failed trial under the same label.

Each run sets `IGNORE_SPACE` and `PIPES_AS_CONCAT`, disables the query cache and
uses a server timeout of 600 seconds per statement. Q5 requires `PIPES_AS_CONCAT`
because `||` expresses string concatenation. The timing covers a fresh client
connection, session setup, statement execution and complete result transfer;
metadata collection is outside the timed interval. Q39 is timed as a complete
two-result script. Its alternative `v3` shares a temporary table: creation,
population, both SELECTs and cleanup are all timed. That sharing assumes unchanged
data between the two outputs; `v4` preserves the original independent statement
boundaries. The selected `v6` additionally keeps each grouped inventory result
before its dimension lookups with STRAIGHT_JOIN. This avoids the bad secondary
index paths found in the indexed experiment.

The comparison preserves result-set boundaries, column names (including repeated
names), row order, NULLs, empty strings and the complete numeric text returned by
MariaDB. It does not round values to two decimal places. Any difference is a
failed trial. Empty-result equality alone is weak evidence; the synthetic fixtures
below deliberately produce nonempty results. These checks establish equivalence
for tested cases, not official Appendix B qualification.

Only ordinary runs with labels ending in `_r1`, `_r2`, etc. contribute to
`measurements.csv`. Warm-ups, probes, plans and fixtures are excluded. Summaries
keep different SQL hashes and recorded configurations separate. Compare medians
within the same profile, scale, seed and configuration; retain the min/max and
raw trials to show variability. Three repetitions provide preliminary evidence;
increase this for the final report if variability obscures a conclusion.

The procedure uses warm-ups and no cache reset. It does not establish a controlled
cold-cache state or guarantee that all relevant data remains in memory. A change
of hardware, memory settings, index definitions or query parameters is a new
experiment and needs new baseline measurements.

## Compare an intermediate version

The job builder selects Q4 v2, Q5 v1, Q31 v2, Q39 v6 and Q51 v1. It does not
automatically measure every retained alternative. For a direct correctness
check of, for example, Q31 v1 against v0, use a new output directory:

```bash
export TPCDS_REVIEW_DIR=experiments/local/q31_v1_reference_check

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q31/query31_v0.sql \
  --label q31_v0_reference_check --profile reference --scale 1 --data-seed 10 \
  --out "$TPCDS_REVIEW_DIR"

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q31/query31_v1_earlyfilters.sql \
  --label q31_v1_reference_check --profile reference --scale 1 --data-seed 10 \
  --expect "$TPCDS_REVIEW_DIR/q31_v0_reference_check/result.json" \
  --out "$TPCDS_REVIEW_DIR"
```

The example assumes the reference indexes actually exist. Require status `OK`
and `strict_result_match: true` in the candidate's `run.json`. These `_check`
labels deliberately stay out of the timing summary: one correctness execution
per version is not a repeated performance comparison.

For a repeated comparison of this intermediate version:

1. Generate a new Q31 job file with `build_experiment_jobs.py`, as in the
   controlled-comparison section, choosing a new runs directory and
   `--queries 31 --repeats 3`.
2. In that new JSON, change every candidate `file` from
   `query31_v2_pivot.sql` to `query31_v1_earlyfilters.sql`, and every candidate
   `label` prefix from `q31_v2_` to `q31_v1_`. Keep the original v0 jobs and their
   `expect` references. This retains fresh warm-ups and three alternating rounds.
3. Run the batch and summarizer. Review the archived SQL hashes, exact-result
   flags and actual configuration before comparing medians. On another scale,
   use the correct data and scale/seed labels for both versions.

The same approach works for other saved alternatives. For Q39, keep the complete
two-result script as the timed file; temporary-table setup and cleanup belong
inside the timed interval for v2/v3. Use fresh controls for a new series rather
than borrowing a median from an earlier configuration or execution phase.

## Inspect the committed evidence without a database

You can review the old experiments without running any queries. Extract the
committed archive into the ignored local directory, keeping the archive intact:

```bash
python3 -m zipfile -e \
  experiments/evidence/riccio_sf1_20261014/raw_trials.zip \
  experiments/local/evidence_20261014
```

For example, compare all Q31 output values from one original/candidate pair:

```bash
python3 - <<'PY'
import json
from pathlib import Path

runs = Path("experiments/local/evidence_20261014/runs")
original = json.loads((runs / "q31_v0_pk_r1/result.json").read_text())
candidate = json.loads((runs / "q31_v2_pk_r1/result.json").read_text())
print("Original rows:", [len(s["rows"]) for s in original])
print("Candidate rows:", [len(s["rows"]) for s in candidate])
assert original == candidate, "Returned values differ"
print("All ordered result sets, column names and values match")
PY
```

Each query document names the useful archive members for its plans and outputs.
`run.json` records each individual timing; `input.sql` identifies the SQL that
was executed; `plan_1.json` contains a diagnostic plan where one was captured.
Q39's two result sets must remain separate during comparison. XML is also saved
as `output.xml` for checking the parser's source representation.

The retained timing groups and statistics are in the committed
[`measurements.csv`](evidence/riccio_sf1_20261014/measurements.csv). Exploratory
probes, fixtures and diagnostics are in the raw archive but excluded from those
medians. The archive preserves the 14 October machine paths as historical
metadata; reproduce new work with the current portable scripts and new sessions.

## Test the standard indexes separately

Finish the primary-key measurements before creating secondary indexes. The
generated script below targets your dedicated database; the original
`sql/05_indexes.sql` contains `USE tpcds` and should not be run against another
database unchanged.

```bash
mariadb "$TPCDS_DB" \
  < "experiments/local/${TPCDS_DB}_sql/05_indexes.sql" \
  > experiments/local/reference_indexes.log 2>&1
```

Verify that all 117 secondary indexes exist, update statistics outside timings,
then build another manifest using `--profile reference`. Use the same dataset,
parameters, settings and serial timing protocol. Check results against both the
same-profile baseline and the saved original results. If adding indexes makes a
query slower, explain the actual plan before adding more indexes or hints. Record
index storage and build time as costs, not just query runtime. Additional covering
indexes constitute a third profile and need their own baselines.

## Inspect plans without mixing them into timings

```bash
python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file queries/optimized/q31/query31_v2_pivot.sql \
  --label q31_v2_pk_explain --profile pk --mode explain \
  --out experiments/local/my_session/runs
```

Use `--mode analyze` to execute the query and capture actual rows, loops and time
in `plan_1.json`. ANALYZE executes the query; EXPLAIN estimates a plan. Run both
outside ordinary repetitions. For the original Q39 use `query39a_v0.sql` and
`query39b_v0.sql` separately. For a temporary-table candidate, analyze the SELECT
that populates its temporary table separately; the ordinary trial still times
the complete script.

Check how many fact-table nodes execute, how many rows each node reads and how
many loops it performs. Estimated `rows` are not actual row counts. For actual
plans, a node's `r_rows` is an average per loop, so interpret it together with
`r_loops`. Distinguish a repeated materialization from an index lookup into a
materialized result.

## Check difficult cases using temporary tables

`build_semantic_fixture.py` creates a SQL file without accessing MariaDB. Its
temporary tables shadow permanent names only for that client connection; both
versions run on the same small input, and disconnecting removes the tables.

```bash
python3 scripts/build_semantic_fixture.py \
  --query 31 \
  --baseline queries/optimized/q31/query31_v0.sql \
  --variant queries/optimized/q31/query31_v2_pivot.sql \
  --output experiments/local/my_session/fixtures/q31.sql

python3 scripts/query_trial.py \
  --database "$TPCDS_DB" \
  --file experiments/local/my_session/fixtures/q31.sql \
  --label q31_fixture --profile semantic_fixture \
  --out experiments/local/my_session/runs
```

Compare the first half of `result.json` with the second half, preserving the
result-set order. Q39 has two baseline sets followed by two candidate sets;
the others have one followed by one. Require the baseline row counts specified
in the fixture's JSON manifest as well as exact equality. Covered cases include
missing periods, zero/NULL denominators, NULL totals, duplicate dimension business
IDs, orphan facts, date endpoints, older web sales linked to current returns,
negative increments and channel-only dates.

Q4's surrogate-key rewrite requires unique `c_customer_id`. Run
`queries/optimized/q4/check_customer_identity.sql` at each scale and after data
refresh. If this condition fails, use the original query or develop a rewrite
that preserves its business-ID grouping. The other candidates preserve their
original predicates and rely on the schema's primary keys and NOT NULL dates.

## What you can finish independently

- Keep this work on your own branch and database; retain original queries,
  rejected candidates and raw evidence.
- Reproduce correctness checks, capture plans, and draft the five optimization
  sections of the report with diagrams/tables derived from your own results.
- Prepare reproducible setup and benchmark commands, an environment description,
  timing CSVs and a small experiment bundle without generated data or credentials.
- Run a pilot at another scale if local resources permit, recording actual data
  size and resource consumption. Label it as a pilot until the group chooses the
  common scales and final measurement machine.
- Review the loader, all-query runner, row counts and referential-integrity checks
  for reproducibility problems; record issues for the shared implementation.

Final measurements are planned on Hossein's computer, following the 15 October
group discussion. Record its actual CPU, RAM, OS, free disk, MariaDB version and
settings before running. The group still needs to agree on four scales, the DB
configuration, common physical design, report ownership and a release commit.
Confirm the lecturer's expectations for refresh operations, concurrent streams
and the benchmark metrics. Query optimization alone does not complete Part I.

## Finish the course submission

For each agreed scale, generate the full dataset with recorded generator
arguments. Do not approximate a smaller scale by deleting arbitrary fact rows.
The course's normalized ratios (for example 0.1/0.2/0.5/1.0) are distinct from
the generator's integer `-SCALE` argument; report both. Choose the largest feasible
scale by measuring disk, RAM, loading time and runtime with headroom for indexes
and temporary data. Four feasible integer generator scales need not match the
example ratios exactly; explain the chosen mapping.

Measure all 99 adapted queries on the agreed machine, report errors/timeouts and
correctness checks, then compare these five optimizations under controlled
profiles. SQL here embeds the checked-in query parameters; if the group changes
dsqgen parameters, change both baseline and candidate and repeat validation.
Add the lecturer-required refresh/concurrency workload once its scope is known.

Part I is due **1 November 2026**. Submit a PDF describing data generation,
schema/load validation, environment, four scales, measurement protocol, results,
these optimizations and limitations. Submit a ZIP containing the toolkit/code,
schema/load/benchmark scripts, SQL variants, configuration, environment/results
evidence and exact reproduction instructions. Preserve the toolkit's license.
Regenerate bulky data through instructions instead of including database files.
Test the ZIP from a fresh directory before submission. Part II, TPC-DI, remains
a separate implementation and report due **24 December 2026**.
