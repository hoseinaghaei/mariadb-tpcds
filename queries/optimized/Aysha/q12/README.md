# TPC-DS Web Sales Revenue Query: Join Order Optimization

Forces the join order `date_dim → web_sales → item` so MySQL/MariaDB filters on the date range first instead of scanning `item` and probing `web_sales` for every item.

## Index

```sql
CREATE INDEX idx_ws_date_item_price
  ON web_sales (ws_sold_date_sk, ws_item_sk, ws_ext_sales_price);

-- Rollback
DROP INDEX idx_ws_date_item_price ON web_sales;
```

It is a covering index: the join keys and the summed column are all in the index, so there are no base-table reads.

## Query change

Original: `FROM web_sales, item, date_dim ...`, where the optimizer chose `item → web_sales → date_dim`.

Optimized: `SELECT STRAIGHT_JOIN ... FROM date_dim STRAIGHT_JOIN web_sales ON ws_sold_date_sk = d_date_sk STRAIGHT_JOIN item ON ws_item_sk = i_item_sk ...`

Filters, `GROUP BY`, window function, and `ORDER BY` are unchanged. All joins are inner, so the result set is identical.

## Results (EXPLAIN ANALYZE)

| | Original | Optimized |
|---|---|---|
| Join order | item → web_sales → date_dim | date_dim → web_sales → item |
| date_dim | ~217K PK lookups | 1 full scan, 73K rows (31 survive) |
| web_sales | ~217K rows | ~6.6K rows (31 loops × ~213) |
| item | 1 full scan, 18K rows | ~6.6K PK lookups |
| Pages: date_dim / web_sales / item | 437K / 20.7K / 622 | 672 / 104 / 13.5K |
| Total time | 271.5 ms | 34.2 ms (~8x faster) |

## Why it's faster

- The date range is the most selective filter (about 31 of 73K dates), so it goes first.
- `web_sales` is read by index range on `ws_sold_date_sk`, about 33x fewer rows.
- `item` is reached by PK lookup only for the surviving rows. The category filter is applied there.

## Caveats and next steps

- `date_dim` is still a full scan, since there is no index on `d_date`. Add one to turn the 73K-row scan into a 31-row range scan:
```sql
  CREATE INDEX idx_date_dim_d_date ON date_dim (d_date);
```
- `item` PK lookups touch many pages (13.5K). `item(i_category, i_item_sk)` may help.
- The optimizer `cost` is higher for the optimized plan (29,105 vs 750) because of inflated row estimates. Real runtime is much lower, so trust the measured times.
- `STRAIGHT_JOIN` pins the plan and won't adapt if the date range or data distribution changes. Re-check with `EXPLAIN ANALYZE` after changes.