# TPC-DS on MariaDB

# THE TPC SOFTWARE IS AVAILABLE WITHOUT CHARGE FROM TPC.

Running the complete **TPC-DS v4.0.0** benchmark schema and all **99 queries**
on **MariaDB 13.0.2** (Apple Silicon, macOS).

> **Performance results in this repository are NOT comparable to TPC Benchmark
> Results.** They were not audited, not produced at a publishable scale factor,
> and do not meet the requirements of any official TPC Benchmark Standard. They
> are published as a research/engineering exercise under clause 4.c(3) of the
> TPC End User License Agreement (`DSGen-software-code-4.0.0/EULA.txt`).

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

report/                    15 documents, one per step
```

---

## Reproducing

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
