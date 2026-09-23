# Step 11 — The `tpcds-run-tool` reference implementation

Cloned to `dw/tpcds-run-tool/` from
<https://github.com/spetrunia/tpcds-run-tool>. Sergei Petrunia is a MariaDB
optimizer developer, so this is a MariaDB-informed reference rather than a
generic port. It tracks MariaDB bug
[MDEV-17802](https://jira.mariadb.org/browse/MDEV-17802) — "MySQL/MariaDB
cannot run all of the TPC-DS queries".

## What it provides

| Artifact | Use here |
|---|---|
| `mariadb-tpcds-tooling2/adapt-queries-for-mariadb-v4.diff` | independent check on our dialect fixes |
| `mariadb-tpcds-tooling2/ddl/indexes.sql` | 117 indexes — the optimization starting point |
| `mariadb-tpcds-tooling2/ddl/tables.sql` | alternative schema |
| `mariadb-tpcds-tooling2/aux-tables.sql` | `my_tpcds_result` timing table — adopted as-is |
| `10-prepare-queries.sh` / `20-run-queries.sh` | harness structure |

It targets **TPC-DS v2.8.0rc4 and MariaDB 10.4** (2018); we are on **v4.0.0 and
MariaDB 13.0.2**, so its diff does not apply directly — it was used as a
cross-check, not applied.

## Where it agrees with what we found independently

Its diff adds `as TBL_1`, `as TBL_2` … in exactly the places we identified as
unaliased derived tables, for queries 2, 23 and 49. Same diagnosis, same fix,
reached separately. That is a useful confirmation that R5 is correct and not a
workaround for something else.

It also passes `-dialect netezza`, confirming the `limit %d` choice.

## Where it gave up — and where we went further

The repo runs only **83 of 99** queries. Its `templates-for-mariadb.lst`
excludes 16, and for three of them the diff replaces the query with a stub:

```sql
select 'MARIADB-EXPECTED-ERROR: Derived table must have alias; rollup+order by' as NOTE;   -- query14
select 'MARIADB-EXPECTED-ERROR: full outer join' as NOTE;                                  -- query51
select 'MARIADB-EXPECTED-ERROR: full outer join' as NOTE;                                  -- query97
```

Excluded: **5, 8, 14, 18, 22, 27, 36, 38, 51, 54, 70, 77, 80, 86, 87, 97.**

We run **all 99**. The 16 break down as:

| Excluded because | Queries | Status here |
|---|---|---|
| `ROLLUP` + `ORDER BY` | 5, 18, 22, 27, 36, 70, 77, 80, 86 | fixed by R1+R4 |
| `INTERSECT` / `EXCEPT` | 8, 38, 87 | **no longer needed** — MariaDB has supported these since 10.3; verified working on 13.0.2 |
| `FULL OUTER JOIN` | 51, 97 | fixed by R6 (emulation) |
| alias + rollup | 14 | fixed by R5+R4 |
| — | 54 | runs unmodified |

So a meaningful part of the gap is simply **seven years of MariaDB
development**: `INTERSECT`/`EXCEPT` arrived in 10.3 and window functions in
10.2, both after this repo was written. The rest (rollup ordering, full outer
join) are still real MariaDB limitations in 13.0.2 and needed genuine
workarounds.

**99/99 parsing versus the reference's 83/99 is where this work picks up.**

## Schema difference worth noting

`ddl/tables.sql` declares surrogate keys as 32-bit `integer`; our
`01_schema.sql` uses `BIGINT` because Clause 2.2.2.1(b) requires a 64-bit
range (see [step 5](05-mariadb-design.md)). Theirs is smaller and marginally
faster; ours is specification-compliant and safe at any scale factor. At SF=1
this is not the bottleneck, so the loaded schema was left as-is.

## Adopted directly

```sql
create table my_tpcds_result(
  query_name varchar(64), query_stream varchar(64),
  query_start datetime,   query_time_ms bigint
);
```
