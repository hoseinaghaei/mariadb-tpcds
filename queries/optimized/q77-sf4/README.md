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
would make the `ss` CTE index-only. Adding it was not possible here: the
analysis session is restricted to read-only statements, so no DDL could be
issued. It is also not obviously safe — the last time six indexes were added
to this schema, 16K/SF=1 got **40% slower** — so it would need the same
before/after discipline applied to the whole suite, not just to q77.

Recorded as the open lead for this query.
