# TPC-DS Q35 Optimization (MariaDB)

## What the query does
Finds customers who bought in a store in 1999 Q1-Q3 **and** also bought via web or catalog in the same period. Groups them by state, gender, marital status and dependent counts, then returns the top 100 groups.

## Result

| | Time |
|---|---|
| Original | 2.9 s |
| With indexes | 0.27 s |

About 10x faster.

## Problem
`web_sales` (~840K rows) and `catalog_sales` (~1.5M rows) were fully scanned (`type = ALL`) to build the `EXISTS` customer lists. No index covered the date and customer columns.

## Fix
Date-first covering indexes, so MariaDB reads only the 1999 date range and gets the customer IDs straight from the index (`Using index`):

```sql
CREATE INDEX idx_ss_date_cust ON store_sales   (ss_sold_date_sk, ss_customer_sk);
CREATE INDEX idx_ws_date_cust ON web_sales     (ws_sold_date_sk, ws_bill_customer_sk);
CREATE INDEX idx_cs_date_cust ON catalog_sales (cs_sold_date_sk, cs_ship_customer_sk);
```

## Not needed
The customer-first indexes were considered but never chosen by the optimizer. Drop them:

```sql
DROP INDEX idx_ss_cust_date ON store_sales;
DROP INDEX idx_ws_cust_date ON web_sales;
DROP INDEX idx_cs_cust_date ON catalog_sales;
```

## Index column order rule
- `(date, customer)`: fast for "which customers bought in this date range?"
- `(customer, date)`: fast for "did this one customer buy in range?"

Same columns, different order, different job.

## How to verify
1. `ANALYZE TABLE store_sales, web_sales, catalog_sales;`
2. Run the query twice and use the second timing (warm cache).
3. `EXPLAIN` should show `ref` and `Using index` on the three sales tables, not `ALL`.

## Optional next steps
- Replace the `date_dim` join with a plain `BETWEEN` on the sales date key.
- Pre-build `DISTINCT` customer sets and join them.
- Drop the redundant `min/avg/sum` columns (constant inside each group) if the output is used for real analysis.