# query 88 — 33s → 0.25s (~130x)

Original: `queries/mariadb/query88.sql`.
Output is **byte-identical** to it (1 row, 8 columns, headers included).

## What the query must do

TPC-DS Appendix B.88:

> How many items do we sell between pacific times of a day in certain stores to
> customers with one dependent count and 2 or less vehicles registered or 2
> dependents with 4 or fewer vehicles registered or 3 dependents and five or
> less vehicles registered. **In one row** break the counts into sells from
> 8:30 to 9, 9 to 9:30, 9:30 to 10 ... 12 to 12:30

One row, eight half-hour buckets.

## The shape of the problem

The query is **eight subqueries cross-joined**, each returning a single count:

```sql
select * from
 (select count(*) h8_30_to_9   from store_sales, household_demographics, time_dim, store
   where ... and t_hour =  8 and t_minute >= 30 and <demographics> and s_store_name='ese') s1,
 (select count(*) h9_to_9_30   from store_sales, household_demographics, time_dim, store
   where ... and t_hour =  9 and t_minute <  30 and <demographics> and s_store_name='ese') s2,
 ... six more ...
```

Verified identical across all eight: the tables, the join conditions, the
demographic predicate (`hd_dep_count` 0/1/4 with `hd_vehicle_count <= n+2`),
and `s_store_name = 'ese'`. **The only difference is the half-hour window.**

So it makes eight passes over `store_sales` to compute eight numbers that one
pass can produce.

## Two independent fixes

### 1. Conditional aggregation — 8 passes become 1

```sql
select
    sum(case when t_hour =  8 and t_minute >= 30 then 1 else 0 end) h8_30_to_9
  , sum(case when t_hour =  9 and t_minute <  30 then 1 else 0 end) h9_to_9_30
  , ... six more ...
from store_sales, household_demographics, time_dim, store
where <the common joins, demographics and store filter>
  and t_hour between 8 and 12;
```

`t_hour between 8 and 12` is a **safe superset** of the eight windows — rows at
8:00–8:30 or 12:30–13:00 fall through every `CASE` and contribute 0.

**36.0s → 4.2s**, close to the 8x the structure predicts.

### 2. A covering index — the table is never touched

The query reads exactly three columns from `store_sales`:
`ss_store_sk`, `ss_hdemo_sk`, `ss_sold_time_sk`. All three are join keys; no
measure column is used, because the aggregate is `count(*)`.

```sql
CREATE INDEX idx_ss_store_hdemo_time
    ON store_sales (ss_store_sk, ss_hdemo_sk, ss_sold_time_sk);
```

The plan changes from `store_sales ALL rows=3,910,824` to driving from `store`
(12 rows) into `ref idx_ss_store_hdemo_time rows=2,235 **Using index**`. The
base table is never read.

## Results

| Configuration | Time |
|---|---:|
| original, no index | 29.8–36.0s |
| original **+ covering index** | 1.4s |
| **single-pass rewrite**, no index | 4.2s |
| **both** (`query88_BEST.sql`) | **0.2–0.3s** |

Three-pass on the index: visible 0.3s / 0.2s / 0.2s, IGNORED 4.2s, visible
again 0.3s.

**Both levers are strong alone and they compose** — 8x from the rewrite, 25x
from the index, ~130x together. That is the opposite of query 22, where no
single ingredient helped and only the combination did.

## Why the filters are individually weak

| Filter | Selectivity |
|---|---|
| `s_store_name = 'ese'` | 3 of 12 stores |
| demographic predicate | 1,800 of 7,200 |
| `t_hour between 8 and 12` | 18,000 of 86,400 |

Each keeps ~21–25%; together ~1.3%. No single-column index helps much, which
is why the three-column covering index does so well — it makes the *conjunction*
cheap.

Full writeup: [`report/18-query-optimization.md`](../../../report/18-query-optimization.md)
