# TPC-DS on MariaDB

# THE TPC SOFTWARE IS AVAILABLE WITHOUT CHARGE FROM TPC.

Running the complete **TPC-DS v4.0.0** benchmark schema and all **99 queries**
on **MariaDB 13.0.2** (Apple Silicon, macOS).

**Current course work:** the headline results below describe the original
repository author's environment. Riccardo's independent experiments use MariaDB
10.11.14 on Linux, SF=1 and data seed 10. See
[`experiments/README.md`](experiments/README.md) for the isolated workflow,
query candidates, measurement protocol and remaining submission work.

> **Performance results in this repository are NOT comparable to TPC Benchmark
> Results.** They were not audited, not produced at a publishable scale factor,
> and do not meet the requirements of any official TPC Benchmark Standard. They
> are published as a research/engineering exercise under clause 4.c(3) of the
> TPC End User License Agreement (`DSGen-software-code-4.0.0/EULA.txt`).

---

## Reproducing the results — one command

Everything runs in a Linux container; the repository is mounted read-only, so
a run cannot modify it. Results land in `./results/`.

```sh
./reproduce.sh smoke      # low-memory setup/execution check: 1G pool, four queries
./reproduce.sh            # quick: SF=1, 8G pool, 40 selected queries
./reproduce.sh full       # SF=4, 8G pool, 40 selected queries
```

The same commands can be rerun against existing results and data volumes.
Before a new query run, its previous results and log are moved to
`results/.history/<tag>/<timestamp>/` (under `results/smoke/` for smoke).
The latest results keep their usual paths, such as `results/tuned/`;
no new output-directory option is required. Archives consume disk space and
are excluded from the scaling report's inputs.

`smoke` is intended for checking the installation on a smaller machine. It uses
smaller caches and execution buffers, skips secondary-index creation, and writes
to `results/smoke/` with its own `tpcds-smoke-data` volume. Its first run still
generates and loads the **full SF=1 dataset**. It is not a qualification test or
a reproduction of the published performance results. Peak memory and first-run
time for this new profile have not yet been measured with Docker.

`quick` and `full` keep the reference memory settings. The script checks a
memory estimate before building the image; their defaults need roughly 12 GiB
of Docker capacity. Overrides such as `BUFFER_POOL=4G` now apply to both the
check and container, but reducing the pool alone leaves the other large buffers
in place. See the [profile and resource guide](docker/README.md#resource-notes).

A default run measures **both** of this project's contributions together: the
tuned server settings *and* the team's optimized queries (`queries/tuned/`,
33 of the 40 tier-4/5 queries rewritten). Two knobs separate them —
`QUERYSET` picks the SQL, `TUNED` picks the server settings:

```sh
./reproduce.sh quick QUERYSET=tier45 TUNED=both    # server tuning alone
./reproduce.sh quick QUERYSET=tuned  TUNED=tuned   # + the query rewrites
```

Full detail in [`docker/README.md`](docker/README.md). Script regression tests
use a fake Docker command and need no daemon or database:

```sh
python3 -B -m unittest discover -s scripts -p test_reproduce.py
```

For all **99** queries using the adopted versions where available, select
`QUERYSET=all-tuned`. A separate result directory is optional; the default remains the
historical 40-query workload:

```sh
./reproduce.sh full BUFFER_POOL=2G QUERYSET=all-tuned RESULTS_DIR=results/sf4-all-tuned-v1
```

