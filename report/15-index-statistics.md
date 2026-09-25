# Step 15 — Index usage statistics

> **Snapshot caveat:** query 72 had not finished when these counts were taken
> (it was past 24 minutes and is the query that also had to be abandoned in the
> timed run). Its contribution is missing, so the "unused" set is an upper
> bound — it can only shrink. Re-run the queries at the end of this document to
> refresh.

Observability was enabled (`userstat`, `performance_schema`, slow query log,
all 179 InnoDB metrics) and all 99 queries re-run against the indexed database
so `INFORMATION_SCHEMA.INDEX_STATISTICS` would record which indexes actually
get read.

Configuration lives in `/opt/homebrew/etc/my.cnf.d/tpcds-observability.cnf`,
a drop-in that the existing `!includedir` picks up. Deleting that one file and
restarting reverts everything.

> Statistics were flushed to zero before the run, so the numbers below describe
> exactly these 99 queries. The run used four parallel agents, so **wall times
> from it are contended and are not measurements** — they were written to a
> separate `results/instrumented/` tag and are not used for timing anywhere.
> Index read counts are unaffected by contention.

---

## Finding 1 — 81 of the 117 indexes were never read

| | |
|---|---:|
| Secondary indexes defined | **117** |
| Secondary indexes actually read | **36** |
| **Never touched by any of the 98 completed queries** | **81 (69%)** |

Those 81 cost storage, cost time on every insert and update, and enlarge the
optimizer's search space — for nothing. Whole groups are dead:

- **`catalog_returns`** — 15 of its 17 indexes unused
- **`web_returns`** — 11 of 14 unused
- **`catalog_sales`** — 13 of 18 unused
- **`store_returns`** — 6 of 10 unused
- Both of the hand-picked composites `idx_store_sales_1` and
  `idx_store_sales_2` were never used, as was
  `idx_customer_demographics_1`

The index set is inherited wholesale from the reference repo, which built it by
indexing essentially every foreign key column. At this scale factor and on this
query set, most of that never pays.

## Finding 2 — the indexes that *are* used are being read many times over

`ROWS_READ` divided by the table's row count gives a read amplification: how
many times the equivalent of the whole table was pulled through that index.

| Table | Index | Rows read | Table rows | Amplification |
|---|---|---:|---:|---:|
| `inventory` | `idx_inv_warehouse_sk` | 58,725,000 | 11,745,000 | **5.0x** |
| `store_sales` | `idx_ss_addr_sk` | 15,221,436 | 2,880,404 | **5.3x** |
| `item` | `idx_item_2` | 89,957 | 18,000 | 5.0x |
| `item` | `idx_item_1` | 54,973 | 18,000 | 3.1x |
| `store_sales` | `idx_ss_hdemo_sk` | 8,505,124 | 2,880,404 | 3.0x |
| `store_sales` | `idx_ss_sold_date_sk` | 8,250,933 | 2,880,404 | 2.9x |
| `web_returns` | `idx_wr_item_sk` | 143,510 | 71,763 | 2.0x |
| `catalog_returns` | `idx_cr_item_sk` | 287,355 | 144,067 | 2.0x |

`idx_inv_warehouse_sk` pulled **58.7 million rows out of an 11.7 million row
table** — five complete passes, every one of them as random index lookups
rather than a sequential scan.

**This is the regression mechanism, measured rather than inferred.** The
optimizer places these indexes on the inner side of a nested loop and re-reads
the table several times over. A single sequential scan would have touched each
row once.

The two worst offenders are exactly the indexes already implicated by `EXPLAIN`
in [`queries/tiers/06_regressed_by_indexes.sql`](../queries/tiers/06_regressed_by_indexes.sql):
`idx_ss_addr_sk` appears in 5 of the 19 regressed queries, and `inventory`
accounts for 3 more.

## Finding 3 — the primary keys carry the real work

| Table | Index | Rows read |
|---|---|---:|
| `date_dim` | PRIMARY | 220,548,101 |
| `store_sales` | PRIMARY | 66,068,330 |
| `item` | PRIMARY | 63,159,526 |
| `customer` | PRIMARY | 48,718,760 |
| `catalog_sales` | PRIMARY | 18,432,125 |

`date_dim` is read **220 million times** from a 73,049-row table — it is
referenced by 23 foreign keys (see
[`14-schema-relationships.md`](14-schema-relationships.md)) and almost every
query joins and filters on it. It is small enough to stay resident in even a
128 MB buffer pool, which is why this costs less than it looks.

## What the slow query log adds

106 queries were logged at `long_query_time = 0.5` with
`log_slow_verbosity = query_plan,explain,innodb`. Each entry carries the
InnoDB page-level detail that makes the amplification concrete:

```
# Query_time: 1.758839  Lock_time: 0.009789  Rows_sent: 100  Rows_examined: 1469738
# Pages_accessed: 1744439  Pages_read: 9023  Pages_prefetched: 0
# Pages_read_time: 977.3237  Engine_time: 1606.1553
```

**1,744,439 pages accessed to return 100 rows, with zero prefetched.** Zero
prefetch is the signature of random index access — InnoDB's read-ahead cannot
engage, so every page miss is a separate I/O. Compare a scan-based plan in the
same log:

```
# Pages_accessed: 3818  Pages_read: 172  Pages_prefetched: 2598
# Full_scan: Yes
```

2,598 of 3,818 pages prefetched. That is the difference the optimizer is
failing to price.

## Recommended next steps, in order

1. **Drop the 83 unused indexes.** No query touched them; there is no risk to
   query time and it recovers storage and write throughput immediately.

2. **Raise `innodb_buffer_pool_size`.** It is 128 MB against a 3.2 GB database —
   under 4%. The amplification above is only expensive because those random
   reads miss cache. This may remove several regressions without dropping a
   single index, and costs nothing to test.

3. **Then reconsider `idx_ss_addr_sk` and the `inventory` indexes**, which show
   both the highest amplification and the most regressions. Re-measure after
   step 2 — some may stop being a problem once the pool is realistic.

## Reproducing

```sql
FLUSH INDEX_STATISTICS; FLUSH TABLE_STATISTICS;
-- run the query set, then:
SELECT TABLE_NAME, INDEX_NAME, ROWS_READ
FROM information_schema.INDEX_STATISTICS
WHERE TABLE_SCHEMA='tpcds' ORDER BY ROWS_READ DESC;

-- indexes never read:
SELECT s.TABLE_NAME, s.INDEX_NAME
FROM (SELECT DISTINCT TABLE_NAME,INDEX_NAME FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA='tpcds' AND INDEX_NAME<>'PRIMARY') s
LEFT JOIN information_schema.INDEX_STATISTICS i
  ON i.TABLE_SCHEMA='tpcds' AND i.TABLE_NAME=s.TABLE_NAME AND i.INDEX_NAME=s.INDEX_NAME
WHERE i.INDEX_NAME IS NULL;
```
