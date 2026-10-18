# TPC-DS Query Optimization

## Overview

This query calculates the average quantity, list price, coupon amount and sales price for each item based on catalog sales in 1998. The results are filtered by customer demographics and promotion channel conditions, grouped by item ID and sorted in ascending order.

The optimization focuses on improving join execution, reducing the cost of filtering and leveraging suitable indexes in MariaDB.

## Query Details

- **Dataset:** TPC-DS
- **Query type:** Analytical aggregation
- **Tables involved:** `date_dim`, `catalog_sales`, `customer_demographics`, `item`, `promotion`
- **Filtering conditions:**
  - Sales year: `1998`
  - Gender: `F`
  - Marital status: `S`
  - Education status: `Unknown`
  - Promotion channel: Email or event channel equals `N`
- **Aggregation:** Average sales measures grouped by `i_item_id`
- **Output:** First 100 items ordered by `i_item_id`

## Optimization Techniques

### 1. Composite Indexes

The following indexes were introduced to improve filtering, joins and data retrieval.

**Date dimension index**
```sql
CREATE INDEX idx_date_year_sk
ON date_dim (d_year, d_date_sk);
```
Allows MariaDB to filter dates by year and efficiently retrieve the corresponding date keys.

**Customer demographics index**
```sql
CREATE INDEX idx_cd_filter_sk
ON customer_demographics (
    cd_gender,
    cd_marital_status,
    cd_education_status,
    cd_demo_sk
);
```
Supports filtering customers by gender, marital status and education status while providing the demographic key required for joining.

**Catalog sales covering index**
```sql
CREATE INDEX idx_cs_date_cover
ON catalog_sales (
    cs_sold_date_sk,
    cs_bill_cdemo_sk,
    cs_item_sk,
    cs_promo_sk,
    cs_quantity,
    cs_list_price,
    cs_coupon_amt,
    cs_sales_price
);
```
Covers the date, customer demographic, item and promotion join columns, along with the measures used in the aggregate calculations. This can reduce the need to access the underlying table rows.

### 2. Join Order Optimization Using `STRAIGHT_JOIN`

The optimized query replaces the original comma-separated table list with explicit `STRAIGHT_JOIN` operations.

Unlike a regular join, `STRAIGHT_JOIN` instructs MariaDB to process the tables in the order specified in the query. This provides control over the join order and can prevent the optimizer from selecting a less efficient execution plan.

The chosen order is:

1. `date_dim`
2. `catalog_sales`
3. `customer_demographics`
4. `item`
5. `promotion`

Starting with `date_dim` allows the query to filter the data to the year 1998 before joining the matching catalog sales records. Subsequent joins apply the demographic conditions and retrieve the required item and promotion information.

**Note:** The effectiveness of a forced join order depends on the dataset, indexes, statistics and execution plan. The observed performance improvement should be validated using the same data and execution conditions.

## Performance Comparison

| Query version | Execution time |
|---|---:|
| Original query, without added indexes | 3.7 seconds |
| Original query, with indexes | 1.2 seconds |
| Optimized query using `STRAIGHT_JOIN` and indexes | 0.2 seconds |

### Performance Improvement

- **Index-based optimization:** Reduced execution time from 3.7 seconds to 1.2 seconds, an improvement of approximately **67.6%**.
- **Final optimized query:** Reduced execution time from 3.7 seconds to 0.2 seconds, an improvement of approximately **94.6%**.
- **Additional improvement over the indexed original:** Reduced execution time from 1.2 seconds to 0.2 seconds, approximately **83.3%**.

The final optimized query runs approximately **18.5 times faster** than the original query in the recorded tests.

## Conclusion

The optimization combines composite indexes with an explicitly controlled join order. Indexes improve the efficiency of date and demographic filtering and help retrieve the required catalog sales data, while `STRAIGHT_JOIN` controls the sequence in which MariaDB processes the tables.

The measured execution time decreased from **3.7 seconds to 0.2 seconds**, demonstrating a substantial improvement for this TPC-DS query under the tested conditions.

These results are specific to the tested MariaDB environment and dataset. For reproducibility, the timings should be measured under consistent conditions, and the final execution plan should be checked to confirm that the intended indexes are being used.