# q66 — rewritten, measured, and not adopted

The rewrite in `query66_v1_keyagg.sql` is correct and produces byte-identical
output. It is also, warm, **slower than the original**, so it is kept here as
a recorded negative result rather than promoted into `queries/tuned/`.

## What it does

Two changes, both sound:

1. The inner `GROUP BY` was on six warehouse strings plus `d_year`, every one
   of them functionally determined by `w_warehouse_sk` (and `d_year` pinned
   to 1998 by the WHERE clause). The rewrite groups on the integer key and
   joins `warehouse` afterwards, in the outer query.
2. `d_year = 1998` is the contiguous key range `d_date_sk 2450815..2451179`
   (365 rows, span 365), added as a redundant `BETWEEN` on the fact tables'
   own foreign keys so the range optimizer can drive them by index. The
   `date_dim` join has to stay regardless, because all 24 `case` expressions
   read `d_moy`.

## What it measured

Three interleaved passes at SF=4:

| pass | original | v1 |
|---|---:|---:|
| 1 | 15.4s | 7.1s |
| 2 | 6.0s | 6.6s |
| 3 | 6.0s | 7.6s |

Pass 1 is a cold buffer pool — the first touch of this window of `web_sales`
and `catalog_sales` — and it is the only pass that favours the rewrite. Warm,
the original is 6.0s twice over and the rewrite is 6.6s and 7.6s:
**0.91x, a 10–25% regression.**

## Why the reasoning did not translate

The argument for narrowing the group key assumed the key width drives the
cost. It does not here. The inner aggregation produces roughly one group per
warehouse — about 22 of them — and at that cardinality the grouping structure
is tiny and resident whatever the key is made of. Replacing a six-string key
with an integer saves comparisons that were never expensive, while the extra
derived table and the deferred `warehouse` join add work that was not there
before.

## Which half was responsible

`query66_v2_keyagg_norange.sql` is v1 with the redundant date range removed
and the key aggregation kept, to settle it:

| pass | original | v2 |
|---|---:|---:|
| 1 | 12.3s | 7.1s |
| 2 | 7.2s | 9.6s |
| 3 | 16.5s | 7.2s |

**1.01x** — a dead heat.

So the two halves separate cleanly: the key aggregation on its own is
*neutral* (1.01x), and adding the redundant range predicate is what turns it
into a *regression* (0.91x). The range gives the optimizer a second viable
access path on each fact table, and here it picks the worse one.

That is worth remembering, because the predicate is genuinely redundant —
every row it admits the join already admitted — so it reads like a free hint.
It is not free. The same addition cost q38, q77 and q87 between 20% and 27%.

The lesson generalises to the rest of this batch: **shrinking a GROUP BY key
pays in proportion to the number of groups, not the number of rows.** It was
worth 9.6x on q23, where `frequent_ss_items` groups ~9M rows into up to
millions of groups on a 30-character varchar. It is worth nothing on 22
warehouses.

Reported figures elsewhere (10.6s for q66 in `report/25-query-by-query.md`)
come from a full-suite run with different cache state; the ratio above is the
comparable number, both sides measured back to back.
