# query 97 — build each list once (1.5x-1.8x in back-to-back runs)

Original: `queries/mariadb/query97.sql`.
Every variant produces **identical output** to it: `537217 | 284824 | 145`.

## What the query must do

Count distinct (customer, item) pairs bought in 12 months (`d_month_seq`
1176-1187) through store only, catalog only, or both channels.

MariaDB has no `FULL OUTER JOIN`, so the original emulates it as
`LEFT JOIN ... UNION ALL ... RIGHT JOIN ... WHERE NULL`.

NULL customers never match (`NULL = NULL` is not true) and are excluded by the
`IS NOT NULL` tests, so 6,895 store and 670 catalog pairs fall in no bucket.
Any rewrite must keep that rule.

The official answer set (`540401 | 286628 | 174`) does not match the loaded
data. The result above was recomputed independently from the raw `.dat` files,
so this is a data / answer-set configuration issue, not a query bug.

## Diagnosis (`ANALYZE FORMAT=JSON`, 128 MB buffer pool, 85.8s)

- `ssci` and `csci` are each **built twice**, once per half of the union.
  The four builds took 81.5s of the 85.8s profile; the joins cost about 4s.
- About 50s of that was disk wait (store_sales is ~500 MB, pool was 128 MB).
- Filesort is not the problem (under 100 ms per sort).
- The optimizer estimated 45.5M rows for the union; the real number was 829,751.

## Results (8 GB buffer pool, `time mariadb tpcds < file`)

| File | Change | Best measured time |
|---|---|---:|
| `query97_v0_original.sql` | original | 15.4s |
| **`query97_BEST.sql`** = `query97_v1_temp_tables.sql` | build each list once | **8.7s** |

Best pair: 15.4s -> 8.7s (1.8x). Back-to-back (interleaved) pairs later gave
1.5x-1.8x, and one later pair measured about 36s vs about 5s.

**Timing note:** absolute times on the test laptop varied a lot between runs
for identical data and queries (original 15-39s, optimized 5-27s). Compare
versions only from back-to-back runs, and treat the ratio as the result, not
the raw seconds. The timing method (DBeaver or terminal) did not matter: both
gave the same time for the same file.

The buffer pool change (128 MB -> 8 GB) is a configuration effect and is
reported separately from the query rewrite.

## The rewrite

`ssci` / `csci` are materialized once as temp tables with a
`(customer_sk, item_sk)` key. One `LEFT JOIN` gives `store_and_catalog` and
`store_only`. The second half of the union is replaced by arithmetic:

    catalog_only = COUNT(csci pairs with non-NULL customer) - store_and_catalog

Every csci pair is either matched (already counted as "both") or unmatched
(catalog only), so no second join is needed.

**Caveat:** v1 uses several statements (two `CREATE TEMPORARY TABLE` plus the
`SELECT`). TPC-DS expects one statement per query, so v1 is reported as a
labelled optimization, not as the official query form.

## Reproduce

    for i in 1 2 3; do
      ( time mariadb tpcds < queries/optimized/q97/query97_v0_original.sql ) 2>&1 | grep -E "^[0-9]|real"
      ( time mariadb tpcds < queries/optimized/q97/query97_BEST.sql ) 2>&1 | grep -E "^[0-9]|real"
    done

Each run must print `537217 284824 145`. Run the pairs back to back, with the
machine plugged in and nothing else open.
