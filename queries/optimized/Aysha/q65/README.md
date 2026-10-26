# TPC-DS Query 65: Optimization Notes

## What the query does

Finds items that sell badly in each store: items whose 12-month revenue (`d_month_seq` 1176-1187) is at most 10% of the average item revenue in that store. Returns the first 100 rows by store name and item description.

Tables: `store_sales` (large fact table), `date_dim`, `store`, `item`.

## Constraints

- No new tables.
- Allowed: filter first, hints (`straight_join`), join reordering, indexes, session settings.

## Problems in the original plan (SF4, 41.7 s)

- The same heavy subquery (sum of sales per store and item) runs twice, about 19-21 s each.
- Each copy scans all 11.5M `store_sales` rows and then does 11M one-by-one lookups into `date_dim`, which keeps only 20% of the rows.
- The `item` join runs 477k times, although only about 3.4% of rows pass the low-seller filter.

## Changes

1. **Date first.** `date_dim` is read first (365 matching days), then only those days are read from `store_sales`.
2. **Covering index.** All columns the query needs are in the index, so `store_sales` is read from the index only. It replaces the old index (same leading columns), so there is no extra storage.
3. **Heavy work once.** A window function (`avg(sum(...)) over (partition by ss_store_sk)`) replaces the second subquery.
4. **Filter before `item`.** The low-seller filter now runs before the join, so `item` lookups fell from 477k to 16k.
5. **More sort memory.** The first optimized run spilled its sort to disk (4 passes). Bigger session buffers keep it in memory.

```sql
drop index idx_ss_date_store_item on store_sales;
create index idx_ss_date_store_item_price
  on store_sales (ss_sold_date_sk, ss_store_sk, ss_item_sk, ss_sales_price);

set session sort_buffer_size    = 64*1024*1024;
set session tmp_table_size      = 512*1024*1024;
set session max_heap_table_size = 512*1024*1024;
```

```sql
select s_store_name, i_item_desc, lo.revenue,
       i_current_price, i_wholesale_cost, i_brand
from (
    select straight_join
           ss_store_sk, ss_item_sk,
           sum(ss_sales_price) as revenue,
           avg(sum(ss_sales_price)) over (partition by ss_store_sk) as ave
    from date_dim
    join store_sales on ss_sold_date_sk = d_date_sk
    where d_month_seq between 1176 and 1176+11
    group by ss_store_sk, ss_item_sk
) lo
join store on s_store_sk = lo.ss_store_sk
join item  on i_item_sk  = lo.ss_item_sk
where lo.revenue <= 0.1 * lo.ave
order by s_store_name, i_item_desc
limit 100;
```

## Results (SF4)

| Version | Time |
|---|---|
| Original | about 40 s |
| Optimized (index + rewrite), default memory | 17.7 s (analyze) |
| Optimized + larger sort/temp memory | 2.25 s (analyze) |

About 18x faster than the original.

## What is left

About 1.7 s of the 2.2 s is grouping 2.2M rows into 498k groups. The `item` join is about 0.04 s, so an index on `item` would not help. An index led by `(ss_store_sk, ss_item_sk, ...)` to avoid the sort is not expected to pay off now, because the sort takes only about 0.2 s.

## Notes

- The `set session` lines apply per connection, so put them at the top of the script. Use large buffers for benchmark sessions only.
- Window functions need MariaDB 10.2 or later.
- Compare the output rows against the original to confirm the results match.
- For the larger scale test, check `analyze` for `r_sort_passes` (should be absent or 1) and for no on-disk temporary table. Record the index size and time here.