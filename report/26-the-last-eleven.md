# The last eleven: optimizing what nobody had touched

Eleven of the forty tier-4/5 queries were still running the adapted TPC-DS
text, with no optimized version from anyone. This is what happened when all
eleven were rewritten and measured.

**Four were adopted. Seven were not.** Every one of the eleven rewrites
produces the same answer as the original; the seven were rejected on speed,
not correctness, and they are kept with their measurements because the
negative results turned out to be the more useful half.

## Results

All at SF=4 on the standing configuration (`sql/tpcds-tuned.cnf`), three
interleaved passes per query, best-of-3, output diffed against the original.
Every comparison came back byte-for-byte identical except q71, which matched
on rows but not on order — see the correctness note at the end, which is
about the query, not the rewrite.

| query | original | rewrite | ratio | adopted | what the rewrite did |
|---|---:|---:|---:|:---:|---|
| q82 | 0.8s | 0.1s | **8.00x** | yes | joins that only test existence → `EXISTS` |
| q23 | 160.7s | 44.7s | **3.60x** | yes | strip three CTEs to single-table aggregates |
| q70 | 11.6s | 3.6s | **3.22x** | yes | delete a subquery that filters nothing |
| q35 | 1.7s | 1.3s | **1.31x** | yes | make three `EXISTS` checks index-only |
| q66 v2 | 7.2s | 7.1s | 1.01x | no | aggregate on the warehouse key |
| q58 | 0.6s | 0.6s | 1.00x | no | resolve the week at authoring time |
| q65 | 3.2s | 3.3s | 0.97x | no | share a duplicated derived table |
| q66 v1 | 6.0s | 6.6s | 0.91x | no | key aggregation **+ redundant range** |
| q38 | 6.9s | 8.6s | 0.80x | no | intersect on the date key |
| q87 | 6.8s | 8.5s | 0.80x | no | except on the date key |
| q71 | 4.6s | 6.0s | 0.77x | no | three `date_dim` joins → ranges |
| q77 | 3.3s | 4.5s | 0.73x | no | six `date_dim` joins → ranges |

## What it did to the suite

Before this pass, the eleven unoptimized queries were **241.7s of the 620.9s**
tier-4/5 total at SF=4 — 39% of the runtime sitting on untouched TPC-DS text,
and q23 alone was 28% of it. Afterwards, the seven still on the original are
**38.6s of 475.4s, 8%**, and 33 of the 40 run an optimized query.

Treat the totals with care. The suite was run twice back to back on identical
files and settings and measured **408.7s and 475.4s** — a 16% spread with
nothing changed. The honest statement is the per-query one: q23 3.60x, q70
3.22x, q82 8.00x, q35 1.31x, each from interleaved A/B passes, best-of-3.

All 40 answers were checked against the previous suite run by `md5_sorted`:
**40/40 identical.**

## The one technique, and why it only worked half the time

Every one of the eleven rewrites rests on the same observation. The TPC-DS
dimensions are **dense**: `date_dim` holds 73,049 rows over `d_date_sk`
2,415,022..2,488,070 with no gaps, `item` is 1..46,000, `customer` is
1..233,000, and each was checked here by confirming that
`max(key) - min(key) + 1` equals the row count. So any contiguous set of days
is a contiguous key range, and a `date_dim` join that exists only to apply a
date filter can be replaced by a `BETWEEN` on the fact table's own foreign
key:

| filter | key range | rows / span |
|---|---|---:|
| `d_year in (1999..2002)` | 2451180..2452640 | 1461 / 1461 |
| `d_year = 1999 and d_moy = 7` | 2451361..2451391 | 31 / 31 |
| `d_month_seq between 1176 and 1176+11` | 2450815..2451179 | 365 / 365 |
| `d_date between '1998-08-28' and +30d` | 2451054..2451084 | 31 / 31 |
| `d_year = 1999 and d_qoy < 4` | 2451180..2451453 | 274 / 274 |
| `d_moy = 11 and d_year = 2001` | 2452215..2452244 | 30 / 30 |
| week of `'1998-03-14'` | 2450883..2450889 | 7 / 7 |
| `d_date between '2000-01-15' and +60d` | 2451559..2451619 | 61 / 61 |

These bounds are not scale-factor-specific: `date_dim` is a fixed TPC-DS
dimension with the same 73,049 rows at SF=1 and SF=4.

The substitution is always *correct*. It is almost never *sufficient*.

**It paid when it unlocked something else.** On q35 it left each `EXISTS`
naming exactly two columns, both carried by an existing index in the right
order (`idx_ss_cust_date`, `idx_cs_cust_date`, `idx_ws_cust_date`), so the
existence checks became index-only probes. On q82 it did the same for
`idx_inv_item_date_sk`. On q23 and q70 it rode alongside changes that deleted
real work.

**It cost when it stood alone.** On q38, q66, q71, q77 and q87 the rewrite
removed a per-row dimension probe that was never the bottleneck, while
handing the optimizer a different access path — and on four of the five it
chose worse. q38 and q87 have the same shape and regressed by the same 0.80x,
which rules out noise.

q66 was split into two versions to find out which half hurt. v1 (key
aggregation plus a redundant range predicate) measured 0.91x; v2 (key
aggregation alone) measured 1.01x. The redundant predicate was the whole
difference. **It reads like a free hint — every row it admits the join
already admitted — and it is not free.**

## The three wins worth reading

### q23: a CTE rebuilt 55,882 times

The most expensive query in the suite, and two earlier attempts had found
nothing in it. Timing cannot resolve it on this host — four identical runs of
the original spanned 160.7–213.0s — so it was analysed with
`ANALYZE FORMAT=JSON`, whose loop counts are deterministic.

