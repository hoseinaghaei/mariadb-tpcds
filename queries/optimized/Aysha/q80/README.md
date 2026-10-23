# TPC-DS Query 80 Optimization

## 1. Query Overview

Query 80 calculates total sales, returns and profit across three sales channels: physical stores, catalog pages and websites.

- **Date range:** 28 August – 27 September 1998 (30-day interval added to the start date).
- **Filters:** Items with a current price above 50 and promotions where `p_channel_tv = 'N'`.
- **Aggregation:** Groups results by store, catalog page or website, then calculates channel-level and grand totals using `WITH ROLLUP`.
- **Output:** Sorts results by channel and ID and returns at most 100 rows.

## 2. Optimization Techniques Applied

### A. Indexing

Added two indexes:

```sql
CREATE INDEX idx_dd_date
ON date_dim(d_date);

CREATE INDEX idx_item_price
ON item(i_current_price);
```

- `idx_dd_date`: Helps locate the required date range in `date_dim`.
- `idx_item_price`: Helps locate items satisfying `i_current_price > 50`.

These indexes reduce the need to scan entire tables when the optimizer can use them effectively.

### B. Hardware and Memory Configuration

```sql
SET GLOBAL innodb_buffer_pool_size = 8*1024*1024*1024;

SET SESSION tmp_table_size = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;
```

- **8 GB buffer pool:** Allows MariaDB to cache more table data and indexes in RAM, reducing disk reads.
- **256 MB temporary-table limits:** Allow eligible internal temporary tables to use more memory before spilling to disk.

The effective in-memory temporary-table limit depends on the smaller of `tmp_table_size` and `max_heap_table_size`. These settings can increase memory consumption, so they should be tested against available RAM. <https://mariadb.com/docs/server/server-management/variables-and-modes/server-system-variables>

### C. Replacing Date Joins with Date-Key Range Filtering

**Original approach:**

```sql
ss_sold_date_sk = d_date_sk
AND d_date BETWEEN start_date AND end_date
```

The original query joins each sales table to `date_dim` and filters the date column.

**Optimized approach:**

```sql
WHERE ss_sold_date_sk BETWEEN
    (SELECT MIN(d_date_sk) FROM date_dim
     WHERE d_date BETWEEN '1998-08-28'
                       AND '1998-08-28' + INTERVAL 30 DAY)
AND
    (SELECT MAX(d_date_sk) FROM date_dim
     WHERE d_date BETWEEN '1998-08-28'
                       AND '1998-08-28' + INTERVAL 30 DAY)
```

The optimized version finds the minimum and maximum date keys for the required period and filters the sales table directly using those keys.

- Removes the explicit `date_dim` join from each sales subquery.
- Allows the database to filter sales rows using their date keys.
- Can reduce join overhead and improve filtering efficiency.

**Important assumption:** This range is correct only if the date keys for the selected dates form a continuous range with no unrelated dates between them. Verify this property in the dataset.

### D. Explicit Joins and Filter Placement

The original query uses implicit joins, listing tables separated by commas and specifying join conditions in `WHERE`.

The optimized query uses explicit joins:

```sql
FROM store_sales
JOIN item
    ON i_item_sk = ss_item_sk
   AND i_current_price > 50
JOIN promotion
    ON p_promo_sk = ss_promo_sk
   AND p_channel_tv = 'N'
JOIN store
    ON s_store_sk = ss_store_sk
```

- Makes join relationships easier to read and maintain.
- Places relevant filters alongside their table joins.
- Makes the intended join structure clearer.

Explicit joins do not automatically make a query faster; the actual improvement depends on the execution plan chosen by MariaDB.

### E. String Concatenation

The optimized query replaces expressions such as:

```sql
'store' || store_id
```

with:

```sql
CONCAT('store', store_id)
```

This makes string concatenation explicit for MariaDB. It is mainly a syntax and clarity change, not the expected main source of the speedup.

### F. Preserving Aggregation and Results

The optimized query retains:

- `SUM()` calculations for sales, returns and profit.
- `UNION ALL` to combine the three sales channels.
- `GROUP BY channel, id WITH ROLLUP` to calculate subtotals and grand totals.
- Final sorting and `LIMIT 100`.

These operations are still potentially expensive, but preserving them maintains the intended reporting structure.

## 3. Performance Results

| Query version | Average execution time |
|---|---:|
| Original query, before changes | 0.590 s |
| Original query, with indexes and memory changes | 0.520 s |
| Optimized query, with indexes and memory changes | 0.125 s |

### Performance improvement

**Original versus original with indexes and memory changes**

- Time saved: `0.590 − 0.520 = 0.070 s`
- Reduction: approximately **11.9%**

**Original with changes versus optimized query**

- Time saved: `0.520 − 0.125 = 0.395 s`
- Reduction: approximately **76.0%**
- Speedup: approximately **4.16×**

**Original versus final optimized query**

- Time saved: `0.590 − 0.125 = 0.465 s`
- Reduction: approximately **78.8%**
- Speedup: approximately **4.72×**

## 4. Analysis

The indexes and memory changes reduced the recorded average execution time from **0.590 s to 0.520 s**. The rewritten query then reduced it further to **0.125 s** under the same stated configuration.

The largest additional improvement is associated with the query rewrite, particularly replacing the date-dimension joins with date-key range filtering. However, the individual contribution of each change has not been isolated, so this cannot be attributed to one change with certainty.

For a fair comparison, run both versions several times under the same conditions, compare their returned results and inspect their execution plans using `EXPLAIN` or `ANALYZE`. MariaDB documents these tools for examining join order, index usage and rows examined. <https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/analyze-and-explain-statements/explain>

## 5. Conclusion

Query 80 was optimized using indexing, memory configuration, direct date-key filtering, explicit joins and clearer string concatenation. Its recorded average execution time decreased from **0.590 seconds to 0.125 seconds**, representing an approximately **78.8% reduction**.

The results are promising, but the optimized query should be validated against the original before claiming equivalent output. In particular, verify the date-key range assumption and check that the return-table joins do not multiply sales rows. The same output alone is not sufficient if only a limited subset of rows is compared.