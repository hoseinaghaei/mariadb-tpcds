# Step 5 — MariaDB physical design decisions

Each decision below, the reason for it, and what to change if a different
trade-off is wanted.

## Datatype mapping

| TPC-DS (Clause 2.2.2) | MariaDB | Why |
|---|---|---|
| `identifier` | `BIGINT` | Clause 2.2.2.3 allows identifier columns to be sized for scaling. `BIGINT` is safe at every scale factor. |
| `integer` | `BIGINT` | Clause 2.2.2.1(b) requires a 64-bit range. `INT` would not comply. |
| `decimal(d,f)` | `DECIMAL(d,f)` | Exact decimal, as required. Never `FLOAT`/`DOUBLE`. |
| `char(N)` | `CHAR(N)` | Direct. |
| `varchar(N)` | `VARCHAR(N)` | Direct. |
| `date` | `DATE` | MariaDB `DATE` spans 1000-01-01 … 9999-12-31, covering the required 1900–2199. |
| `time` | `TIME` | `dbgen_version` only. |

Resulting column mix: 189 `BIGINT`, 71 `DECIMAL(7,2)`, 12 `DATE`, the rest
`CHAR`/`VARCHAR`/`DECIMAL(5,2)`.

### The `BIGINT` trade-off

`BIGINT` is 8 bytes; `INT` is 4. `store_sales` has 11 integer-family columns
across 2.88M rows, so the choice is worth roughly 63 MB on that table alone,
and proportionally more at higher scale factors.

At SF=1 every surrogate key fits comfortably in `INT`. **`BIGINT` was chosen
for specification compliance**, and because `ss_ticket_number` and the
`*_order_number` columns do exceed 2³¹ at large scale factors — a schema that
only works at SF=1 is a trap.

To trade compliance for size:

```sql
-- shrinks the fact tables by roughly 40%; only valid up to about SF=1000
ALTER TABLE store_sales
  MODIFY ss_sold_date_sk INT, MODIFY ss_item_sk INT, /* ... */;
```

## Character set: `utf8mb4`

**Forced by the data.** `customer.dat` contains 910 lines with multi-byte
characters in the name columns — `c3 89` (É) and `c3 94` (Ô). The file is
valid UTF-8. A single-byte character set such as `latin1` would store those as
two mojibake characters each and corrupt 910 customer rows.

The cost is that `CHAR(N)` reserves up to 4N bytes. Maximum row sizes were
computed for every table against InnoDB's 65,535-byte limit:

| Widest tables | utf8mb4 max row | latin1 max row |
|---|---:|---:|
| `call_center` | 2,830 B | 781 B |
| `store` | 2,826 B | 777 B |
| `web_site` | 2,526 B | 687 B |
| `item` | 2,250 B | 612 B |

The widest table uses 4% of the limit. No row-size risk. (InnoDB also stores
`CHAR` columns variable-length under `ROW_FORMAT=DYNAMIC` with a multi-byte
charset, so the on-disk cost is closer to the latin1 column.)

## Collation: `utf8mb4_bin`

The server default is `utf8mb4_general_ci` — case-insensitive and
accent-insensitive. `utf8mb4_bin` was set explicitly instead:

- **Deterministic ordering.** Most TPC-DS queries end in `ORDER BY ... LIMIT
  100`. Under a case-insensitive collation, ties between strings that differ
  only in case are broken arbitrarily, so which 100 rows come back can vary.
  Binary comparison is total and reproducible.
- **Matches the answer sets.** `answer_sets/` was produced on systems using
  case-sensitive comparison.
- **Faster.** Byte comparison beats collation-aware comparison on index
  lookups and joins.

The TPC-DS data is consistently cased, so equality predicates like
`i_category = 'Music'` behave the same either way. To prefer
case-insensitive matching instead:

```sql
ALTER DATABASE tpcds COLLATE utf8mb4_uca1400_ai_ci;   -- then re-run 01_schema.sql
```

## Engine: InnoDB, `ROW_FORMAT=DYNAMIC`

- Required for the optional foreign keys in `02_foreign_keys.sql`.
- Clustered on the primary key, which suits the surrogate-key star schema.
- `DYNAMIC` is the server default and stores long variable-length columns
  off-page.

Aria or MyISAM would load faster and use less space but support no foreign
keys and no transactions. InnoDB is the right default; switch only if RI is
definitively not wanted and load time dominates.

