# q68 and q46 at SF=4 — drive the join from `date_dim`

Two queries nobody had optimized, with the same structural defect, fixed the
same way.

| query | original | rewritten | |
|---|---|---|---:|
| **q68** | 12, 11, 11s | **2, 3, 2s** | **4.9x** |
| **q46** | 13, 12, 12s | **7, 6, 6s** | **1.9x** |

Three interleaved passes each, `rc=0` and output byte-identical every pass.

## The defect

`ANALYZE FORMAT=JSON` at SF=4, on both queries:

```
FULL SCAN store_sales   11,519,024 rows
FULL SCAN customer         233,000 rows
customer_address probed    233,000 times
```

Both join the same five tables — `store_sales`, `date_dim`, `store`,
`household_demographics`, `customer_address` — and both read the entire fact
table, then throw nearly all of it away.

## The fix

`STRAIGHT_JOIN` from `date_dim`, so the dates are resolved first and
`store_sales` is reached through `idx_ss_sold_date_sk` rather than scanned.
`date_dim` is ~73k rows; scanning it to find the matching days costs nothing
beside 11.5M fact rows.

Nothing else changes — same tables, same predicates, same grouping, only the
order they are visited in. That is why the output is identical.

## Why q68 gains 4.9x and q46 only 1.9x

Selectivity, and it was predicted before measuring:

| | predicate | dates selected |
|---|---|---:|
| q68 | `d_dom between 1 and 2`, three years | ~18 of 1,095 — **1.6%** |
| q46 | `d_dow in (6,0)` — weekends, three years | ~312 of 1,095 — **28%** |

q68 needs almost none of the fact table, so not scanning it is worth a great
deal. q46 needs over a quarter of it, so the same change has far less to
save. Same defect, same fix, different headroom.

This is worth keeping in mind before copying the pattern to a third query:
the gain comes from the predicate being selective, not from `STRAIGHT_JOIN`
itself.

## How these were found

By scanning all 12 unoptimized tier-4/5 queries with `ANALYZE FORMAT=JSON`
first (`queries/optimized/unoptimized-scan/analyze-all.sh`) and looking for
structural defects — loop counts and full scans — rather than timing them.

Of the twelve, **only q68 and q46 had anything actionable**. Seven showed
nothing structural and are simply doing the work they describe; rewriting
them would be inventing problems. q77 has 240,716 repeated `store` lookups
and may be worth a look.

That ordering matters on this host. Loop counts and row counts from `ANALYZE`
are deterministic, so a defect is a defect regardless of clock noise — while
q23 showed that timing here cannot resolve anything under about 30% on a long
query. Five minutes of scanning replaced what would otherwise have been hours
of inconclusive measurement.

## Files

| file | |
|---|---|
| `query68_v1_datefirst.sql` | the q68 rewrite |
| `../q46-sf4/query46_v1_datefirst.sql` | the q46 rewrite |
| `../unoptimized-scan/analyze-all.sh` | the structural scan over all twelve |
