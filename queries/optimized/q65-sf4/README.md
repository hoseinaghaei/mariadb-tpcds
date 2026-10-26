# q65 — the duplicated subquery was already being shared

> **Superseded.** A classmate's `queries/optimized/q65/query65_BEST.sql` was
> measured head to head against this one at SF=4 — three interleaved passes,
> identical output — and won every pass: **2.6, 2.7, 2.8s against 1.6, 1.7,
> 1.8s, 1.62x**. It is what `queries/tuned/query65.sql` now uses.
>
> That is the right outcome. The rewrite below measured **0.97x** — no change
> — because its premise was wrong: MariaDB already materialises the duplicated
> derived table once, so naming it as a CTE told the optimizer nothing it had
> not worked out. Their version attacks the aggregation itself instead.
>
> Kept for the negative result, which still stands.

`query65_v1_sharedcte.sql` is correct and produces byte-identical output (101
rows). It makes no measurable difference, so the original stays.

| pass | original | v1 |
|---|---:|---:|
| 1 | 5.7s | 5.2s |
| 2 | 3.2s | 3.3s |
| 3 | 5.2s | 5.4s |

**0.97x** — indistinguishable, and the two sides trade places pass to pass.

## What it does

q65 contains the same derived table twice, written out in full both times:

```sql
(select ss_store_sk, ss_item_sk, sum(ss_sales_price) as revenue
   from store_sales, date_dim
  where ss_sold_date_sk = d_date_sk and d_month_seq between 1176 and 1176+11
  group by ss_store_sk, ss_item_sk)
```

once as `sa` (wrapped by `sb`, which averages it per store) and once as `sc`.
The rewrite names it once as a CTE and refers to it twice, so `sb` becomes an
aggregate over `sc` rather than a second pass over the fact table. The
`date_dim` join also becomes a range on `ss_sold_date_sk`
(`2450815..2451179`, 365 rows, span 365).

## Why it changes nothing

The premise — that a 12-month window of `store_sales` is scanned and grouped
twice — turns out not to hold. MariaDB already recognises the two spellings
as the same derived table and materialises it once, so naming it explicitly
tells the optimizer something it had worked out for itself.

That also explains why the earlier structural scan saw `<derived3>` scanned
`ALL` at 1,048,697 rows with `temporary + filesort`: that is the single
shared materialisation being read, not a second computation of it.

The remaining cost is the materialisation itself plus the `filesort` behind
`order by s_store_name, i_item_desc`, and the rewrite touches neither.

Filed with q66, q38, q77 and q58 as a rewrite that was sound and did not pay.
