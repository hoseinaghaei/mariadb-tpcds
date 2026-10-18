# Query 60 (Q60) Optimization

## Overview
This document describes the optimization of TPC-DS Query 60 in MariaDB. The optimization focused on adding indexes and changing the join order using `straight_join`.

## Performance Results

| Version | Optimization | Execution Time |
|---|---|---:|
| Original | Original TPC-DS query | 1.00 s |
| Version 1 | Added indexes | 0.48 s |
| Version 2 | Added indexes + `straight_join` with a revised join order | 0.36 s |

## Optimizations Applied

### 1. Indexing
Indexes were added to improve filtering and join performance across the sales and item tables.

The indexes added were:

```sql
create index idx_ss_date_addr_item_price
on store_sales (
    ss_sold_date_sk,
    ss_addr_sk,
    ss_item_sk,
    ss_ext_sales_price
);

create index idx_cs_date_addr_item_price
on catalog_sales (
    cs_sold_date_sk,
    cs_bill_addr_sk,
    cs_item_sk,
    cs_ext_sales_price
);

create index idx_ws_date_addr_item_price
on web_sales (
    ws_sold_date_sk,
    ws_bill_addr_sk,
    ws_item_sk,
    ws_ext_sales_price
);

create index idx_item_category_id
on item (i_category, i_item_id);
```

These indexes support date filtering, address and item lookups, category filtering and access to the sales-price columns.

### 2. Join Order Optimization
The original query used comma-separated table references, allowing MariaDB's optimizer to determine the join order.

The revised query uses `straight_join` to force the following join order in each common table expression (CTE):

- `date_dim` → sales table → `customer_address` → `item`

The sales table differs for each CTE:
- `ss`: `store_sales`
- `cs`: `catalog_sales`
- `ws`: `web_sales`

Starting with `date_dim` allows the query to filter dates to September 2000 before joining the sales data. The address and item tables are then joined to apply the remaining conditions.

## Results and Analysis

The original query took approximately **1.00 second**. Adding indexes reduced execution time to **0.48 seconds**, an improvement of approximately **52%**.

Applying `straight_join` with the revised join order reduced execution time further to **0.36 seconds**, representing an overall improvement of approximately **64%** compared with the original query.

The final version was approximately **2.78 times faster** than the original.

## Conclusion

The results show that indexing and join-order optimization improved the performance of TPC-DS Query 60. Indexing provided the largest individual improvement, while forcing the join order with `straight_join` provided an additional reduction in execution time.

Execution times may vary depending on caching and database conditions, so repeated runs are recommended to confirm the results.