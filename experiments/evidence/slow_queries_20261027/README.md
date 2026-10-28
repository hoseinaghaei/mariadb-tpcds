# Q4/Q67 optimization evidence, 2026-10-27

See [report 27](../../../report/27-query-followup.md) for the experiment and
interpretation. `measurements.csv` and `summary.json` summarize only ordinary
repetitions; probes, metadata, fixtures, EXPLAIN and ANALYZE are excluded.
Speedups use the currently adopted query within the same series/configuration.

`raw_trials.zip` contains the exact SQL inputs, full XML/JSON results,
per-trial metadata, diagnostic plans and serial job manifests. `SHA256SUMS`
identifies the archive. The original local workspace was
`experiments/local/slow_queries_20261027/`; historical job paths refer to that
location. Inspect archived `runs/<label>/input.sql` to identify what executed.
Replaying on another database requires a fresh adopted baseline answer.

List or extract the evidence without connecting to MariaDB:

```bash
python3 -m zipfile -l experiments/evidence/slow_queries_20261027/raw_trials.zip
# Choose a new destination to keep the original evidence intact.
python3 -m zipfile -e experiments/evidence/slow_queries_20261027/raw_trials.zip /tmp/tpcds-followup-evidence
```

Each ordinary `run.json` contains `status: OK`, `strict_result_match: true`,
the unrounded time, SQL hash, result-set row counts, server version, memory
settings and index definitions. Q67's query-local SETs take effect after
the runner's context capture; their unchanged values are present in the
archived input SQL. Actual runtime plans are named `plan_1.json`.

Q4 fixtures return six rows per version; Q67 fixtures return 31. They use
CTEs to shadow table names for a single SELECT, with no database object
creation. Their correctness observations supplement the SQL equivalence
arguments; neither fixtures nor matching one dataset prove all-input
equivalence on their own.
