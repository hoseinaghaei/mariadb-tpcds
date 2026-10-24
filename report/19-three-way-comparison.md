# Three-way comparison: Claude / riccio / Aysha

One serial pass on this machine. Every query sees the same **188 indexes** —
the repo's 117 plus all 41 that the three of us prescribe — and each query's
before and after ran back to back, so the pair is internally comparable.

| column | meaning |
|---|---|
| **A** | original query, repo's 117-index baseline (earlier serial run) |
| **B** | original query, all 41 contributed indexes present |
| **C** | optimized query, all 41 contributed indexes present |

`A→C` is the whole gain, index and rewrite together. `B→C` is what the SQL
rewrite alone is worth once everyone's indexes are available to the original
too — that is the fairer measure of the query work, and it is often much
smaller.


## Claude — 6 counted

| query | A base | B before | C after | A→C | B→C | output |
|---|---:|---:|---:|---:|---:|---|
| q72 | 300.1s | 90.6s | 84.9s | 3.5x | 1.1x | identical |
| q2 | 85.2s | 88.4s | 26.9s | 3.2x | 3.3x | identical |
| q78 | 73.4s | 28.4s | 16.9s | 4.3x | 1.7x | identical |
| q59 | 12.6s | 19.8s | 20.2s | 0.6x | 1.0x | identical rows, label differs |
| q22 | 19.8s | 12.3s | 6.8s | 2.9x | 1.8x | identical |
| q88 | 29.0s | 1.6s | 0.2s | 145.0x | 8.0x | identical |
| **total** | **520.1s** | **241.1s** | **155.9s** | **3.34x** | **1.55x** |

## riccio — 5 counted

| query | A base | B before | C after | A→C | B→C | output |
|---|---:|---:|---:|---:|---:|---|
| q5 | 132.1s | 78.2s | 1.0s | 132.1x | 78.2x | identical |
| q51 | 58.6s | 50.6s | 42.2s | 1.4x | 1.2x | identical |
| q4 | 59.0s | 22.1s | 7.5s | 7.9x | 2.9x | identical |
| q39 | 92.5s | 1.7s | 0.6s | 154.2x | 2.8x | identical |
| q31 | 26.0s | 0.5s | 0.5s | 52.0x | 1.0x | identical |
| **total** | **368.2s** | **153.1s** | **51.8s** | **7.11x** | **2.96x** |

## Aysha — 16 counted, 4 excluded

| query | A base | B before | C after | A→C | B→C | output |
|---|---:|---:|---:|---:|---:|---|
| q47 | 53.1s | 84.1s | 10.0s | 5.3x | 8.4x | **differs** |
| q14a | — | 55.8s | 3.5s | — | 15.9x | identical |
| q67 | 12.6s | 12.6s | 14.9s | 0.8x | 0.8x | identical |
| q43 | 5.0s | 9.0s | 1.0s | 5.0x | 9.0x | identical |
| q27 | 6.2s | 8.2s | 2.0s | 3.1x | 4.1x | identical |
| q35 | 8.2s | 2.7s | 0.5s | 16.4x | 5.4x | identical · index-only |
| q9 | 3.9s | 2.6s | 1.0s | 3.9x | 2.6x | identical |
| q38 | 9.6s | 2.1s | 1.9s | 5.1x | 1.1x | identical · index-only |
| q28 | 0.5s | 0.6s | 0.5s | 1.0x | 1.2x | identical |
| q80 | 0.8s | 0.6s | 0.2s | 4.0x | 3.0x | identical |
| q86 | 1.2s | 0.5s | 0.1s | 12.0x | 5.0x | identical |
| q21 | 23.7s | 0.5s | 0.3s | 79.0x | 1.7x | identical |
| q15 | 3.4s | 0.4s | 0.8s | 4.2x | 0.5x | identical rows, label differs |
| q60 | 1.6s | 0.4s | 0.3s | 5.3x | 1.3x | identical |
| q26 | 3.7s | 0.3s | 0.3s | 12.3x | 1.0x | identical |
| q12 | 0.4s | 0.1s | 0.1s | 4.0x | 1.0x | identical |
| **total** | **133.9s** (15/16) | **180.5s** | **37.4s** | **3.58x** | **4.83x** |

