# TPC-DS Query 54: Optimization Notes (MariaDB)

Three versions of TPC-DS query 54, from 23 s down to 0.3 s, using only
query-level techniques (no new tables).

## Files

| File | What it is |
|---|---|
| `query54_Original.sql` | Unmodified TPC-DS query 54 |
| `q54_Optimized_V1.sql` | Filter-first rewrite of `my_customers` |
| `q54_Optimized_V2.sql` | V1 + early dedup + forced join order (`STRAIGHT_JOIN`) |

> `q54_Optimized_V1.sql` and `q54_Optimized_V2.sql` start with `EXPLAIN`.
> Remove that line to get results and timings instead of the plan.

## Results

| Version | Time | Main idea |
|---|---|---|
| Original | 23 s | Unions both full fact tables, filters afterwards |
| V1 | 4.5 s | Filter each fact table first, then union |
| V2 | 0.3 s | V1 + dedup before joining `customer` + forced join order |

## What the query does

1. **`my_customers`**: customers who bought Women / swimwear from catalog or web
   in July 2000.
2. **`my_revenue`**: for those customers, total store purchases over the next
   three months (`d_month_seq` +1 to +3), only at stores in the same county and
   state as the customer's current address.
3. **`segments`**: revenue bucketed into 50-dollar segments, then customers
   counted per segment.

## Constraints

- No new tables.
- Allowed techniques: filter first, optimizer hints to force execution order,
  join reordering.
- Indexes are not on that list. The experiment below shows none were needed.

## Original: why it is slow

- `catalog_sales UNION ALL web_sales` is built in full inside a derived table,
  and the date / item filters are applied only after that.
- The Phase B join order (`my_customers`, `store_sales`, `customer_address`,
  `store`, `date_dim`) is left to the optimizer.

## V1: filter first (4.5 s)

- The `date_dim` and `item` filters move inside each union branch, so only the
  July 2000 swimwear sales reach the union.
- Still weak (from the V1 `EXPLAIN`):
  - `customer` is read with a full scan (99,015 rows) and probes the union result.
  - `store` has no join condition to `store_sales`, so the optimizer cross-joins
    it with `date_dim` (BNL join). Every downstream step is multiplied by 12 until
    the county / state filter hits `customer_address`.
  - `store_sales` is entered by date, not by customer.

## V2: forced order and early dedup (0.3 s)

1. **`UNION` instead of `UNION ALL` + `DISTINCT`.** Duplicate customer IDs are
   removed on one integer column before the `customer` join.
2. **`SELECT STRAIGHT_JOIN` in both `my_customers` and `my_revenue`.** Tables are
   joined in the written order.
3. **Join order in `my_revenue`:** `my_customers` -> `customer_address` -> `store`
   -> `store_sales` -> `date_dim`. Small, selective tables run first, and
   `store_sales` is reached through the customer index only for surviving customers.

V2 `EXPLAIN` highlights:
- `customer` is `eq_ref` on its primary key (1 row per lookup).
- `store_sales` is reached via `idx_ss_cust_date` on `ss_customer_sk`.
- `date_dim` is `eq_ref` on its primary key.
- A `UNION RESULT <union3,4>` row confirms the early dedup.

## Flow

```
ORIGINAL                         V1                               V2
catalog_sales + web_sales        date_dim -> fact -> item         date_dim -> fact -> item
  (full, UNION ALL)                (per branch, filtered)           (per branch, filtered)
        |                                |                                |
join date/item/customer          UNION ALL                        UNION (dedup customer_sk)
        |                                |                                |
apply filters (too late)         join customer, DISTINCT          join customer by PK
        |                                |                                |
DISTINCT                         5-table join, optimizer order    customer_address (PK)
        |                                |                                |
5-table join, optimizer order    SUM, bucket, count               store (county, state)
        |                                                                 |
SUM, bucket, count                                                store_sales (customer index)
                                                                          |
                                                                  date_dim (PK) -> SUM, bucket, count
```

## Why the results are identical

- Same filters and join conditions in every version.
- `UNION` on `customer_sk` gives the same rows as `DISTINCT (c_customer_sk,
  c_current_addr_sk)`, because `customer` is joined on its primary key, so each
  customer has exactly one `c_current_addr_sk`.
- Join order and hints change how the query runs, not what it returns.

To verify, remove the `EXPLAIN` line, then:

```bash
mariadb tpcds < query54_Original.sql  > original.out
mariadb tpcds < q54_Optimized_V1.sql  > v1.out
mariadb tpcds < q54_Optimized_V2.sql  > v2.out
diff original.out v1.out && diff original.out v2.out && echo "identical"
```

## Index experiment

Three indexes were created for V1 (`idx_ws_date_item_cust`, `idx_cs_date_item_cust`,
`idx_ss_cust_date_cover`) and later dropped. V1 kept the same time and the same
`EXPLAIN`, so they were not contributing.

The schema already had equivalent indexes, and these are the ones the plans use:
`idx_cs_date_customer`, `idx_ws_date_cust`, `idx_ss_cust_date`.

Conclusion: the gain from 23 s to 4.5 s comes from the rewrite (filter first),
not from the added indexes.

## Known caveats and open items

- `STRAIGHT_JOIN` in V2 applies only to the two outer `SELECT`s. Inside the union
  branches the optimizer chooses the order. The plan starts at `date_dim` anyway;
  add `STRAIGHT_JOIN` there to lock it in.
- The `<derived3>` row estimate (460,428) is far too high because the optimizer
  ignores the selectivity of the `item` filter. It does not matter once the order
  is forced.
- Not yet measured: how much of the 4.5 s -> 0.3 s gain comes from Phase A
  (`my_customers`) versus Phase B (`my_revenue`). Time two hybrids to find out:
  V1 Phase A + V2 Phase B, and V2 Phase A + V1 Phase B.
- Re-time V2 with the three created indexes dropped, to confirm the 0.3 s does
  not depend on them. Its `EXPLAIN` lists none of them.