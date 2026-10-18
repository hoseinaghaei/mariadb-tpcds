# TPC-DS Query 86 Optimization

Rollup of web sales by item category and class over 12 months, with a rank inside each parent group.

## Results

| Version | What changed | Time | Speedup vs original |
|---|---|---|---|
| Original | none | 1.25 s | 1.0x |
| Original + index | covering index on `web_sales` | 0.50 s | 2.5x |
| V1 | index + forced join order (`STRAIGHT_JOIN`) | 0.45 s | 2.8x |
| V2 | index + forced join order + sum per item first | 0.074 s | 16.9x |

Timings come from a test dataset. Results will differ on your data, but V2 should keep its lead as the data grows, because it avoids the per-sale `item` lookup.

## What the query does

1. Find the 365 days in the 12 months `d_month_seq` 1176 to 1187 (`date_dim`).
2. Read the `web_sales` rows for those days.
3. Look up each sale's `item` to get its category and class.
4. Add up `ws_net_paid` per category and class, plus subtotals and a grand total (`WITH ROLLUP`).
5. Rank rows inside each parent group, sort, and keep the first 100.

Steps 4 and 5 work on a handful of rows. The cost is in steps 2 and 3, which grow with the number of sales rows in the 12 months.

## Original query

```sql
select * from (
  select
    sum(ws_net_paid) as total_sum,
    i_category,
    i_class,
    (i_category is null)+(i_class is null) as lochierarchy,
    rank() over (
      partition by (i_category is null)+(i_class is null),
                   case when (i_class is null) = 0 then i_category end
      order by sum(ws_net_paid) desc) as rank_within_parent
  from web_sales, date_dim d1, item
  where d1.d_month_seq between 1176 and 1176+11
    and d1.d_date_sk = ws_sold_date_sk
    and i_item_sk = ws_item_sk
  group by i_category, i_class with rollup
) tpcds_rollup
order by lochierarchy desc,
         case when lochierarchy = 0 then i_category end,
         rank_within_parent
limit 100;
```

## What was slow

- **Table reads on `web_sales`.** The index used (`idx_ws_date_cust`) did not contain `ws_net_paid`, so every sales row needed an extra read from the main table.
- **One `item` lookup per sales row.** With millions of sales rows, that is millions of lookups, even though there are far fewer items than sales.
- **Join order left to the optimizer.** It picked a good order here, but nothing guarantees it as the data changes.

## Optimizations

### 1. Covering index (original: 1.25 s to 0.50 s)

```sql
create index idx_ws_date_item_cust
  on web_sales (ws_sold_date_sk, ws_item_sk, ws_bill_customer_sk, ws_net_paid);
```

The index holds the date, item and `ws_net_paid`, so the engine never opens the main table. EXPLAIN shows `Using index` on `web_sales`.

`ws_bill_customer_sk` sits in the index so the same index also serves other queries that need date, item and customer. If you only run this query, `(ws_sold_date_sk, ws_item_sk, ws_net_paid)` is smaller.

If you already have a 3-column version of this index, replace it. Run the drop first, then the create:

```sql
drop index idx_ws_date_item_cust on web_sales;
-- then run the create index statement above
```

### 2. Forced join order (0.50 s to 0.45 s)

```sql
from date_dim d1
     straight_join web_sales on ws_sold_date_sk = d1.d_date_sk
     straight_join item      on i_item_sk = ws_item_sk
where d1.d_month_seq between 1176 and 1176+11
```

The order is `date_dim`, then `web_sales`, then `item`:

- `date_dim` has the only strong filter, and it returns about 365 dates from a covering index.
- `web_sales` is the huge table, and the date-first index reads only the days needed.
- `item` is a primary key lookup, so it goes last.

### 3. Sum per item first (0.45 s to 0.074 s)

Add up sales per item first, then look up `item` once per item instead of once per sale. The result is the same, because a sum of sums gives the same total.

## Final query (V2)

```sql
select * from (
  select
    sum(s.total) as total_sum,
    i_category,
    i_class,
    (i_category is null)+(i_class is null) as lochierarchy,
    rank() over (
      partition by (i_category is null)+(i_class is null),
                   case when (i_class is null) = 0 then i_category end
      order by sum(s.total) desc) as rank_within_parent
  from (
        select ws_item_sk, sum(ws_net_paid) as total
        from   date_dim d1
               straight_join web_sales on ws_sold_date_sk = d1.d_date_sk
        where  d1.d_month_seq between 1176 and 1176+11
        group by ws_item_sk
       ) s
       straight_join item on i_item_sk = s.ws_item_sk
  group by i_category, i_class with rollup
) tpcds_rollup
order by lochierarchy desc,
         case when lochierarchy = 0 then i_category end,
         rank_within_parent
limit 100;
```

## Expected EXPLAIN (V2)

| Table | Type | Key | Extra |
|---|---|---|---|
| `d1` (`date_dim`) | range | `idx_date_month_date` | Using index |
| `web_sales` | ref | `idx_ws_date_item_cust` | Using index |
| `item` | eq_ref | PRIMARY | |

If `web_sales` does not say `Using index`, the covering index is not being used. Check that it exists and that its column order matches the query.

## Index memory and write cost

- A 4-column covering index costs roughly 25 to 35 bytes per row. On a billion-row table that is tens of GB.
- Every index slows inserts into `web_sales`, because each one must be updated.
- A date-first index is friendly to memory: a 12-month query touches only that slice of the index, so the whole index does not need to sit in RAM.
- Look for duplicate indexes (for example `idx_ws_date_cust` and `idx_ws_date_customer`) with `SHOW INDEX FROM web_sales`. Enable `userstat` and read `INDEX_STATISTICS` to find indexes with no reads, then drop them.

## Optional ideas for very large data

- **Date range instead of a date join.** If `d_date_sk` grows with the date (true in TPC-DS), replace the `date_dim` join with one range scan:
  ```sql
  where ws_sold_date_sk between
          (select min(d_date_sk) from date_dim where d_month_seq between 1176 and 1176+11)
      and (select max(d_date_sk) from date_dim where d_month_seq between 1176 and 1176+11)
  ```
  Only use this if your date keys really follow date order.
- **Summary table.** For a report that runs often, keep a small table with one row per day and item, filled by a nightly job:
  ```sql
  create table agg_ws_item_day (
    d_date_sk  int,
    ws_item_sk int,
    net_paid   decimal(15,2),
    primary key (d_date_sk, ws_item_sk)
  );
  ```
  The query then reads this table instead of `web_sales`, with no extra index on the fact table.
- **Partitioning.** Partition `web_sales` by date range so a 12-month query skips old partitions. In MariaDB the partition column must be in every unique key, so the primary key would need to include `ws_sold_date_sk`.

## How to verify

1. Run the original and V2 and compare the output. It should be identical.
2. Run `EXPLAIN` and check the table above.
3. Run `ANALYZE FORMAT=JSON` for real row counts per step.
4. Repeat on a larger dataset. V2 should keep its lead as the data grows.

## Caveats

- `STRAIGHT_JOIN` is a hard rule. If the data changes a lot, for example if the date filter stops being selective, the optimizer cannot adapt. Re-check the plan now and then.
- Timings are from one test dataset and one run each. Repeat a few times, with a warm cache, before drawing conclusions.