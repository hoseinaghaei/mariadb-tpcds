# q71 — rewritten, measured, not adopted (and a note on its ORDER BY)

`query71_v1_keydate.sql` is correct and returns the same 3,948 rows. It is
slower, so the original stays.

| pass | original | v1 |
|---|---:|---:|
| 1 | 23.6s | 9.5s |
| 2 | 5.1s | 9.4s |
| 3 | 4.6s | 6.0s |

**0.77x.** Pass 1 is a cold buffer pool and favours the rewrite by 2.5x;
warm, the original wins both remaining passes.

## What it does

Each of the three union branches joins `date_dim` only to apply
`d_moy = 11 and d_year = 2001`. Those 30 days are the contiguous key range
`d_date_sk 2452215..2452244` (30 rows, span 30), and `date_dim` is dense over
2415022..2488070, so each join becomes a `BETWEEN` on the branch's own
foreign key. Nothing downstream reads a `date_dim` column.

`sold_date_sk` stays in the projection even though nothing consumes it,
because dropping a column from a `UNION ALL` branch would change the shape of
`tmp`.

This is the same pure substitution that failed on q38, q66, q77 and q87, and
it fails here for the same reason: it removes a per-row dimension probe that
was not the cost, while handing the optimizer a different access path. The
real cost in q71 is the full scan of `item` to apply `i_manager_id = 1` —
there is no index on `i_manager_id` — and the three-way union feeding a
`filesort`. Neither is touched.

## q71's output order is not deterministic

The comparison reported **"same rows, different order"**, not a difference,
and that is a property of the query rather than of the rewrite.

`order by ext_price desc, i_brand_id` is not a total order here:

| | |
|---|---:|
| result rows | 3,948 |
| distinct `(ext_price, i_brand_id)` keys | 3,934 |
| rows sitting in a tie | 24 |

The select list also carries `t_hour` and `t_minute`, which the ORDER BY does
not mention, so two groups differing only in hour or minute can tie on the
full sort key and come back in either order. Up to 24 rows are free to
permute between runs.

This matters beyond q71: a byte-for-byte diff of its output can report a
spurious difference for two runs that are both correct. The suite already
guards against this by hashing results twice — `md5` and `md5_sorted` — and
`verify-tuned.sh` classifies a row-order-only difference separately from a
real one. q71 is a live example of why both exist.
