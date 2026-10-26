# query 37 — 1.049s → 0.804s (1.30x, SF=4)

Original: [`queries/mariadb/query37.sql`](../../mariadb/query37.sql).
[`query37_v0.sql`](query37_v0.sql) remains an exact copy.
The selected SQL is [`query37_BEST.sql`](query37_BEST.sql), renamed from
`query37_v2_date_bounds_sales_exists.sql` without changing its contents.
Both returned **4 identical ordered rows** in the final SF=4 check.

| File | Recorded time | Change / decision |
|---|---:|---|
| [`query37_v0.sql`](query37_v0.sql) | 1.049s | Original, final comparison control |
| [`query37_v1_sales_exists.sql`](query37_v1_sales_exists.sql) | Not separately timed | Still an unchanged baseline copy; placeholder, not an EXISTS implementation |
| **[`query37_BEST.sql`](query37_BEST.sql)** | **0.804s** | Date/inventory-first joins and one catalog-sale lookup per qualifying item |

## Measurement setup

Local SF=4, seed=10 database: `tpcds_sf4_seed10`. Linux laptop with a Ryzen 5
3500U and about 6.7 GiB of visible RAM; MariaDB 10.11.14, a 2 GiB InnoDB buffer
pool and 16 MiB temporary-table limits. The database had primary keys only;
these rewrites added no secondary indexes or server configuration changes.

The final timings are one sequential original-then-BEST pair, **n=1 per
version**, with the query cache disabled for each connection. Time includes
connection, session setup, SQL execution and complete result transfer. There
was no controlled cache reset. These are local observations, not repeated-run
medians or the final group benchmark. Final-pair timings and checks were
printed during the interactive experiment; their raw outputs and plans were
not saved as repository artifacts. Earlier diagnostic runs are identified
separately below.

## What the query must do

Return distinct item ID, description and current price where:

- Price is 25–55 and manufacturer is one of 677, 739, 684 or 867.
- Some inventory observation has quantity 100–500 between 6 March 2002 and
  5 May 2002, inclusive.
- The item has at least one catalog sale, at any date.

The original `GROUP BY` removes duplicate projected attributes from the
inventory/sales join. Keep that grouping, `ORDER BY i_item_id` and `LIMIT 100`.
The inventory date restriction must not become a catalog-sale date restriction.

## Steps and why they help

1. Keep `date_dim → inventory → item` as the outer join order using
   `SELECT STRAIGHT_JOIN`. The inventory primary key begins with `inv_date_sk`,
   so matching dates can drive its lookups.
2. Remove `catalog_sales` from the main join. Its columns are neither returned
   nor aggregated, so only the existence of a sale matters.
3. An earlier diagnostic retained plain `EXISTS` after fixing the outer order.
   `EXPLAIN` still showed the whole catalog primary index being read for
   materialization. That attempt took **18.642s**, versus **1.510s** for its
   original control; both returned the same 4 rows. That intermediate SQL was
   edited in place and is not retained as another version file.
4. Use a correlated scalar lookup instead:

   ```sql
   AND 1 = (
       SELECT 1
       FROM catalog_sales cs
       WHERE cs.cs_item_sk = i.i_item_sk
       LIMIT 1
   )
   ```

   A match returns 1; no match returns NULL and fails the WHERE condition.
   The final `EXPLAIN` shows `cs` using `ref` on `PRIMARY` with the item key,
   instead of the whole-index materialization. A joined date-bounds CTE from
   the earlier attempt was also removed.

The final 1.30x ratio belongs to the final pair above; these separate diagnostic
runs do not isolate every change's individual contribution.

## Correctness

The final comparison checked full column labels, values, NULLs, duplicate
counts and row order: all 4 rows matched. A separate session-local fixture,
with Q37's own dates, prices, manufacturers and catalog table, also matched
exactly: **A, B, C, K**. It tested duplicate projections, multiple facts, missing
sales, quantity/price/date endpoints, NULLs and an orphan inventory date.
The adapted Q37 fixture was executed in memory, not saved as a fixture file.

No new index is required. The plan still scans the small date dimension and
uses existing primary keys for inventory, item and the catalog lookup.

## Reproduce

From the repository root, with the SF=4/seed=10 database already loaded:

```bash
python3 scripts/sf4.py compare \
  --database tpcds_sf4_seed10 \
  --baseline queries/optimized/q37/query37_v0.sql \
  --optimized queries/optimized/q37/query37_BEST.sql \
  --repeats 3 --timeout 300 \
  --out experiments/local/q37_best_sf4.csv
```

This command runs new alternating comparisons and saves their timings; it
does not reproduce a controlled cold-cache state. It requires the existing
`scripts/sf4.py` helper and MariaDB client on `PATH`.

Separate work: [Nafiz's SF=1 Q37 study](../Nafiz/tier4/q37/README.md) uses a
different dataset/configuration; its absolute times are not this SF=4 control.
