# query 82 — 0.732s → 0.687s (1.07x, SF=4)

Original: [`queries/mariadb/query82.sql`](../../mariadb/query82.sql).
[`query82_v0.sql`](query82_v0.sql) remains an exact copy.
The selected SQL is [`query82_BEST.sql`](query82_BEST.sql), renamed from
`query82_v3_date_bounds_sales_exists.sql` without changing its contents.
Both returned **5 identical ordered rows** in the final SF=4 check.

| File | Recorded time | Change / decision |
|---|---:|---|
| [`query82_v0.sql`](query82_v0.sql) | 0.732s | Original, final comparison control |
| [`query82_v1_sales_exists.sql`](query82_v1_sales_exists.sql) | Not separately timed | Still an unchanged baseline copy; placeholder |
| [`query82_v2_both_exists.sql`](query82_v2_both_exists.sql) | 24.569s median, n=3 | Inventory/date EXISTS plus sales EXISTS; correct but rejected as much slower |
| [`query82_exists_instead_of_join.sql`](query82_exists_instead_of_join.sql) | Not separately timed | Byte-for-byte the same SQL as v2 |
| **[`query82_BEST.sql`](query82_BEST.sql)** | **0.687s** | Date/inventory-first joins and a first-match store-sale lookup |

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

Return distinct item ID, description and current price with price 33–63 and
manufacturer 306, 845, 203 or 671. At least one inventory observation must have
quantity 100–500 from 15 January 2000 through that date + 60 days, inclusive.
The item must also have a store sale, with **no sale-date restriction**.

`GROUP BY` removes duplicates on the three output attributes. Different item
surrogate keys can share those attributes, so replacing the sales join does
not justify dropping the grouping. Keep the original ordering and `LIMIT 100`.

## Steps and rejected attempts

1. The original joins inventory observations with every matching store sale,
   although sales only establish presence. The final rewrite removes that
   unnecessary sales multiplicity.
2. v2 put both inventory/date and sales inside `EXISTS`. It was correct but
   slow on this primary-key-only profile. The saved
   [local CSV](../../../experiments/local/sf4_times.csv) contains the
   three-run series `20261025T150255648111Z`: original times were
   **0.783158, 0.697887, 0.694755s**; v2 times were
   **24.833970, 24.526488, 24.568781s**. All five output rows matched in
   each pair. The medians were **0.697887s → 24.568781s**, about 35x slower.
   That local CSV may be absent from another checkout; the figures are
   recorded here without treating it as committed evidence.
3. Restore the outer `date_dim → inventory → item` joins and use
   `SELECT STRAIGHT_JOIN` to preserve that order. The date-leading inventory
   primary key can then serve the matching dates. Remove the joined bounds
   CTE used in an intermediate attempt.
4. Plain sales `EXISTS` still produced whole-sales-index materialization in
   `EXPLAIN`. In that separate diagnostic, original and candidate took
   **2.382s → 35.868s**, with matching results. This intermediate SQL was
   edited in place and is not a retained version file.
5. Replace it with `1 = (SELECT 1 FROM store_sales ss WHERE
   ss.ss_item_sk = i.i_item_sk LIMIT 1)`. The final plan shows an item-key
   `ref` lookup on the sales `PRIMARY` key, stopping after the first match.
   It returns NULL when there is no sale, preserving the exclusion rule.

The final original/BEST difference is only about 0.05s in one pair, so it does
not establish a repeatable 6% gain over the original. The clear finding is
that the selected SQL avoids the large regression seen with v2 and the
materialized-EXISTS attempt. The median v2 series and final single pair are
separate experiments, not a controlled ablation of every step.

## Correctness

The final SF=4 comparison matched all column labels and all 5 ordered rows,
including full values and NULLs. The existing
[`fixture_setup.sql`](fixture_setup.sql), followed by v0 and BEST in one
connection, also matched exactly: **4 rows, A, B, C, K**. It covers multiple
sales/inventory rows, duplicate item attributes, missing matches, inclusive
bounds, a NULL description, filtered NULL values and an orphan inventory date.

No additional index or server configuration change was used.

## Reproduce

From the repository root, with the SF=4/seed=10 database already loaded:

```bash
python3 scripts/sf4.py compare \
  --database tpcds_sf4_seed10 \
  --baseline queries/optimized/q82/query82_v0.sql \
  --optimized queries/optimized/q82/query82_BEST.sql \
  --repeats 3 --timeout 300 \
  --out experiments/local/q82_best_sf4.csv
```

This command runs new alternating comparisons and saves their timings; it
does not reproduce a controlled cold-cache state. It requires the existing
`scripts/sf4.py` helper and MariaDB client on `PATH`.