## Primary keys: declared

Clause 2.5.1.8 makes them optional, but they were declared on all 24 base
tables:

- InnoDB creates a hidden 6-byte clustered index when no primary key exists,
  so declaring one costs nothing and produces a useful clustering order.
- They document the grain of each table.

All 17 dimensions have a single-column surrogate key. **All 7 fact tables
have compound keys**, in the order the specification gives:

```sql
store_sales       PRIMARY KEY (ss_item_sk, ss_ticket_number)
store_returns     PRIMARY KEY (sr_item_sk, sr_ticket_number)
catalog_sales     PRIMARY KEY (cs_item_sk, cs_order_number)
catalog_returns   PRIMARY KEY (cr_item_sk, cr_order_number)
web_sales         PRIMARY KEY (ws_item_sk, ws_order_number)
web_returns       PRIMARY KEY (wr_item_sk, wr_order_number)
inventory         PRIMARY KEY (inv_date_sk, inv_item_sk, inv_warehouse_sk)
```

Column order within a compound key matters in InnoDB: it is the clustering
order, and it decides which prefix lookups can use the key. The specification's
order was preserved exactly — note that the v4.0.0 change history records a
deliberate reversal of the `web_returns` key order, so the item-first ordering
above is intentional, not incidental.

`dbgen_version` has no primary key — the specification defines none.

## NOT NULL: only where the specification marks `N`

Clause 2.5.4.1 permits `NOT NULL` **only** on columns marked `N`. Applied
exactly, from the parsed specification — never inferred from the data. Note
that fact-table foreign keys are mostly nullable by design: dsdgen deliberately
emits NULL surrogate keys to exercise outer joins.

## What was deliberately not created

Two of these are choices; one is a requirement. They are separated here
because an earlier draft of this document ran them together and implied the
specification forbids all three. It does not.

### Required by the specification

- **No `CHECK` constraints.** Clause 2.5.4.1 is explicit: constraints "are
  limited to primary key, foreign key, and NOT NULL constraints".
- **No generated / computed columns on base tables.** Clause 2.5.2.9: "all
  columns listed in the table definition shall be implemented and **there shall
  be no columns added to the tables**." A generated column is an added column.

### A choice, not a requirement

- **No secondary indexes** *(beyond the primary keys)*. Clause 2.5.3 restricts
  Explicit Auxiliary Data Structures but does not prohibit indexes — they are
  named as an example of an EADS and are permitted subject to 2.5.3.2–2.5.3.8.
  None were created initially so the baseline measurement would be clean; 117
  were applied later in [step 11](11-reference-repo.md).

- **No partitioning.** **Explicitly allowed** by Clause 2.5.3.8, not forbidden.
  Horizontal partitioning of base tables and EADS is permitted (2.5.3.8.3)
  provided that:
  - only **primary keys, foreign keys, date columns and date surrogate keys**
    are used as partitioning columns;
  - explicit partition values rely on nothing but the column's minimum and
    maximum and its declared datatype;
  - partitions divide that range **equally** (date granularities of days,
    weeks, months or years are permitted);
  - values outside the range can still be inserted, per Clause 1.5;
  - the DDL and directives are **disclosed**.

  Vertical partitioning is allowed too (2.5.3.8.4), but only where it is *not*
  driven by explicit DDL directives — SQL that explicitly partitions columns
  across storage is prohibited.

  Clause 3.3.3 confirms partitioning is expected to be a real option: if the
  test database is horizontally partitioned, the qualification database must be
  too. It was simply not used here.

  MariaDB's `PARTITION BY RANGE` on `d_date_sk`, or on the fact tables'
  `*_sold_date_sk`, would be specification-legal and is a reasonable next
  experiment — partition pruning on date is exactly the access pattern TPC-DS
  exercises.

- **No views.** Also **permitted**, and in fact anticipated by the
  specification. Clause 4.2.3 lists `CREATE VIEW` / `DROP VIEW` among the
  statements whose names may be adjusted, allows subqueries to "be replaced
  with semantically equivalent derived tables or views", and Clause 4.2.3's
  notes cover dropping dependent views. A **non-materialized** view is only a
  query rewrite and holds no data, so it is not an auxiliary data structure at
  all. A **materialized** view is an EADS and falls under the 2.5.3
  restrictions.

  Views were not used because the queries are taken unmodified from `dsqgen`;
  nothing here needed them.
