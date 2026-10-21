# Optimizing the six-bucket `store_sales` query

A TPC-DS style query on MariaDB. It computes the average, count and distinct count of `ss_list_price` for six `ss_quantity` buckets (0-5, 6-10, 11-15, 16-20, 21-25, 26-30), each with an OR filter on list price, coupon amount and wholesale cost. Each bucket is a separate derived table, and the six one-row results are joined side by side.

## Results

| Variant | Index | Time | Compared with original |
|---|---|---|---|
| Original (six selects) | none | 1.77 s | baseline |
| Original (six selects) | `idx_ss_qty_q28` | 0.285 s | about 6.2x faster |
| CASE, single scan | none | 2.7 s | about 1.5x slower |
| CASE, single scan | `idx_ss_qty_q28` | 1.2 s | about 1.5x faster, but about 4x slower than original with index |
| Original, OR reordered | `idx_ss_qty_q28` | 0.277 s | about 6.4x faster |

The very first cold run of the original query took 6.029 s. Later numbers are warm-cache runs, so compare them with each other and not with the cold run.

## What worked: a covering index

```sql
create index idx_ss_qty_q28 on store_sales
  (ss_quantity, ss_list_price, ss_coupon_amt, ss_wholesale_cost);
analyze table store_sales;
```

- Before the index, `idx_ss_qty_cover` held only the quantity (plus two unrelated columns). For every row in a bucket's quantity range, about 137K per bucket, the database had to jump to the main table to read price, coupon and wholesale cost. That was about 412K pages per bucket.
- With the new index all the needed columns are in the index. The plans show `using_index: true` and about 400 pages per bucket, so the main table is never visited.
- Estimated size: roughly 110-130 MB (an estimate from the `show table status` figures: 3,147,832 rows, about 507 MB data, about 1.03 GB existing indexes). Check the real figure with `Index_length` before and after.

## What did not help

- **CASE, single scan** (`query_case_single_scan.sql`): the quantity ranges don't overlap, so the six selects already read each index entry once. A single scan reads the same 825K entries, but every row is then tested 18 times (6 buckets x avg, count, count distinct) and six distinct counts are tracked at once. It was slower without the index and still slower than the six selects with the index.
- **Joins:** each bucket returns one row and the six-way join costs almost nothing. The huge `cost` numbers in the plan (e29) are optimizer estimates for cross joins of one-row tables, not real work.
- **OR reordering** (`query_six_selects_reordered_or.sql`): MariaDB checks OR terms left to right and stops at the first true one, so putting the most often true term first (wholesale cost) saves a few checks. The gain was about 3% (0.285 s to 0.277 s), which is within run-to-run noise.

## Why the index only narrows by quantity

Only `ss_quantity`, the first index column, is used to jump to the right range (`used_key_parts: ss_quantity`). The OR conditions on the other three columns are checked entry by entry after reading, and about 74% of the entries are discarded. One index cannot skip using three OR alternatives, because each would need the data sorted differently.

## Not tested

Reading fewer entries would need one index per OR condition, with `ss_quantity in (0,1,2,3,4,5)` and `union all`. Rough estimate of about 300 MB of extra indexes. At 0.28 s the gain is unlikely to justify it.

## Reproduce

1. Run `analyze format=json` in front of the query and note `r_total_time_ms`.
2. Run each variant 3 times in a row and use the typical time, because the first run after a restart is slower (cold cache).
3. Check that each `store_sales` access shows `using_index: true` and that `pages_accessed` is in the hundreds, not hundreds of thousands.
4. To undo the index: `drop index idx_ss_qty_q28 on store_sales;`

## Files

- `query_six_selects_reordered_or.sql`: the original six selects with the OR terms reordered
- `query_case_single_scan.sql`: the CASE single-scan version