Excluded from Aysha's total:

- **q14b** — optimized SQL does not run: typo `item.i_braknd_id`
- **q54** — both sides return **zero rows** at scale 1, so the 250x is unverifiable — nothing proves the rewrite is equivalent
- **q61** — both sides return a single all-NULL row at scale 1; 0.0s carries no information
- **q97** — optimized SQL needs temp tables from `query97_v1_temp_tables.sql`, which the file does not create


## Totals

| contributor | queries | A base | B before | C after | saved (A→C) | A→C | B→C |
|---|---:|---:|---:|---:|---:|---:|---:|
| Claude | 6 | 520.1s | 241.1s | 155.9s | 364.2s | 3.34x | 1.55x |
| riccio | 5 | 368.2s | 153.1s | 51.8s | 316.4s | 7.11x | 2.96x |
| Aysha | 16 | 133.9s | 180.5s | 37.4s | 96.5s | 3.58x | 4.83x |
| **all** | **27** | **1022.2s** | **574.7s** | **245.1s** | **777.1s** | **4.17x** | **2.34x** |


## Per-query notes

- **q15** — column label only (`sum(cs_sales_price)` vs `sum_sales`)
- **q47** — same 100 rows and values, but `sum_sales` / `avg_monthly_sales` are **transposed** in the select list — needs reordering
- **q5** — re-measured with PIPES_AS_CONCAT; before this it returned 7 rows, not 100
- **q59** — column label only (`sun_sales1/sun_sales2` vs `sun_sales1 / sun_sales2`)
- **q72** — A was capped by `max_statement_time=300`, so 300.1s is a floor
- **q80** — re-measured with PIPES_AS_CONCAT; the *original* was the wrong one


## A bug this comparison uncovered: `||` is not concatenation in MariaDB

Four queries — **q5, q66, q80, q84** — use the ANSI string-concatenation
operator `||`. MariaDB only reads `||` that way when `PIPES_AS_CONCAT` is in
`sql_mode`; otherwise it is **logical OR**. It is not an error, so nothing
complained: the concatenated `id` column silently evaluated to `0` or `1`.

For q5 and q80 that collapses the `GROUP BY channel, id WITH ROLLUP` to a
handful of groups. Both returned **7 rows where TPC-DS expects 100**, which is
exactly the `ROWS_DIFF` those two have been recorded as in every run so far.

```
                       before fix          after fix
query5    ROWS_DIFF    rows=7/100          rows=100/100
query80   ROWS_DIFF    rows=7/100          rows=100/100
query66   VALUES_DIFF  ship_carriers=0/1   concatenated correctly
query84   ROWS_DIFF    customername=0/1    rows=26/25 (separate issue)
```

Fixed by adding `PIPES_AS_CONCAT` to the session `sql_mode` in
`queries/run_query.py` and `queries/timeq.py`. q5 and q80 in the table above
were re-measured with the fix; the other 29 pairs do not contain `||` and are
unaffected.

Two consequences worth stating plainly:

- **riccio's q5 was being measured on a degenerate query.** Both sides returned
  7 rows, so the grouping work that dominates the real q5 was never happening.
  Re-measured correctly it is **78.2s → 1.0s**, still the single largest win in
  the whole comparison.
- **Aysha's q80 rewrite was being scored against a broken original.** She wrote
  `concat('store', store_id)`, which is the correct MariaDB translation, so her
  version was right and the "before" was wrong — the 6.5x was an artefact of
  comparing a correct query against an incorrect one. The honest figure is 3.0x.

`q84` still returns 26 rows against an expected 25. That is a different defect
and is not investigated here.


## Method

- **One index set for everyone.** `sql/14_contributed_indexes.sql` holds all 41
  indexes the three of us prescribe, collected out of the `.sql` and `.md` files
  under `queries/optimized/`. 29 of them existed only on Aysha's machine. They
  were created here (2m54s total), followed by `ANALYZE TABLE`.
- `idx_ss_date_item_store_cover`, which Aysha's q47 `FORCE INDEX`es, has **no
  `CREATE` statement anywhere in the repo**. It is inferred here as
  `store_sales(ss_sold_date_sk, ss_item_sk, ss_store_sk, ss_sales_price)`, which
  is what the query needs to be covering. If her real definition differs, q47's
  number moves.
