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

Adaptation is **dialect only**. No predicate, join, projection, grouping,
ordering or limit was altered, and nothing was rewritten for performance.
Every rule exists because MariaDB rejects the ANSI spelling outright.

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

**R3 is the one rule that is not provably exact.** MariaDB has no `GROUPING()`
function at all — it is MySQL-only. With `WITH ROLLUP`, a super-aggregate row
carries NULL in the rolled-up column, so `GROUPING(x)` is usually written as
`x IS NULL`. That is only equivalent if the column has no genuine NULLs, and
**`item.i_category` has 43 genuine NULLs out of 18,000**, so for queries 36 and
86 the substitution could in principle misclassify real rows as subtotals.
Query 70 groups by `store.s_state`/`s_county`, which have no NULLs, so it is
exact there. An exactly-equivalent rewrite is possible by grouping on
`COALESCE(col,'<sentinel>')` and unwrapping with `NULLIF` in the projection;
it was not applied because it restructures the query more than a dialect fix
should, and the answer-set comparison is the better arbiter.

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
