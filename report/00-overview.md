# TPC-DS v4.0.0 on MariaDB — Build Report

> Performance figures in this report are **not comparable to TPC Benchmark
> Results** — unaudited, scale factor 1, not meeting any official TPC Benchmark
> Standard. See `DSGen-software-code-4.0.0/EULA.txt` clause 4.c(3).

Working directory: `/Users/hosseinaghaei/Desktop/projects/dw`

## What was done

| # | Step | Report |
|---|------|--------|
| 1 | Unpack the TPC-DS toolkit and port `dsdgen` to macOS/arm64 | [01-build-dsdgen.md](01-build-dsdgen.md) |
| 2 | Generate the scale-factor-1 data set | [02-generate-data.md](02-generate-data.md) |
| 3 | Read the specification and identify the schema | [03-read-specification.md](03-read-specification.md) |
| 4 | Reconcile the specification against the toolkit's own DDL | [04-reconcile-discrepancies.md](04-reconcile-discrepancies.md) |
| 5 | Decide the MariaDB physical design | [05-mariadb-design.md](05-mariadb-design.md) |
| 6 | Generate and apply the schema | [06-create-schema.md](06-create-schema.md) |
| 7 | Port and validate referential integrity | [07-foreign-keys.md](07-foreign-keys.md) |
| 8 | Verify, record deviations, and state next steps | [08-verification.md](08-verification.md) |
| 9 | Load the SF=1 data into MariaDB | [09-load-data.md](09-load-data.md) |
| 10 | Generate the queries and adapt them to MariaDB | [10-adapt-queries.md](10-adapt-queries.md) |
| 11 | The `tpcds-run-tool` reference implementation | [11-reference-repo.md](11-reference-repo.md) |
| 12 | Qualification parameters and the answer sets | [12-qualification-parameters.md](12-qualification-parameters.md) |
| 13 | Benchmark results: baseline vs. indexed | [13-benchmark-results.md](13-benchmark-results.md) |
| — | Schema relationships reference | [14-schema-relationships.md](14-schema-relationships.md) |
| 15 | Index usage statistics — 81 of 117 indexes never read | [15-index-statistics.md](15-index-statistics.md) |
| 16 | What the buffer pool was hiding — a method correction | [16-buffer-pool-and-root-cause.md](16-buffer-pool-and-root-cause.md) |
| 17 | Hiding the unused indexes — and a retracted finding | [17-unused-indexes-are-not-safe-to-drop.md](17-unused-indexes-are-not-safe-to-drop.md) |

## Result

A database `tpcds` on the local MariaDB server containing the complete
TPC-DS v4.0.0 schema — **25 tables, 429 columns, 24 primary keys**, verified
column-by-column against the specification — **loaded with 19,557,376 rows**
of SF=1 data, and **all 99 TPC-DS queries running** against it.

| | |
|---|---|
| Queries running on MariaDB | **99 / 99** (reference repo: 83 / 99) |
| SQL errors | **0** in both the baseline and indexed runs |
| Referential integrity | 107 / 107 relationships, **zero orphan rows** |
| Indexed speedup, 97 clean queries | **1.01x** (1276.8s -> 1262.8s) |
| Queries made *slower* by indexing | **18** — two of them serious |
| Indexes never read by any query | **81 of 117** — hiding all 80 changes runtime by **−0.8%** ([step 17](17-unused-indexes-are-not-safe-to-drop.md)) |
| Worst regression, root-caused and fixed | query 39: **92.5s → 1.7s** |
| Biggest index win | query 95: **>300s → 0.1s** |
| Buffer pool | **8 GB**, matching the reference repo |
| Dataset seed | **10**, matching the reference repo |

## Layout

```
dw/
├── DSGen-software-code-4.0.0/     TPC-DS toolkit (patched for macOS)
│   ├── tools/                     dsdgen, dsqgen, distcomp + sources
│   ├── specification/             specification_4.0.0.pdf
│   ├── query_templates/           99 query templates
│   ├── answer_sets/               reference results
│   └── data/                      25 .dat files, 1.2 GB, SF=1
├── sql/
│   ├── 01_schema.sql              database + 25 tables + primary keys
│   ├── 02_foreign_keys.sql        107 foreign keys (optional, apply after load)
│   ├── 03_drop_foreign_keys.sql   reverses 02, including its indexes
│   ├── 04_load_data.sql           25 LOAD DATA statements with NULL handling
│   └── 05_indexes.sql             117 indexes, from the reference repo
├── queries/
│   ├── generated/                 dsqgen output, RNG parameters
│   ├── mariadb/                   dialect-adapted, used for timing
│   ├── qualification/             Appendix B parameters, for answer-set checks
│   ├── manual-fixes/              hand fixes as patches (survive regeneration)
│   ├── results/base/              run with no indexes
│   ├── results/indexed/           run with 117 indexes
│   ├── run_query.py               run one query, time it, compare to answer set
│   └── compare.py                 base vs indexed comparison
├── tpcds-run-tool/                cloned reference implementation
└── report/                        this report
```

## Environment

| | |
|---|---|
| Host | macOS 26.6.2 (Darwin 25.6.0), Apple Silicon arm64 |
| Compiler | Apple clang 21.0.0 |
| MariaDB | 13.0.2-MariaDB (Homebrew), datadir `/opt/homebrew/var/mysql/` |
| Toolkit | TPC-DS Tool v4.0.0 (`DSGen-software-code-4.0.0`) |
| Date | 2026-09-23 |

## Reproducing from scratch

```sh
cd DSGen-software-code-4.0.0/tools
make                                     # builds dsdgen, dsqgen, distcomp, tpcds.idx
./dsdgen -SCALE 1 -RNGSEED 10 -DIR ../data -FORCE   # 25 .dat files
cd ../..
mariadb < sql/01_schema.sql              # creates database tpcds
mariadb --local-infile=1 < sql/04_load_data.sql   # loads 19.5M rows
mariadb tpcds < sql/05_indexes.sql       # 117 indexes (optional)
cd queries && for q in $(seq 1 99); do python3 run_query.py $q indexed; done
python3 compare.py
```