- **Before and after run back to back** in one session per query — the
  interleaved method, which on this machine gives a far cleaner signal than
  A/B/A.
- **Each folder's own original is the "before"**, not the tier baseline, so the
  pair lines up statement for statement. q14 is Aysha's A and B parts measured
  separately; q39 is both of its statements.
- Session `SET`s a contributor's file carries (q38, q67 raise `tmp_table_size`
  and friends) are applied to their "after" only, as part of their submission.
- Output is compared for every pair: header, row multiset, and row order.

### What the A and B columns are not

Column **A** comes from the earlier serial benchmark, a different session on the
same machine and config. It is a reasonable reference point, not a controlled
measurement against B and C — only `B→C` is a within-pass comparison. Several
queries are *slower* in B than in A (q2, q47, q54, q67, q43, q27, q28, q59)
because 29 extra indexes give the optimizer more ways to choose wrong.


## What the numbers actually say

**The ranking flips depending on which question you ask.**

By `A→C` — the end-to-end gain, index work included — riccio leads at 7.11x.
By `B→C` — the SQL rewrite alone, with everyone's indexes available to the
original too — Aysha leads at 4.83x and my own work drops to **1.55x**, the
weakest of the three.

That gap is the real finding. Four of my six queries lose most of their
advantage once the index exists for the original as well:

| query | claimed earlier | `B→C` here | where the win actually came from |
|---|---:|---:|---|
| q59 | 6.1x | **1.0x** | entirely `idx_ss_sold_date_sk_store_sales_price` + `idx_dd_week_seq` |
| q72 | 719x | **1.1x** | the index; the original is now 90.6s, not a 300s timeout |
| q88 | ~130x | 8.0x | mostly `idx_ss_store_hdemo_time`, some rewrite |
| q78 | 3.2x | 1.7x | partly `idx_ss_q78` |
| q22 | 5.3x | 1.8x | partly `idx_inv_item_date_sk` |
| q2 | 3.2x | **3.3x** | genuinely the rewrite |

Only q2 survives intact. My earlier per-query figures were honest about *what I
measured* — each was the query plus its index against a baseline with neither —
but they attribute to the rewrite what the index was doing. q72 is the starkest:
it was never a 719x rewrite, it was an index that took a timing-out query down
to 90 seconds.

**q72 and q59 are now actively worth revisiting.** Both of my rewrites are at or
below parity with their own originals under the full index set (q59: 20.2s vs
19.8s; q72: 84.9s vs 90.6s). The plans they were tuned against no longer exist.

**Two of Aysha's entries are index-only.** `q35_Optimized.sql` and
`q38_Optimized.sql` contain no rewritten query at all — they are pure
`CREATE INDEX` files. Their "after" is the original text against the new
indexes, which is legitimate optimization work, but it is index work, not query
work, and `B→C` credits it as the latter.


## Fixes this run identified

| # | item | fix |
|---|---|---|
| 1 | `queries/mariadb/{query5,66,80,84}.sql` read `\|\|` as logical OR | done — `PIPES_AS_CONCAT` added to `run_query.py` and `timeq.py` |
| 2 | `Aysha/q14/Query-14-B` — typo `item.i_braknd_id` | correct to `i_brand_id`; the query has never executed |
| 3 | `Aysha/q47` — `sum_sales` and `avg_monthly_sales` transposed | reorder the select list; no performance cost |
| 4 | `Aysha/q97/query97_BEST.sql` — references `ssci_t` / `csci_t` | ship the `CREATE TEMPORARY TABLE` statements with it |
| 5 | `Aysha/q47` — `idx_ss_date_item_store_cover` has no `CREATE` | add the real DDL to the folder |
| 6 | `Aysha/q54`, `Aysha/q61` — degenerate results at scale 1 | re-verify at a larger scale factor, or on parameters that return rows |
| 7 | q72, q59 — rewrites no longer beat their originals | re-tune against the 188-index plans |

Items 2–6 are Aysha's files and are left as findings rather than edited here.
