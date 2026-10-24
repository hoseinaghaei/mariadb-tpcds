# Query 8 optimization

- `v0_original`: original TPC-DS SQL.
- `v1_date_range`: adds only the equivalent 2000-Q2 date-key range.
- `v2_reordered`: keeps the range and puts `date_dim` before `store_sales` in SQL order.
- `v3_datefirst`: keeps both prior changes and adds a date-first `JOIN_PREFIX` hint.

Every version returned the same empty result set on this SF=1 data. The report and CSV contain the measured comparison.
