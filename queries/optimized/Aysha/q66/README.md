# SQL Query 66 Optimization Using Indexing and join seqeuncing reorder

## Overview

This project focuses on optimizing the execution time of a SQL query by creating appropriate indexes and improving the query structure. The query retrieves warehouse information and shipping carrier data for the year 1998 by combining data from multiple tables.

The optimization process was carried out in multiple stages to evaluate the impact of indexing on query performance. First, the original query was executed without additional indexes. Then, indexes were added to the `web_sales` and `catalog_sales` tables. Finally, the SQL query was optimized further while retaining both indexes.

The results demonstrate how a combination of indexing and query optimization can significantly reduce execution time.

## Objective

The main objectives of this project are:

- Analyze the performance of the original SQL query.
- Create indexes on frequently accessed columns to improve data retrieval.
- Measure the performance impact of indexing individual tables and multiple tables.
- Optimize the SQL query structure to reduce execution time.
- Compare execution times before and after optimization.

## Database Tables Involved

The query accesses the following tables:

| Table | Purpose |
|---|---|
| `ship_mode` | Stores shipping mode and carrier information. |
| `date_dim` | Provides date-related information, including the year and date key. |
| `web_sales` | Contains web sales transactions. |
| `catalog_sales` | Contains catalog sales transactions. |
| `time_dim` | Provides information about the time associated with a sales transaction. |
| `warehouse` | Stores warehouse details, including name, location and size. |

The query combines shipping, date, sales, time and warehouse information to produce the final results.

## Indexing Strategy

Two composite indexes were created to improve the performance of the sales-related joins.

### 1. Index on `web_sales`

```sql
CREATE INDEX idx_ws_q66 ON web_sales
(
    ws_ship_mode_sk,
    ws_sold_date_sk,
    ws_sold_time_sk,
    ws_warehouse_sk,
    ws_sales_price,
    ws_quantity,
    ws_net_paid_inc_ship
);
```

The `idx_ws_q66` index contains columns used for joining sales records with shipping modes, dates, time information and warehouses. It also includes additional sales-related columns used by the query.

This index allows the database to retrieve matching sales records more efficiently. Including the additional columns may also allow the database to satisfy parts of the query directly from the index, reducing the need to access the underlying table.

### 2. Index on `catalog_sales`

```sql
CREATE INDEX idx_cs_q66 ON catalog_sales
(
    cs_ship_mode_sk,
    cs_sold_date_sk,
    cs_sold_time_sk,
    cs_warehouse_sk,
    cs_ext_sales_price,
    cs_quantity,
    cs_net_paid_inc_tax
);
```

The `idx_cs_q66` index follows a similar strategy for the `catalog_sales` table.

It includes columns used for joins and additional sales-related columns accessed by the query. This helps improve the retrieval of matching catalog sales records.

### Why Composite Indexes?

Composite indexes contain multiple columns in a specific order. They can improve performance when a query filters or joins records using the leading columns of an index.

In this project, the indexes were designed to support the sales-table joins and provide additional columns required by the query.

The performance benefits depend on the query execution plan, data distribution and how effectively the database can use the indexed columns.

## Query Execution and Join Sequence

The query combines two result sets using `UNION`.

### First SELECT

The first part processes web sales data using the following join sequence:

1. `ship_mode`
2. `date_dim`
3. `web_sales`
4. `time_dim`
5. `warehouse`

### Second SELECT

The second part processes catalog sales data using the following join sequence:

1. `ship_mode`
2. `date_dim`
3. `catalog_sales`
4. `time_dim`
5. `warehouse`

Both parts apply the relevant filtering conditions and retrieve the required warehouse information. Their results are then combined using `UNION`.

The execution plan shows that the database uses the composite indexes on `web_sales` and `catalog_sales` to retrieve matching sales records.

## Performance Evaluation

The query was tested under different configurations to evaluate the impact of indexing and query optimization.

### Execution Time Results

| Configuration | Execution Time |
|---|---:|
| Original query — warm run | 11.9 seconds |
| Original query — cold run | 28.2 seconds |
| Original query with `web_sales` index | 7.93 seconds |
| Original query with both sales-table indexes | 1.54 seconds |
| Optimized query with both indexes | 0.46 seconds |

*Note: The warm and cold measurements refer to different cache conditions. The other execution times are reported from the respective tests.*

### Performance Improvement

The original query took 11.9 seconds during a warm run. After adding the index to `web_sales`, execution time decreased to 7.93 seconds.

Adding the second index to `catalog_sales` reduced execution time further to 1.54 seconds. Finally, optimizing the SQL query while retaining both indexes reduced execution time to 0.46 seconds.

Using the original warm execution time as the baseline:

- **With the `web_sales` index:** approximately 33.4% less execution time.
- **With both indexes:** approximately 87.1% less execution time.
- **With both indexes and the optimized query:** approximately 96.1% less execution time.

The optimized query is approximately **25.9 times faster** than the original warm-run query.

These calculations use the reported execution times and compare the original warm run with each subsequent configuration.

## Results and Observations

The experiments produced several important observations.

### 1. Indexing `web_sales` Improved Performance

Creating the composite index on `web_sales` reduced execution time from 11.9 seconds to 7.93 seconds in the reported tests.

This indicates that improving access to the web sales data helped reduce the overall query execution time.

### 2. Indexing Both Sales Tables Produced a Larger Improvement

After creating an additional index on `catalog_sales`, execution time decreased to 1.54 seconds.

The improvement suggests that both sales tables contribute significantly to the query's execution cost. Optimizing access to both tables produced a greater benefit than indexing `web_sales` alone.

### 3. Query Optimization Further Reduced Execution Time

With both indexes in place, the optimized query executed in 0.46 seconds.

This demonstrates that indexing alone was not responsible for the entire performance improvement. The combination of the indexes and the revised query structure produced the best result among the tested configurations.

### 4. Cold and Warm Runs Can Differ Significantly

The original query took 28.2 seconds during a cold run compared with 11.9 seconds during a warm run.

This difference highlights the importance of cache conditions when benchmarking SQL queries. Data and index pages already available in memory can reduce the time required for subsequent executions.

For a fair comparison, queries should be tested under clearly documented and consistent conditions.

## Conclusion

This project demonstrates the impact of composite indexing and SQL query optimization on query execution performance.

The original query required 11.9 seconds during a warm run. Creating an index on `web_sales` reduced the execution time to 7.93 seconds, while adding an index on `catalog_sales` reduced it further to 1.54 seconds.

The best result was achieved by optimizing the SQL query while retaining both indexes, reducing execution time to just 0.46 seconds.

Overall, the experiments show that **effective indexing combined with query optimization can significantly improve database performance**. They also highlight the importance of analyzing query execution plans, selecting suitable index columns and conducting performance tests under controlled conditions.

The results provide a practical example of how database tuning techniques can reduce query execution time and improve the efficiency of analytical workloads.