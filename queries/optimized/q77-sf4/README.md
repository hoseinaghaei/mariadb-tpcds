# q77 — rewritten, measured, not adopted

`query77_v1_keydate.sql` is correct and produces byte-identical output (87
rows). It shows no gain, so it stays here as a recorded result.

| pass | original | v1 |
|---|---:|---:|
| 1 | 11.9s | 4.5s |
| 2 | 3.3s | 5.9s |
| 3 | 5.3s | 10.7s |

Best-of-3 says **0.73x**. The means say 6.8s against 7.0s — a wash. Both
readings are weak: the original spans 3.3–11.9s and the rewrite 4.5–10.7s
across three passes, so this query is not resolvable to better than a factor
of three on this host. What can be said is that there is **no evidence of
improvement**, which is enough to leave the original in place.

## What it does

All six of q77's CTEs join `date_dim` purely to apply the same 31-day window
(`d_date between '1998-08-28' and +30 days`). Those days are the contiguous
key range `d_date_sk 2451054..2451084` (31 rows, span 31), and `date_dim` is
dense over 2415022..2488070, so each join becomes a `BETWEEN` on the CTE's own
foreign key. No `date_dim` column is read anywhere else in the query.

The `store` and `web_page` joins stay: they supply the grouping key that
becomes `id` in the output, and their surrogate keys were not checked for
density, so dropping them could admit fact rows the original rejected.

## Why there was less here than it looked

The structural scan flagged q77 because its plan reaches `store_sales`
through `idx_ss_date_cust (ss_sold_date_sk, ss_customer_sk)` with
`Using join buffer (flat, BKAH join); Rowid-ordered scan`. That index does
not carry `ss_store_sk`, `ss_ext_sales_price` or `ss_net_profit`, so every
qualifying row costs a base-table fetch — and **that** is the cost, not the
`date_dim` joins the rewrite removes.

The fix the plan actually wants is a covering index on
`(ss_sold_date_sk, ss_store_sk, ss_net_profit, ss_ext_sales_price)`, which
would make the `ss` CTE index-only.

## That index was built and measured, and it does not help q77

`sql/15_q77_covering_index.sql` creates it; `pagesize/test-q77-index.sh`
measured four full tier-4/5 passes at SF=4, alternating `IGNORED` and
`NOT IGNORED`. It occupies **512 MB**.

q77, per pass:

| | IGNORED | NOT IGNORED |
|---|---:|---:|
| pass 1 | 11.0s | 15.3s |
| pass 2 | 7.3s | 5.7s |

Overlapping — no signal. Meanwhile two queries the index was *not* built for
improved consistently, both passes beating both passes:

| | IGNORED | NOT IGNORED | |
|---|---|---|---:|
| q70 | 3.5, 4.2s | 1.4, 1.3s | **~2.9x** |
| q5 | 10.1, 13.1s | 5.8, 3.9s | **~2.4x** |

**Why q77 misses out.** Its `ss` CTE does read exactly those four columns, so
the index covers it. But `ss` is one of *six* CTEs — the others aggregate
`store_returns`, `catalog_sales`, `catalog_returns`, `web_sales` and
`web_returns`, none of which this index touches. Making a sixth of the query
index-only disappears into the run-to-run spread.

q5 and q70 benefit because this access pattern is nearly all of what they do.
q5 reads `ss_store_sk`, `ss_sold_date_sk`, `ss_ext_sales_price` and
`ss_net_profit` from `store_sales` and nothing else — the index is a perfect
cover for its entire store-channel subquery. That it helps q5 was not
predicted here, and should have been.

So the diagnosis was right and the remedy was aimed at the wrong query. The
index is worth having for q5 and q70; q77 stays unfixed.
