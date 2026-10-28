# Q4 and Q67: a measured follow-up to report 25

2026-10-27. These are **local SF=1 experiments**, not new measurements for
report 25's MariaDB 13 / SF=4 reference configuration. The adopted files in
`queries/tuned/`, the `BEST` aliases and the benchmark tooling remain unchanged.

**Result:** Q4's combined candidate is 1.85x faster in the first comparison
and 1.88x in a second comparison, with identical returned results. Neither
Q67 candidate demonstrates a useful improvement in this environment.

## Environment and method

- Existing `tpcds_riccio_sf1` database; `dbgen_version` records TPC-DS tools
  4.0.0, `-SCALE 1 -RNGSEED 10`.
- MariaDB 10.11.14 on Linux; Ryzen 5 3500U; 6.7 GiB RAM; 2 GiB InnoDB pool;
  16 KiB pages; statistics sample size 20; 117 secondary indexes plus 24
  primary indexes. Index definitions are captured in every trial's metadata.
- Q4 uses the existing 16 MiB temporary-table/heap limits and 2 MiB sort
  buffer. All three Q67 versions explicitly use the adopted query's 256 MiB
  temporary-table/heap limits and 64 MiB sort buffer. No comparison with the
  reference server's 1536 MiB limits was attempted on this laptop.
- No schema, index, data, global configuration or service changes. Queries
  run serially, with a 120-second statement cap and 150-second client cap.
  Query cache is disabled in each session.
- Initial probes precede repetitions and are excluded from the tables.
  Each series has three rounds, reversing variant order in round 2. This
  checks the new candidates against the **currently adopted SQL**, rather
  than claiming the older original-to-adopted gain again.
- Timings include the client, session setup, execution and full XML result
  transfer. Result parsing/comparison occurs after timing. EXPLAIN, ANALYZE,
  metadata and fixtures are excluded from ordinary timings.
- No cold-cache reset or exclusive host reservation. The initial snapshot
  showed approximately 3.1 GiB available RAM and 3.2 GiB swap in use.
  These small warm-cache series support local conclusions, not statistical
  significance or speedup guarantees on another machine.

Raw SQL inputs, full outputs, plans, metadata and job order are preserved in
[`experiments/evidence/slow_queries_20261027/`](../experiments/evidence/slow_queries_20261027/).
The CSV and JSON summaries retain the individual trial labels and SQL hashes.

## Q4: separate the effects before choosing a candidate

| Version | Change from the adopted query | Median | Min–max | Adopted/candidate |
|---|---|---:|---:|---:|
| adopted | existing two-year/customer-key rewrite | 15.458s | 14.448–16.305s | 1.00x |
| v3 | replace year-presence count with early total conditions | 15.614s | 15.007–15.750s | 0.99x |
| **v4** | v3 plus redundant fact-date bounds | **8.335s** | **7.632–8.385s** | **1.85x** |

The second series tests whether the date bounds alone explain the gain:

| Version | Change | Median | Min–max | Adopted/candidate |
|---|---|---:|---:|---:|
| adopted | same adopted SQL | 15.205s | 14.448–16.307s | 1.00x |
| **v4** | total conditions plus bounds | **8.083s** | **7.836–8.484s** | **1.88x** |
| v5 | bounds only; retain `COUNT(DISTINCT d_year)` | 10.892s | 10.290–11.039s | 1.40x |

All ordinary trials returned the same six rows, column names, ordered values
and NULLs as the fresh adopted baseline. v4 wins every measured round in
both series. v3 alone is not an improvement; v5 is useful but slower than v4.

### Why the changes preserve the answer

The adopted query restricts each channel to 2001/2002 and requires both year
groups with `COUNT(DISTINCT d_year)=2`. Its final comparisons require positive
first-year totals and non-NULL second-year totals in all three channels.
If any second-year total is NULL, a required ratio comparison is UNKNOWN and
the row cannot pass the WHERE clause.

v3/v4 therefore use `HAVING y1 > 0 AND y2 IS NOT NULL`. Non-NULL totals for
both years imply that both year groups exist. Second-year totals are **not**
required to be positive: zero and negative totals remain eligible. The
original monetary expressions, NULL behavior, guarded divisions, joins,
projection, ordering and limit remain intact.

The bounds are `MIN/MAX(d_date_sk)` over the same allowed years. Every date
admitted by the original year predicate lies inside those bounds. The date
join and year predicate remain, so extra dates inside the interval are still
rejected. This does not assume dense or chronological surrogate keys.