Each run records coverage and complete per-statement answers. Successful
execution is distinct from answer validation; see the
[99-query comparison instructions](docker/README.md#complete-99-query-coverage-and-answer-comparison).

---

## What this is

Starting from the TPC-DS toolkit as downloaded from
[tpc.org](https://www.tpc.org/tpc_documents_current_versions/current_specifications5.asp),
this repository:

1. **Ports `dsdgen` to macOS / arm64** — the toolkit has no Darwin target
2. **Builds the schema for MariaDB** from the specification, not from the
   toolkit's stale `tpcds.sql`
3. **Loads 19,557,376 rows** of SF=1 data with correct NULL handling
4. **Adapts all 99 queries** to MariaDB's dialect
5. **Measures** the effect of indexing, baseline vs. indexed

### Headline results

| | |
|---|---|
| Queries running on MariaDB | **99 / 99** |
| SQL errors | **0** |
| Referential integrity | 107 / 107 relationships, zero orphan rows |
| Indexed speedup (all 99) | **2.06x** — 6418.7s to 3119.8s |
| Queries made *slower* by indexing | **19** |

For reference, [`spetrunia/tpcds-run-tool`](https://github.com/spetrunia/tpcds-run-tool)
— the MariaDB-developer reference implementation this work builds on — runs
**83 of 99**. See [`report/11-reference-repo.md`](report/11-reference-repo.md)
for where the gap closes and why.

---

## Layout

```
sql/
  01_schema.sql            25 tables, 429 columns, 24 primary keys
  02_foreign_keys.sql      107 foreign keys (optional)
  03_drop_foreign_keys.sql reverses 02, including its indexes
  04_load_data.sql         LOAD DATA with NULL handling
  05_indexes.sql           117 indexes (from the reference repo)

queries/
  mariadb/                 99 dialect-adapted queries (RNG parameters)
  qualification/           Appendix B parameters, for answer-set comparison
  tiers/                   the 99 queries split into 5 files by response time
  manual-fixes/            hand fixes as patches, survive regeneration
  results/base/            timings with no indexes
  results/indexed/         timings with 117 indexes
  run_query.py             run one query, time it, compare to answer set
  compare.py               base vs indexed

report/                    27 documents, one per step

windows/                   Windows setup, fully isolated from the above
  00..06 *.ps1             prerequisites -> build -> generate -> load -> run
  run-all.ps1              everything in order
  lib/Common.ps1           shared config; refuses to run on non-Windows
  generated/               Windows-generated files stay here
```

**Windows:** see [`windows/README.md`](windows/README.md). The scripts are
additive — they only read the shared `sql/` and `queries/` folders, write
generated files into `windows/generated/`, and hard-refuse to run on a
non-Windows host.

---

## Reproducing

Run the commands below from the repository root (the directory containing
`sql/`, `queries/` and `DSGen-software-code-4.0.0/`). The checkout can live
anywhere, including a directory with spaces; no personal paths need editing.
The loader uses relative `LOAD DATA LOCAL INFILE` paths, resolved from the
MariaDB client's working directory, so run the load command from this root.
The Python query tools locate their inputs from their own script location.

On Linux, use `make OS=LINUX` for the build in step 1. The Linux target
enables `-fcommon` for the toolkit's legacy shared global variables, which
otherwise cause linker errors with GCC 10 and newer. Changes to the makefile
automatically rebuild existing object files.

```sh
# 1. build the toolkit (already patched for macOS in this tree)
cd DSGen-software-code-4.0.0/tools && make

# 2. generate 1.2 GB of SF=1 data
./dsdgen -SCALE 1 -DIR ../data -FORCE

# 3. schema + load
cd ../..
mariadb < sql/01_schema.sql
mariadb --local-infile=1 < sql/04_load_data.sql

# 4. indexes (optional)
mariadb tpcds < sql/05_indexes.sql

# 5. run and compare
cd queries
for q in $(seq 1 99); do python3 run_query.py $q indexed; done
python3 compare.py
```

The generated data is **not** in this repository (1.2 GB). Step 2 recreates it
byte-identically — `dsdgen` is deterministic.

For dedicated databases and scale/seed-specific data directories, use
[`scripts/prepare_experiments.py`](scripts/prepare_experiments.py) as described
in the [experiment guide](experiments/README.md). Its generated SQL and setup
manifest use repository-relative paths. New experiment job manifests use paths
relative to the job file, so they remain usable when the checkout is moved.
Archived measurement records may contain the original machine's paths as
historical metadata; the scripts do not depend on those paths.

---

## Findings worth knowing

**The toolkit's own `tpcds.sql` disagrees with the specification.**
`customer.c_last_review_date` is declared `char(10)` but the spec, the
toolkit's own RI script, `query30.tpl` and the generated data all say
`c_last_review_date_sk` — an integer date key. Taking the DDL at face value
breaks query 30.

**`dsqgen -QUALIFY Y` does not produce the qualification queries.**
It controls only the *order* queries are emitted in; parameters still come from
the RNG. The published answer sets correspond to the fixed values in Appendix B
of the specification, which are extracted and applied in
[`report/12-qualification-parameters.md`](report/12-qualification-parameters.md).

**Every shipped dsqgen dialect file is broken.** All of them fail with
`Substitution '_END' is used before being initialized`. One line fixes it.

**Indexing is not a uniform win.** 19 of 99 queries got *slower*; query39 went
from 1.6s to 193.6s. About a quarter of the total gain is handed back.

Full detail in [`report/00-overview.md`](report/00-overview.md).

---

## License

The TPC-DS toolkit, specification and answer sets under
`DSGen-software-code-4.0.0/` are the property of the **Transaction Processing
Performance Council** and are redistributed here under clause 9 of the TPC End
User License Agreement, a complete copy of which is included at
[`DSGen-software-code-4.0.0/EULA.txt`](DSGen-software-code-4.0.0/EULA.txt).

# THE TPC SOFTWARE IS AVAILABLE WITHOUT CHARGE FROM TPC.

No fee is charged for this distribution. The scripts, reports and query
adaptations written for this project are provided as-is.
