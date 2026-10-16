# TPC-DS Query 14-A — Optimization

## Overview

Q14-A compares sales across the **store, catalog, and web** channels.

The query:

1. Calculates November 2000 sales for all three channels (`u`).
2. Finds brand/class/category combinations that had sales in **all three channels during 1998–2000** (`ct`).
3. Calculates the overall average sale value across the three channels for 1998–2000 (`av`).
4. Keeps November 2000 groups whose sales are **greater than the overall average**.
5. Uses `ROLLUP` to produce subtotals and the grand total.

## Main Optimizations

* Replaced repeated joins to `date_dim` with **date-key ranges** using `MIN(d_date_sk)` and `MAX(d_date_sk)`.
* Replaced large fact-table joins in the eligibility check with **`EXISTS`**, reducing unnecessary rows.
* Used **`STRAIGHT_JOIN`** to control join order and encourage more efficient execution.
* Calculated the average using **`SUM / COUNT`** instead of materializing a large `UNION ALL` before applying `AVG()`.
* Moved the eligibility check to a smaller set of **brand/class/category combinations** before the final filtering.

## Query Flow

```text
u   → November 2000 sales by channel
        ↓
ct  → combinations present in Store + Catalog + Web (1998–2000)
        ↓
JOIN → keep only matching combinations
        ↓
av  → overall average sale value (1998–2000)
        ↓
WHERE u.sales > av.average_sales
        ↓
ROLLUP → subtotals + grand total
        ↓
ORDER BY + LIMIT 100
```

## Result

The optimized query produces the **same result as the original Q14-A** while significantly reducing execution time.