The rewrite inherits the adopted query's customer-identity assumption. The
local check found 100,000 customers, 100,000 distinct business IDs and no
NULL IDs; this is not a schema uniqueness constraint.

### Runtime evidence explaining the gain

The saved ANALYZE plans show different work, not merely shorter wall time:

| Observation | Adopted | v4 |
|---|---:|---:|
| store access | 100,000 customer-key probes | 730 date-key probes |
| store fact rows read, approximately `r_loops * r_rows` | 2,749,835 | 1,102,916 |
| store buffer-pool pages accessed | 8,554,872 | 3,313,012 |

The tradeoff is real: v4 processes more catalog and web facts than the adopted
plan, which reaches those channels only after earlier customer filters.
Reducing the dominant store work wins here; different selectivity, indexes or
optimizer decisions can change that balance.

v4 and v5 reach the same date-filtered fact rows, but their aggregation work
differs. The store grouping sort handles about **14,574 grouped rows** in v4
versus **1,102,916 input rows and four sort passes** in v5. This supports the
interaction observed in the ablation: removing the distinct-year aggregate
helps substantially once the bounds change the access/materialization plan.
It does not justify a general claim that removing DISTINCT is faster.

### Additional semantic checks

SELECT-only CTE fixtures shadow the fact/dimension tables for each statement;
they create no database objects. All Q4 variants matched the adopted query's
six fixture rows, including NULL customer attributes, missing/all-NULL year
totals, zero/negative denominators, valid zero/negative second-year totals,
duplicate facts, decimal amounts, orphan/NULL keys and an out-of-year date
whose key lies inside the bounds. Fixture inputs and outputs are archived.

## Q67: two plausible changes, no convincing gain

| Version | Change from adopted SQL | Median | Min–max | Adopted/candidate |
|---|---|---:|---:|---:|
| adopted | existing key-range/ROLLUP query | 11.593s | 11.040–12.043s | 1.00x |
| v3 | force date → fact → item → store join order | 13.351s | 12.795–13.599s | 0.87x |
| v4 | aggregate by item/store/month before descriptive joins | 11.240s | 10.694–11.499s | 1.03x |

All nine repetitions matched the adopted query's 100 rows exactly. A separate
execution also confirmed that the adapted original returns that same result
on this database. v3 is slower in every round. v4 has overlapping ranges and
does not consistently beat the baseline; do not promote it on these results.

Both candidates keep the complete descriptive ROLLUP, ranking, tie handling,
NULL-to-zero measure expression, ordering and limit. v4 still combines equal
product/store descriptions across different surrogate keys in the final
ROLLUP; replacing that final grouping with key grouping would change results.
Its aggregation pushdown relies on unique item/store dimension keys and exact
decimal arithmetic, as provided by this schema.

The Q67 fixtures compare against the adapted original and return 31 matching
rows. They include equal descriptions under different keys, NULL grouping
values, tied/negative/zero/NULL measures, duplicate facts, orphans and an
out-of-window date inside the surrogate-key interval. Both candidates retain
the original month predicate as well as the redundant key range.

### Why pre-aggregation did not settle the problem

Runtime diagnostics show that v4 reduces the input to the descriptive grouping
from 529,657 rows to 337,685 rows, but adds a separate monthly aggregation.
Both versions still produce **499,780 ROLLUP rows** and create **four on-disk
temporary tables** in these diagnostic sessions. Session `Sort_rows` rises
from 1,029,537 to 1,187,231. Narrowing an earlier stage does not remove the
large downstream ROLLUP/window workload.

Those are observations from individual instrumented runs, not extra ordinary
timing repetitions; parent/child plan times must not be added together.

## Decision and next optimization work

Keep Q4 v4 as the leading candidate. Its local evidence is substantially
stronger than a single fast run, but adoption in `queries/tuned/` requires
fresh correctness and repeated timing checks with the reference MariaDB 13
configuration at SF=4. Check SF=1 too, and retain the actual index state.

Keep the adopted Q67. Its next useful investigation is the cost and storage
of its ROLLUP/window intermediates under the reference configuration,
including the query's own 256 MiB limits. Increasing buffers on this laptop
or forcing another join order is not supported by these measurements.

Read the per-query notes in [Q4](../queries/optimized/q4/README.md) and
[Q67](../queries/optimized/q67/README.md) for the candidate files. Historical
report 25 timings remain unchanged; these different-environment results must
not be inserted into its SF=4 ranking.
