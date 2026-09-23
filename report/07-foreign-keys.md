# Step 7 — Port and validate referential integrity

## Status: built and verified, **not currently applied**

The foreign keys work — they were applied to the live database, counted, and
removed again. They are deliberately left off. The reasoning is below.

## The scripts

```
sql/02_foreign_keys.sql        15 KB    107 ALTER TABLE ... ADD CONSTRAINT
sql/03_drop_foreign_keys.sql   12 KB    107 constraint drops + 107 index drops
```

`02` is a port of `tools/tpcds_ri.sql` with the five defects found in
[step 4](04-reconcile-discrepancies.md) corrected: two constraints naming
non-existent columns removed, three duplicate constraint names suffixed `_2`.
Each correction is documented in the file header.

Foreign keys per table:

| Table | FKs | | Table | FKs |
|---|---:|---|---|---:|
| `catalog_returns` | 18 | | `customer` | 6 |
| `catalog_sales` | 17 | | `catalog_page` | 3 |
| `web_sales` | 17 | | `inventory` | 3 |
| `web_returns` | 14 | | `promotion` | 3 |
| `store_returns` | 10 | | `web_page` | 3 |
| `store_sales` | 9 | | `call_center`, `web_site` | 2 each |
| | | | `household_demographics`, `store` | 1 each |

Most are fact→dimension. A few are fact→fact — a return row references the
sale it reverses, via a composite key:

```sql
ALTER TABLE catalog_returns ADD CONSTRAINT cr_i_on
  FOREIGN KEY (cr_item_sk, cr_order_number)
  REFERENCES catalog_sales (cs_item_sk, cs_order_number);
```

## Validation performed

```
before        -> FKs=0   secondary indexes=0
after  02     -> FKs=107 secondary indexes=97
after  03     -> FKs=0   secondary indexes=0
```

All 107 constraints were created without error, and the round trip is clean.

## A trap in dropping foreign keys

InnoDB creates a secondary index for every foreign key that has no usable
index already, and **`ALTER TABLE ... DROP FOREIGN KEY` does not remove that
index.** The first version of `03_drop_foreign_keys.sql` dropped only the
constraints and left all 97 indexes behind — the storage and write cost
survives the constraint that caused it.

`03` therefore does both:

```sql
-- step 1: drop the constraints
ALTER TABLE catalog_returns DROP FOREIGN KEY cr_cc;
...
-- step 2: drop the indexes MariaDB created for them
ALTER TABLE catalog_returns DROP INDEX IF EXISTS cr_cc;
...
```

`IF EXISTS` is needed on the index drops: 107 constraints produced only 97
indexes, because InnoDB reuses an existing index when one already covers the
foreign key columns (a primary key prefix, for instance). Ten constraints have
no index of their own to drop.

## Why they are not applied

1. **The specification makes them optional.** Clause 2.5.1.8: *"The definition
   of primary and foreign keys is optional."*
2. **97 secondary indexes on empty tables would badly slow the data load.**
   Every insert into the 11.7M-row `inventory` and 2.9M-row `store_sales`
   tables would maintain those indexes and check each parent table. Loading
   first and constraining afterwards is the standard order for exactly this
   reason.
3. **They roughly double the database size.** Index entries on high-cardinality
   surrogate keys are not cheap.

## When to apply them

**After loading the data**, if referential integrity is wanted:

```sh
mariadb < sql/02_foreign_keys.sql
```

Applied to populated tables, this also *validates* the data: it will fail if
any fact row references a dimension key that does not exist. That is a useful
end-to-end check on the load.

To reverse it, including the indexes:

```sh
mariadb < sql/03_drop_foreign_keys.sql
```

Skip `02` entirely if the goal is only to run the TPC-DS query set — the
queries join on these columns but do not require the constraints to exist.
