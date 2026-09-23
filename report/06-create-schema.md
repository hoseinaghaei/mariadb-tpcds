# Step 6 — Generate and apply the schema

## Generation

`sql/01_schema.sql` was generated from the parsed specification (step 3), with
the three corrections from [step 4](04-reconcile-discrepancies.md) applied. It
was not hand-written and not copied from `tpcds.sql`, so every column name,
order, datatype, nullability and key comes from Clause 2.3/2.4 by
construction.

Each table carries a comment pointing back at its specification table, so the
DDL can be traced to the PDF:

```sql
) ENGINE=InnoDB ROW_FORMAT=DYNAMIC COMMENT='TPC-DS v4.0.0 Table 2-1';
```

## The script

```
sql/01_schema.sql     22 KB     25 tables, 429 columns, 24 primary keys
```

Structure:

1. `CREATE DATABASE IF NOT EXISTS tpcds` with `utf8mb4` / `utf8mb4_bin`
2. `SET FOREIGN_KEY_CHECKS = 0`
3. `DROP TABLE IF EXISTS` for all 25, in reverse dependency order
4. 25 `CREATE TABLE` statements, dimensions first, then facts, then
   `dbgen_version`
5. `SET FOREIGN_KEY_CHECKS = 1`

**Re-running the script drops and recreates every table**, discarding any
loaded data. That is intentional — it makes the script idempotent — but it is
worth knowing before re-running it on a populated database.

Example output:

```sql
CREATE TABLE store_sales (
    ss_sold_date_sk        BIGINT,
    ss_sold_time_sk        BIGINT,
    ss_item_sk             BIGINT         NOT NULL,
    ss_customer_sk         BIGINT,
    ss_cdemo_sk            BIGINT,
    ss_hdemo_sk            BIGINT,
    ss_addr_sk             BIGINT,
    ss_store_sk            BIGINT,
    ss_promo_sk            BIGINT,
    ss_ticket_number       BIGINT         NOT NULL,
    ss_quantity            BIGINT,
    ss_wholesale_cost      DECIMAL(7,2),
    ss_list_price          DECIMAL(7,2),
    ss_sales_price         DECIMAL(7,2),
    ss_ext_discount_amt    DECIMAL(7,2),
    ss_ext_sales_price     DECIMAL(7,2),
    ss_ext_wholesale_cost  DECIMAL(7,2),
    ss_ext_list_price      DECIMAL(7,2),
    ss_ext_tax             DECIMAL(7,2),
    ss_coupon_amt          DECIMAL(7,2),
    ss_net_paid            DECIMAL(7,2),
    ss_net_paid_inc_tax    DECIMAL(7,2),
    ss_net_profit          DECIMAL(7,2),
    PRIMARY KEY (ss_item_sk, ss_ticket_number)
) ENGINE=InnoDB ROW_FORMAT=DYNAMIC COMMENT='TPC-DS v4.0.0 Table 2-1';
```

Note that only the two primary-key columns are `NOT NULL`. Every foreign key
into a dimension is nullable, which is correct: dsdgen emits NULL surrogate
keys deliberately so the query set exercises outer joins.

## Applying it

```sh
mariadb < sql/01_schema.sql
```

Completed with exit status 0. The only server messages were the expected
`Note (Code 1051): Unknown table` notices from `DROP TABLE IF EXISTS` on a
fresh database.

## Connection note

The Homebrew MariaDB on this machine authenticates via `unix_socket`, so
`mariadb -u root` fails with `ERROR 1698 (28000): Access denied`. Connecting
as the logged-in OS user works and has full privileges:

```
$ mariadb -e "SELECT VERSION(), CURRENT_USER();"
13.0.2-MariaDB    hosseinaghaei@localhost

GRANT ALL PRIVILEGES ON *.* TO `hosseinaghaei`@`localhost` ... WITH GRANT OPTION
```

Every command in this report uses the bare `mariadb` client with no `-u`.

## Result

```
live database 'tpcds': 25 tables, 429 columns, 24 primary keys
engine/row_format/collation: InnoDB / Dynamic / utf8mb4_bin
on-disk size (empty): 3.2 MB
```

Full column-by-column verification is in [step 8](08-verification.md).
