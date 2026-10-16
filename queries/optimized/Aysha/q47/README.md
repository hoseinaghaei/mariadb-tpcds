# TPC-DS Q47 optimization notes

Query-only tuning (no new tables, no schema changes). Works on MySQL 8.0+ and MariaDB 10.2+.

## Results

| Version | Time | What it is |
|---|---|---|
| Original | ~32 s | `v1` built 3 times, self-joined on `rn` |
| Query A | ~6-7 s | Date-first join + `LAG`/`LEAD` |
| Query B | ~3 s | Query A + pre-aggregation + index hint |

## What the query does

For each category, brand and store, it finds months in **2000** whose sales are **more than 10% above or below** that group's yearly monthly average. It shows the previous and next month's sales next to each flagged month, and returns the 100 steepest drops first.

## Why the original was slow

- It started from `item` and read **all years** of `store_sales`, checking the date only afterwards.
- It built `v1` (join, `GROUP BY`, windows) **three times**, once each for current, lag and lead.
- It grouped on **four text columns** over every joined sales row.

## Changes

| # | Change | Query A | Query B | Why it helps |
|---|---|---|---|---|
| 1 | Join order: `date_dim` first (`STRAIGHT_JOIN`) | yes | yes | Date filter cuts rows before `store_sales` is read |
| 2 | Date filter: three-way `OR` becomes `d_date BETWEEN '1999-12-01' AND '2001-01-31'` | yes | yes | One range, same 14 months |
| 3 | `v2` self-join on `rn` becomes `LAG` / `LEAD` | yes | yes | `v1` built once instead of three times |
| 4 | Added `psum IS NOT NULL AND nsum IS NOT NULL` | yes | yes | Keeps results identical to the old inner join |
| 5 | Pre-aggregate on integer keys (`monthly` CTE) | no | yes | Text `GROUP BY` runs on far fewer, narrower rows |
| 6 | `FORCE INDEX (idx_ss_date_item_store_cover)` | no | yes | Reads only the 14 months straight from the covering index |
| 7 | `STRAIGHT_JOIN` on `monthly` then `item`, `store` | no | yes | Small result drives cheap primary-key lookups |

## How each one flows

**Original:** join 4 tables, group, add avg and rank (x3), self-join, filter, sort, limit.

**Query A:** join 4 tables (date first), group, add avg + `LAG` + `LEAD` in one pass, filter, sort, limit.

**Query B:** sum sales per item/store/month (integers only), attach names and regroup, add avg + `LAG` + `LEAD`, filter, sort, limit.

## Same results?

The logic is unchanged. Rows are dropped, kept and sorted by the same rules. Rows that tie on both sort keys may come back in a different order. Before relying on it, compare the row count and top rows against the original.

## Verify with EXPLAIN

- `date_dim` is the first table.
- `store_sales` shows `key = idx_ss_date_item_store_cover` and `Using index` (Query B).
- One `DERIVED` block for `v1`, not three.

If `FORCE INDEX` makes Query B slower, remove that one hint and re-test.

## Optional (session only)

```sql
SET SESSION tmp_table_size      = 512*1024*1024;
SET SESSION max_heap_table_size = 512*1024*1024;
```

Keeps temp tables in memory instead of spilling to disk. Check with `SHOW SESSION STATUS LIKE 'Created_tmp%tables';` (`Created_tmp_disk_tables` should not climb).