# Step 8 — Verification, known deviations, next steps

## Verification

The live MariaDB database was read back out of `information_schema` and
compared, column by column, against the specification parsed in
[step 3](03-read-specification.md) — table set, column names, **column
order**, datatype, nullability, primary key membership, character set and
collation:

```
live database 'tpcds': 25 tables, 429 columns, 24 primary keys
engine/row_format/collation: InnoDB / Dynamic / utf8mb4_bin

VERIFIED: every table, column, order, datatype, nullability, primary key,
charset and collation in MariaDB matches the TPC-DS v4.0.0 specification.
```

This is a comparison against the PDF, not against `tools/tpcds.sql` — the two
disagree, and [step 4](04-reconcile-discrepancies.md) records why the
specification was followed.

Independent checks that also passed:

| Check | Result |
|---|---|
| Spec column count vs. generated `.dat` field count, all 25 tables | all match |
| SF=1 reference row counts (`store_sales`, `customer`, `item`, `date_dim`) | all match |
| All 107 foreign keys create and drop cleanly | verified |
| No table or column name collides with a MariaDB reserved word | verified — all 429 identifiers parsed unquoted |
| Max row size vs. InnoDB's 65,535-byte limit | widest is 2,830 B (`call_center`) |

## Known deviations

### 1. `CHAR(N)` does not pad on retrieval

Clause 2.2.2.2 comments:

> If the string that a column of datatype char(N) holds is shorter than N
> characters, then trailing spaces shall be stored in the database or the
> database shall automatically pad with spaces upon retrieval such that a
> CHAR_LENGTH() function will return N.

MariaDB strips trailing spaces from `CHAR` columns on retrieval. Measured:

```sql
CREATE TABLE t (c CHAR(10), v VARCHAR(10));
INSERT INTO t VALUES ('AB','AB');
SELECT CHAR_LENGTH(c), CHAR_LENGTH(v) FROM t;
-- 2, 2     (the specification requires 10 for the CHAR column)
```

This is engine behaviour with no schema-level workaround. **No TPC-DS query
template calls `CHAR_LENGTH` on a `char` column, so it does not affect query
results or the answer sets.** It is recorded here because it would matter for
a formal audited submission.

### 2. Two column names follow the specification, not `tpcds.sql`

`c_last_review_date_sk` and `s_tax_percentage`. See
[step 4](04-reconcile-discrepancies.md). The first is required for query 30 to
compile; the second is cosmetic and reversible with one `ALTER TABLE`.

### 3. `integer` mapped to `BIGINT`

Compliant with Clause 2.2.2.1(b), but larger than a SF=1 database strictly
needs. See [step 5](05-mariadb-design.md) for the size trade-off.

## Current state

| | |
|---|---|
| Database | `tpcds` on local MariaDB 13.0.2 |
| Tables | 25 (7 fact, 17 dimension, 1 metadata) |
| Columns | 429 |
| Primary keys | 24 |
| Foreign keys | 0 applied (107 available in `sql/02_foreign_keys.sql`) |
| Secondary indexes | 0 |
| Rows | 0 — **tables are empty** |
| On-disk size | 3.2 MB |
| Data files | generated, 1.2 GB, in `DSGen-software-code-4.0.0/data/` |

## Next step: loading the data

Not part of this task, and not done. The schema is ready for it. Three things
about the `.dat` format will bite a naive loader:

1. **Every line ends with a trailing `|`.** Use `LINES TERMINATED BY '|\n'` so
   the last delimiter is consumed rather than producing an extra empty field.
2. **Empty field means NULL, but `LOAD DATA` does not treat it that way.** It
   writes `0` into numeric columns and `0000-00-00` into dates. Nullable
   columns must be routed through variables:

   ```sql
   LOAD DATA LOCAL INFILE 'store_sales.dat' INTO TABLE store_sales
     CHARACTER SET utf8mb4
     FIELDS TERMINATED BY '|' LINES TERMINATED BY '|\n'
     (@ss_sold_date_sk, @ss_sold_time_sk, ss_item_sk, /* ... */)
     SET ss_sold_date_sk = NULLIF(@ss_sold_date_sk,''),
         ss_sold_time_sk = NULLIF(@ss_sold_time_sk,'');
   ```

   This is not a marginal concern. Measured over the first 500,000 rows of
   `store_sales.dat`, each nullable foreign key is empty about 4.5% of the
   time:

   | Column | empty | | Column | empty |
   |---|---:|---|---|---:|
   | `ss_sold_date_sk` | 4.45% | | `ss_hdemo_sk` | 4.48% |
   | `ss_sold_time_sk` | 4.47% | | `ss_addr_sk` | 4.48% |
   | `ss_customer_sk` | 4.45% | | `ss_store_sk` | 4.50% |
   | `ss_cdemo_sk` | 4.44% | | `ss_promo_sk` | 4.48% |
   | `ss_item_sk` | **0.00%** | | `ss_ticket_number` | **0.00%** |

   Loaded naively, roughly 130,000 rows per nullable column in `store_sales`
   alone would hold `0` — a value that matches no dimension key. Every
   affected foreign key in `02_foreign_keys.sql` would then fail to create,
   and outer-join queries would return wrong answers.

   The two 0.00% columns are the primary key, which confirms independently
   that the specification's `NOT NULL` markings match the generated data.
3. **`LOAD DATA LOCAL INFILE` needs the client flag.** The server already has
   `local_infile=1`; the client needs `mariadb --local-infile=1`.

Load order if the foreign keys will be applied: all 17 dimensions first, then
the 7 fact tables, then `02_foreign_keys.sql`.

## Verifying a load afterwards

Compare against the SF=1 reference cardinalities recorded in
[step 2](02-generate-data.md) — for example `store_sales` must hold exactly
2,880,404 rows and `inventory` exactly 11,745,000.

## Running the queries

The 99 query templates are in `DSGen-software-code-4.0.0/query_templates/`
and the reference results in `answer_sets/`. `dsqgen` (built in
[step 1](01-build-dsdgen.md)) instantiates templates into executable SQL. There
is no MariaDB dialect file in the toolkit, so the templates need one or need
adapting — a separate piece of work from the schema.
