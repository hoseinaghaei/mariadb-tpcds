# q35 — three existence checks made index-only

**1.7s → 1.3s at SF=4, 1.31x, output byte-identical (101 rows).**

| pass | original | v1 |
|---|---:|---:|
| 1 | 7.3s | 3.1s |
| 2 | 1.8s | 1.3s |
| 3 | 1.7s | 1.5s |

Modest warm, but the rewrite wins on all three passes, and by 2.4x on the
cold one.

## What it does

Each of q35's three `EXISTS` subqueries joins `date_dim` purely to apply
`d_year = 1999 and d_qoy < 4`. Those 274 days are the contiguous key range
`d_date_sk 2451180..2451453` (274 rows, span 274), and `date_dim` is dense
over 2415022..2488070, so the join becomes a `BETWEEN` on each fact table's
own foreign key. Nothing in the subqueries reads a `date_dim` column — they
are `exists (select *)`, so the projection is discarded — and `BETWEEN`
excludes the NULL foreign keys the inner join excluded.

## Why this substitution paid when the others did not

Removing `date_dim` is not the point. The point is what it leaves behind.

With the dimension gone, each subquery names exactly two columns, and each
one has an index holding both, in that order:

| subquery | index |
|---|---|
| `store_sales` | `idx_ss_cust_date (ss_customer_sk, ss_sold_date_sk)` |
| `catalog_sales` | `idx_cs_cust_date (cs_ship_customer_sk, cs_sold_date_sk)` |
| `web_sales` | `idx_ws_cust_date (ws_bill_customer_sk, ws_sold_date_sk)` |

So all three existence checks become index-only probes — seek to the
customer, test whether any entry falls in the range, stop at the first hit.
No base-table row is touched. Before, the date predicate lived on a column
the index does not carry, so every matching index entry had to be resolved to
its row before it could be tested.

That is the distinction that separates the four rewrites in this batch that
paid from the five that did not: q35 and q82 use the key range to **unlock an
index-only path**, q23 and q70 use it alongside the removal of real work.
q38, q66, q77, q87 and q58 apply the same substitution with nothing behind
it, and three of the five got slower.

The outer query is untouched — same three dimension joins, same grouping,
same ordering, same limit.
