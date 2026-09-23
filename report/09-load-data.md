# Step 9 — Load the SF=1 data into MariaDB

## Script

`sql/04_load_data.sql`, generated from `information_schema` so nullability is
exact: 25 `LOAD DATA` statements, 429 columns — 52 `NOT NULL` loaded directly,
**377 routed through `NULLIF(@v,'')`**.

```sh
mariadb --local-infile=1 < sql/04_load_data.sql
```

Three properties of the dsdgen format drive the script's shape:

1. **Every line ends with a trailing `|`.** `LINES TERMINATED BY '|\n'`
   consumes it instead of producing a spurious extra field.
2. **Empty field means NULL, but `LOAD DATA` does not treat it that way** — it
   writes `0` into a numeric column and `0000-00-00` into a `DATE`. Every
   nullable column is therefore read into a `@variable` and passed through
   `NULLIF`.
3. **`FIELDS ESCAPED BY ''`** disables backslash escaping. The SF=1 data
   contains no backslashes, but a text column legitimately could, and it would
   otherwise be silently eaten.

Data was checked for loader hazards first: no backslashes, no double quotes,
no embedded newlines, and every row has the expected field count.

## Result

Exit 0, **zero warnings, zero errors**. 19,557,376 rows across 25 tables;
3.2 GB on disk.

Every table's loaded row count equals its source file's line count, and the
fact-table counts match the published SF=1 cardinalities:

| Table | Rows | | Table | Rows |
|---|---:|---|---|---:|
| inventory | 11,745,000 | | catalog_returns | 144,067 |
| store_sales | 2,880,404 | | customer | 100,000 |
| customer_demographics | 1,920,800 | | time_dim | 86,400 |
| catalog_sales | 1,441,548 | | date_dim | 73,049 |
| web_sales | 719,384 | | web_returns | 71,763 |
| store_returns | 287,514 | | customer_address | 50,000 |

## Verification

### NULL handling

The thing most likely to go wrong silently:

```
store_sales: 2,880,404 rows
  ss_sold_date_sk IS NULL : 130,093  (4.52%)
  ss_sold_date_sk = 0     : 0
  ss_customer_sk  = 0     : 0
  ss_store_sk     = 0     : 0
```

4.52% NULL matches the ~4.5% measured in the raw file, and **not a single
bogus zero** anywhere in `store_sales`, `catalog_sales` or `web_sales`. The
`NULLIF` routing worked.

### UTF-8 round-trip

Exactly **910** customer rows contain non-ASCII characters — the same count as
the source file. Accented names (É, Ô) survived intact, confirming the
`utf8mb4` choice from [step 5](05-mariadb-design.md).

### Referential integrity — all 107 relationships, zero orphans

Applying the foreign keys for real proved impractical: with a 128 MB buffer
pool each `ALTER TABLE` on `catalog_sales` took ~2.5 minutes, and after 25
minutes only 27 of 107 constraints existed. Extrapolated, roughly three hours,
almost all of it spent building indexes that were then going to be dropped.

The constraints were not needed to answer the question they were being used to
ask. One anti-join per foreign key does it directly, batched into a single pass
per child table (15 statements covering all 107 relationships):

```sql
SELECT 'store_sales' AS child_table,
  SUM(CASE WHEN c.ss_sold_date_sk IS NOT NULL
            AND p0.d_date_sk IS NULL THEN 1 ELSE 0 END) AS ss_d1, ...
FROM store_sales c
  LEFT JOIN date_dim p0 ON c.ss_sold_date_sk = p0.d_date_sk
  ...;
```

```
checked 107 foreign key relationships
ZERO orphan rows - referential integrity holds across the entire data set.
```

Seconds instead of hours, and it validates the same property. The partial
constraints were then dropped, leaving a clean state: **0 foreign keys, 0
secondary indexes**.

## A bug this exposed in the shipped drop script

`ALTER TABLE ... DROP FOREIGN KEY` does **not** remove the index InnoDB created
for that constraint. Worse, the drop script aborted partway because one
constraint had been interrupted mid-creation and did not exist.

`sql/03_drop_foreign_keys.sql` was corrected on both counts — it now uses
`DROP FOREIGN KEY IF EXISTS` and drops the indexes as a second pass:

```sql
ALTER TABLE catalog_returns DROP FOREIGN KEY IF EXISTS cr_cc;
...
ALTER TABLE catalog_returns DROP INDEX IF EXISTS cr_cc;
```
