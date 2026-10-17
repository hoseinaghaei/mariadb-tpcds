# Query 9 Optimization

## Changes Made
- Combined the `COUNT(*)` and both `AVG()` calculations for each quantity range into a single subquery, avoiding separate scans for each aggregate.
- Added a covering index on `(ss_quantity, ss_ext_list_price, ss_net_profit)` to support range filtering and retrieve the required values directly from the index.
- Removed the standalone `idx_ss_quantity` index because the new covering index includes `ss_quantity` as its leading column.

## Impact
- Reduced repeated scans of `store_sales` by calculating all three aggregates together for each range.
- The covering index can reduce table lookups and improve performance for these aggregations.
- The query retains the original bucket thresholds and conditional logic.

## Notes
- The index adds storage overhead and may slow down inserts and updates.
- Actual performance improvement should be confirmed by comparing execution times and verifying the execution plan with `EXPLAIN`.
