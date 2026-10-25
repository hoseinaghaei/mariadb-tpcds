# q23 — the most expensive query in the suite

173.6s at SF=4 on the standing configuration, more than three times the next
one (q67, 46.1s). Two earlier attempts found nothing; the third did.

## What the first two attempts got wrong

`query23_v1_joins.sql` and `query23_v2_unionfirst.sql` rewrote the *join
order* of the outer query. Neither moved the clock, and v1 was worse than
useless: it had an ambiguous `c_customer_sk`, so statement 2 failed to parse
with ERROR 1052 while the comparison still reported IDENTICAL — both sides
were empty, because q23 returns nothing at SF=4. That is the trap this query
sets, and it is why the check in `test-v3.sh` compares the CTEs rather than
the final answer.

They also chased the wrong thing. The outer join order is not where the time
is.

## Where the time actually is

Timing cannot resolve this query on this host: four identical runs of the
original measured 171.5–198s. `ANALYZE FORMAT=JSON` reports loop counts
instead, which are deterministic. For the original at SF=4:

| | statement 1 | statement 2 |
|---|---:|---:|
| total | 120,240ms | 87,873ms |
| `frequent_ss_items` (catalog branch) | ×55,882 → 35,937ms | ×55,882 → 30,162ms |
| `frequent_ss_items` (web branch) | ×28,222 → 17,183ms | ×28,222 → 15,785ms |
| `best_ss_customer` (catalog branch) | ×1,987 → 31,274ms | ×1,987 → 11,862ms |
| `best_ss_customer` (web branch) | ×1,034 → 14,547ms | ×1,034 → 10,372ms |

`frequent_ss_items` alone is **99.1s of the 208.1s** the query spends under
ANALYZE. It is being split-materialised — recomputed once per outer row —
which is the same mechanism that made q59 bistable.

But q23 is not q59. Turning split materialisation off had already been
measured at **+54.0s, slower**, and that result was correct: materialising
`frequent_ss_items` once meant grouping four years of `store_sales` by
`(substr(i_item_desc,1,30), i_item_sk, d_date)` — a 30-character varchar in
the key — which is worse than recomputing a cheap thing 55,882 times.

The fix is not to choose between those two plans. It is to make the CTE cheap
enough that it no longer matters.

## The rewrite

Four substitutions, each an equivalence that holds on the TPC-DS schema and
each checked against this database before use.

**1. `frequent_ss_items` drops the `item` join.** Its only purpose is
`substr(i_item_desc,1,30)` in the GROUP BY. `i_item_sk` is unique in `item`
(46,000 rows, 46,000 distinct), so that expression is functionally dependent
on a column already in the key — it splits no group. The join discards
nothing either: `ss_item_sk` is NOT NULL in all 11,519,024 rows and spans
exactly 1..46,000, matching `item`'s dense range. Downstream reads only
`item_sk`.

**2. `date_dim` joins become ranges on the surrogate key.** `date_dim` holds
73,049 rows over `d_date_sk` 2,415,022..2,488,070 with no gaps (span equals
count), so a contiguous set of days is a contiguous key range:

- `d_year in (1999..2002)` → `2451180..2452640` (1,461 days, span 1,461)
- `d_year = 1999 and d_moy = 7` → `2451361..2451391` (31 days, span 31)

`date_dim` is a fixed TPC-DS dimension — 73,049 rows at every scale factor —
so these bounds are not SF=4-specific. `BETWEEN` also excludes NULL, which is
what the inner join did to the 519,301 NULL `ss_sold_date_sk` rows.

This also fixes a second defect, the same one found in q68 and q46: the
original reached `catalog_sales` by `ALL` (5,759,989 rows) and probed
`date_dim` 5,716,991 times to keep ~55,882. A range on `cs_sold_date_sk`
drives the selective side first.

**3. Grouping is by `(ss_sold_date_sk, ss_item_sk)`.** Same groups — GROUP BY
is order-insensitive — but it now matches the leading columns of
`idx_ss_date_item_store_cover (ss_sold_date_sk, ss_item_sk, ss_store_sk,
ss_sales_price)`, so the CTE is answerable by an ordered, index-only scan
instead of a temp table keyed on a varchar.

**4. The `customer` joins become `ss_customer_sk is not null`.** `customer` is
dense 1..233,000 and every non-NULL `ss_customer_sk` falls inside it, so the
join removed exactly the 518,489 NULL rows and nothing else. The NULL test has
to stay: without it those rows collapse into one group whose sum could become
`max_store_sales` and change the answer.

## Verification

q23 returns one NULL row and then no rows at all at SF=4, so diffing the final
answer proves very little — that is exactly how the v1 bug survived. Each CTE
was therefore rebuilt standalone, old form against new:

| CTE | old | new | result |
|---|---:|---:|---|
| `frequent_ss_items` (count, distinct item_sk) | 28.7s | 3.0s | 1423 / 1396 both |
| `max_store_sales` (scalar) | 11.5s | 3.4s | 346703.87 both |
| `best_ss_customer` (count, sum, max) | 43.5s | 5.4s | 229225 / 20295460573.81 / 390388.20 both |

All three agree exactly, and each is 3.4–9.6x cheaper.

Then the whole query, three interleaved passes at SF=4:

| pass | original | v3 |
|---|---:|---:|
| 1 | 176.5s | 45.2s |
| 2 | 160.7s | 44.7s |
| 3 | 204.4s | 58.6s |

**160.7s → 44.7s best-of-3, 3.6x**, and the output is byte-identical.

The spread on the original (160.7–204.4s, a 27% range) is the reason this
query was analysed structurally rather than timed. The rewrite's own spread
is narrower in absolute terms but similar in proportion, so treat 3.6x as the
conservative figure and ~4x as the mean-to-mean one.

Worth noting how small `frequent_ss_items` is: **1,423 rows**. The original
plan rebuilt that 55,882 times per branch.
