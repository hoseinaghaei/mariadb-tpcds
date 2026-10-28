# Step 10 — Generate the queries and adapt them to MariaDB

## Generating

`dsqgen` needs a *dialect file* that defines how the target database limits
rows. `query_templates/mariadb.tpl` was added:

```
define __LIMITA = "";
define __LIMITB = "";
define __LIMITC = "limit %d";
define _END = "";
```

MariaDB uses a trailing `LIMIT n`, identical to Netezza — which is why the
reference repo (see [step 11](11-reference-repo.md)) simply passes
`-dialect netezza`.

### A bug in the shipped toolkit

Without the last line, **every shipped dialect fails**:

```
ERROR: Substitution'_END' is used before being initialized at line 63 in query1.tpl
```

`dsqgen` appends an internal `[_END]` substitution to every query but none of
`ansi.tpl`, `db2.tpl`, `oracle.tpl`, `netezza.tpl` or `sqlserver.tpl` defines
it. Verified: `-DIALECT ansi` fails identically. `define _END = "";` fixes it.

That hook turns out to be the toolkit's instrumentation point — the reference
repo defines `_END` as SQL that records each query's elapsed time.

### Two further toolkit quirks

- **`-OUTPUT_DIR` needs a trailing slash.** dsqgen concatenates the directory
  and filename without a separator.
- **`-OUTPUT_DIR` / `-DIRECTORY` paths must be short.** A long path silently
  overflows an internal buffer and produces a corrupted filename with no error.

## Dialect adaptation — what was changed and why

The initial adaptation aimed to change only dialect spelling. The later
NULL-safe grouping-level corrections below replace the original R3 method
structurally to preserve its intended semantics; they are correctness fixes,
not performance rewrites.

**76 of 99 queries needed no change at all.**

| # | Problem | Fix | Queries |
|---|---|---|---|
| R1 | `GROUP BY ROLLUP(a,b)` | `GROUP BY a,b WITH ROLLUP` | 5,14,18,22,27,36,67,70,77,80,86 |
| R2 | `<date> + 90 days` | `<date> + INTERVAL 90 DAY` | 5,12,16,20,21,32,37,40,77,80,82,92,94,95,98 |
| R3 | `GROUPING(x)` | `(x IS NULL)` | 27,36,70,86 |
| R4 | `WITH ROLLUP` + `ORDER BY` (ERROR 1221) | wrap in derived table, order outside | 5,14,18,22,27,36,67,70,77,80,86 |
| R5 | unaliased derived table (ERROR 1064) | add `AS TBL_n` | 2,14,23,49 |
| R6 | `FULL OUTER JOIN` (ERROR 1064) | `LEFT JOIN` ∪ anti-joined `RIGHT JOIN` | 51,97 |

### Notes on the harder ones

**R2 needed care.** A naive `\d+ days` regex would also corrupt quoted column
aliases such as `as "31-60 days"` and `as ">120 days"`. The rule is anchored on
`as date)` so it can only match genuine date arithmetic.

**R3 correctness update, 2026-10-28.** `GROUPING(x)` identifies a rolled-up
column; `x IS NULL` also identifies genuine NULL values, so they are not
generally interchangeable. Q36, Q70 and Q86 now use explicit leaf, subtotal
and grand-total aggregates combined with `UNION ALL`, with hierarchy levels
0/1/2 assigned before ranking. Genuine NULL groups remain separate from
subtotals, even when their displayed keys are identical. A count guard removes
the grand-total branch for empty input, matching MariaDB's grouped ROLLUP.
All-NULL measures still retain their groups.

The adopted Q70 source and generated file have the same correction. They also
preserve the NULL-state exclusion of the original IN predicate and use its
logical date-dimension filter, rather than relying on hardcoded surrogate-key
bounds. Q27's state filter already excludes genuine NULL states, so its R3
substitution does not need this rewrite.

The three adapted fixes are preserved in `queries/manual-fixes/`. Read-only
CTE fixtures check the corrected queries, including adopted Q70, against an
independent grouping/ranking oracle. Twelve live cases passed on MariaDB
10.11.14: normal NULL-containing input, empty input and all-NULL measures.
This is targeted correctness evidence, not proof that all 99 answers have
been qualified. Historical hashes/timings predate these corrections.

**R4 is a hard MariaDB limitation.** `WITH ROLLUP` cannot coexist with
`ORDER BY` in the same SELECT:

```sql
select * from (
   <original query up to and including WITH ROLLUP>
) tpcds_rollup
order by ... limit 100;
```

Same rows, same order.

**R5** — MariaDB requires every derived table to have an alias; ANSI does not.

**R6** — MariaDB has no `FULL OUTER JOIN`. Emulated as
`LEFT JOIN` `UNION ALL` `RIGHT JOIN ... WHERE <left keys> IS NULL`.
`UNION ALL` plus the anti-join filter matters: plain `UNION` would also collapse
legitimate duplicate rows and change the result.

## Result

**All 99 queries / 103 statements parse and resolve cleanly** against the live
schema, verified with `EXPLAIN`.

R1–R4 are applied mechanically by a script from the generated SQL; R5 and R6
were hand-applied and are preserved as patches in `queries/manual-fixes/` so
they survive regeneration.

## One setting, not a query change

Many queries call functions with a space before the parenthesis — `sum (`,
`cast (`. MariaDB rejects this by default (`ERROR 1630: FUNCTION tpcds.sum does
not exist`). Rather than edit 99 files, the runner sets:

```sql
SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE');
```

This is a session setting, so the query text stays untouched.