`frequent_ss_items` was being split-materialised **55,882 times** in one
branch and 28,222 in the other, across two statements: **99.1s of the 208.1s**
the query spends under ANALYZE.

The obvious response — `split_materialized=off` — had already been measured
at **+54.0s, slower**, and that result was correct. Materialising the CTE once
meant grouping four years of `store_sales` by
`(substr(i_item_desc,1,30), i_item_sk, d_date)`, a 30-character varchar in the
key. Recomputing something cheap 55,882 times beat building something
expensive once.

The fix was to stop choosing between those two plans and make the CTE cheap
instead. Dropping the `item` join (its only contribution,
`substr(i_item_desc,1,30)`, is functionally dependent on `i_item_sk`, which is
unique), swapping `d_date` for `d_date_sk`, and reordering the GROUP BY to
`(ss_sold_date_sk, ss_item_sk)` so it matches
`idx_ss_date_item_store_cover` turned a 28.7s CTE into a 3.0s one.

The CTE returns **1,423 rows**.

### q70: a top-5 filter that is not one

```sql
and s_state in
    ( select s_state from (
        select s_state,
               rank() over (partition by s_state
                            order by sum(ss_net_profit) desc) as ranking
        from store_sales, store, date_dim
        where <the same join and month filter as the outer query>
        group by s_state) tmp1
      where ranking <= 5 )
```

It groups by `s_state` and then partitions by `s_state`. Grouping has already
reduced the input to one row per state, so every partition holds exactly one
row, `rank()` is 1 everywhere, and `ranking <= 5` admits all of them. The
subquery reduces to the set of states the outer query is already confined to.

**The filter removes nothing, and establishing that costs a second full pass
over a 12-month window of `store_sales`.** This is a property of the published
TPC-DS text, so reproducing the benchmark's answer means preserving the
behaviour — which deleting the subquery does exactly.

### q82: a GROUP BY with nothing to aggregate

q82 joins `item` to `inventory`, `date_dim` and `store_sales`, then groups by
three item columns **with no aggregate in the select list**. That is a
DISTINCT: the join multiplicity is built at full cost and thrown away. An item
matching 400 inventory rows and 9,000 sales rows contributes 3.6M intermediate
rows and one output row.

Rewriting both joins as `EXISTS` is exact, not approximate, and it stops at
the first match. With the date filter also reduced to a key range, both
subqueries become index-only. 8.00x, on consistent passes (1.0/0.8/0.8 against
0.2/0.1/0.1).

## A wrong answer found on the way past

Not one of the eleven, but found by this pass and worth recording.

q97's optimized version had been rebuilt on CTEs because the original
contribution used temporary tables, which this project does not accept. The
replacement keeps the good idea — the query emulates a FULL OUTER JOIN as
`(LEFT JOIN) UNION ALL (RIGHT JOIN ... WHERE a IS NULL)`, reading both sides
twice, and one LEFT JOIN suffices if the catalog-only count is derived as

```
catalog_only = (rows in csci) - (rows of csci that matched)
```

That derivation is exact *except* for NULLs, and the first version did not
handle them. `ss_customer_sk` and `cs_bill_customer_sk` are nullable, so both
CTEs contain rows grouped under a NULL customer — **2,569 of them in `csci`
at SF=4**. The original scores those as zero in all three output columns: its
case expressions all test `is not null`, and an equality join never matches a
NULL, so such a row falls through every branch. A bare `count(*)` added all
2,569 to `catalog_only`, giving **1,141,754 where the answer is 1,139,185**.

Two things about how it was caught are worth keeping:

- **Nothing in the query's behaviour looked wrong.** It ran, returned one
  row of three plausible counts, and was 1.9x faster than the original. The
  only symptom was a changed hash.
- **It was caught by comparing `md5_sorted` against the previous suite run**,
  a check added to `report/gen-25.py` for a different reason — to stop the
  report publishing a faster number for a query whose answer had moved. It
  found a defect that had already been committed.

Fixed by adding `where customer_sk is not null` to that count. q97 now
returns byte-identical output and is **1.92x** faster than the original
(7.3s → 3.8s), so it also leaves the report's list of optimizations that
make things worse.

A single-row result is the worst case for eyeball verification, and q23 is
the same hazard in a different form — it returns a NULL and no rows at SF=4,
which is why its three CTEs were checked individually rather than trusting
the final answer.

## A correctness note that is not about these rewrites

Comparing q71 reported "same rows, different order", which turned out to be a
property of the query itself. `order by ext_price desc, i_brand_id` is not a
total order: 3,948 result rows collapse to 3,934 distinct sort keys, leaving
**24 rows free to permute between runs**. The select list carries `t_hour` and
`t_minute`, which the ORDER BY never mentions.

So a byte-for-byte diff of q71 can report a difference between two runs that
are both correct. The suite already hashes results twice (`md5` and
`md5_sorted`) and `verify-tuned.sh` classifies row-order-only differences
separately — q71 is the live example of why.

## What could not be tried

q77's plan reaches `store_sales` through
`idx_ss_date_cust (ss_sold_date_sk, ss_customer_sk)`, which carries neither
`ss_store_sk` nor the two profit columns it needs, so every qualifying row
costs a base-table fetch. A covering index on
`(ss_sold_date_sk, ss_store_sk, ss_net_profit, ss_ext_sales_price)` would
make that CTE index-only. q70's aggregate reads the same columns and would
benefit too — it is already 3.22x faster without it, but its remaining cost
is base-table fetches for `ss_net_profit`.

It was not tried: this analysis ran under a read-only policy that permits no
DDL. It is also not obviously safe — the last time six indexes were added to
this schema, 16K/SF=1 got **40% slower** — so it would need the same
before/after discipline applied to the whole suite rather than to one query.

Recorded as the open lead.
