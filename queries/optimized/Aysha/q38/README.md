# Query Optimization: Customer Sales Across All Channels

**Query:** TPC-DS Hot Customers

**Objective:** Identify distinct customer name and date combinations appearing in store, catalog and web sales during a 12-month period.

### Optimizations Applied
- **Composite indexes:** Added date-customer indexes to all three sales tables to improve filtering and joins.
- **Date index:** Added `(d_month_seq, d_date_sk)` to accelerate date filtering.
- **Temporary table memory:** Increased `tmp_table_size` and `max_heap_table_size` to 256 MB.
- **Join buffer:** Increased `join_buffer_size` to 8 MB.
- **Optimizer settings:** Enabled semijoin, materialization and first-match optimizations.

### Notes
- Session settings apply only to the current database connection.
- Indexes persist until explicitly dropped.
- Performance improvements depend on the execution plan and workload.
