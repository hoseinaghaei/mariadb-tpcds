# q87 — rewritten, measured, not adopted

`query87_v1_keydate.sql` is correct and produces byte-identical output. It is
slower, so it stays here as a recorded negative result.

| pass | original | v1 |
|---|---:|---:|
| 1 | 7.2s | 8.5s |
| 2 | 6.8s | 8.6s |
| 3 | 7.2s | 8.6s |

**0.80x**, and unlike q77 this one is consistent — the rewrite loses on every
pass by roughly the same margin.

## What it does

Identical in shape to q38, with `EXCEPT` where q38 has `INTERSECT`. The query
returns a single `count(*)`; `d_date` never reaches the output and serves only
to decide whether a row in one channel matches a row in another. `d_date` and
`d_date_sk` are a bijection on `date_dim` (73,049 rows, 73,049 distinct
dates), so substituting the key for the date in **all three** branches
preserves every match and the set difference has the same cardinality.

`EXCEPT` is order-sensitive in a way `INTERSECT` is not — `(A except B)
except C` — but the substitution is uniform across the branches and the order
is untouched, so the chain evaluates over the same elements.

With `d_date` gone, `date_dim` exists only for `d_month_seq between 1176 and
1176+11`, the contiguous key range `2450815..2451179` (365 rows, span 365),
so each join becomes a `BETWEEN` on the fact table's own foreign key.

The customer joins stay: names are not unique, and the original takes the
difference over names.

## Why it does not pay

Same as q38, and the agreement between them is the useful part: two queries
of the same shape, rewritten the same way, regressed by the same 0.80x. That
is not noise.

The work removed — three per-row probes into `date_dim` — is not where either
query spends its time. The cost is building and differencing three large
`DISTINCT` sets keyed on two name columns, which the rewrite does not touch.
What it does change is the access path: the original resolves 365 `date_dim`
rows and probes each fact table through its date-leading index, and offering
a range scan instead leads the optimizer to a worse plan.

See `../q38-sf4/README.md` for the fuller version of this argument and
`../q82-sf4/README.md` for the contrast with the rewrites that did pay.
