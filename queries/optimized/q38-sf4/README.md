# q38 — rewritten, measured, not adopted

`query38_v1_keydate.sql` is correct and produces byte-identical output. It is
also slower, so it stays here as a recorded negative result.

| pass | original | v1 |
|---|---:|---:|
| 1 | 6.9s | 16.1s |
| 2 | 8.6s | 8.6s |
| 3 | 7.7s | 9.6s |

**0.80x on best-of-3.** Warm, the two are close (8.6 vs 8.6, 7.7 vs 9.6); the
rewrite is never clearly ahead and is badly behind on the cold pass.

## What it does

q38 intersects three sets of `(c_last_name, c_first_name, d_date)` and counts
them. `d_date` never reaches the output — the query returns a single
`count(*)` — and serves only to decide whether a row in one channel matches a
row in another. Since `d_date` and `d_date_sk` are a bijection on `date_dim`
(73,049 rows, 73,049 distinct dates), substituting the key for the date in
**all three** branches preserves every match and every non-match, so the
intersection has the same cardinality.

With `d_date` gone, `date_dim` exists only for `d_month_seq between 1176 and
1176+11`, which is the contiguous key range `2450815..2451179` (365 rows,
span 365). So the join collapses to a `BETWEEN` on each fact table's own
foreign key and the dimension leaves the query.

The customer joins stay: names are not unique, two customers can share one,
and the original intersects on names — collapsing to `c_customer_sk` would
change the answer.

## Why it does not pay

The reasoning is sound and the work removed is real — three per-row probes
into `date_dim` — but it is not where q38 spends its time. The cost is in
building and intersecting three large `DISTINCT` sets keyed on two names,
and that is untouched by the rewrite.

Against that, replacing a join with a range changes the access path. The
original resolves 365 `date_dim` rows and probes each fact table through its
date-leading index; the rewrite offers the optimizer a range scan instead,
and here it chooses worse. The same substitution regressed q66 (0.91x) and
paid off handsomely on q70 (3.22x) and q23 (3.6x) — the difference is that on
those two it came bundled with the removal of an entire table pass, and the
access-path change was swamped by it.

**The substitution is not a win on its own.** It is worth doing when it
unlocks something else — an index-only subquery (q35, q82) or the deletion of
a redundant scan (q70) — and worth measuring, not assuming, otherwise.

The same rewrite was applied to q87, which has the identical shape with
`EXCEPT` in place of `INTERSECT`; see `../q87-sf4/`.
