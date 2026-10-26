# query 65 — 91.718s → 45.167s (2.03x, SF=4)

Original: [`queries/mariadb/query65.sql`](../../mariadb/query65.sql).
[`query65_v0.sql`](query65_v0.sql) remains an exact copy.
The selected SQL is [`query65_BEST.sql`](query65_BEST.sql), renamed from
`query65_v2_single_aggregation.sql` without changing its contents.
The final check returned **the same 100 rows and values**, including duplicate
counts, but **not identical row order within tied sort keys**.

| File | Recorded time | Change / decision |
|---|---:|---|
| [`query65_v0.sql`](query65_v0.sql) | 91.718s | Original, final comparison control |
| [`query65_v1_window.sql`](query65_v1_window.sql) | Not separately timed | Still an unchanged baseline copy; no window rewrite is implemented in this file |
| **[`query65_BEST.sql`](query65_BEST.sql)** | **45.167s** | One store/item aggregation, full-store window average and early date-key filtering |

## Measurement setup

Local SF=4, seed=10 database: `tpcds_sf4_seed10`. Linux laptop with a Ryzen 5
3500U and about 6.7 GiB of visible RAM; MariaDB 10.11.14, a 2 GiB InnoDB buffer
pool and 16 MiB temporary-table limits. The database had primary keys only;
these rewrites added no secondary indexes or server configuration changes.

The final timings are one sequential original-then-BEST pair, **n=1 per
version**, with the query cache disabled for each connection. Time includes
connection, session setup, SQL execution and complete result transfer. There
was no controlled cache reset. These are local observations, not repeated-run
medians or the final group benchmark. Final-pair timings and checks were
printed during the interactive experiment; their raw outputs and plans were
not saved as repository artifacts. Earlier diagnostic runs are identified
separately below.

## What the query must do

For month sequences **1176–1187**, calculate `SUM(ss_sales_price)` for each
**store key + item key**. Average those item totals within each store, then
return items whose revenue is at most **0.1 × that store's average**. Join the
store/item descriptions and keep the six original output fields,
`ORDER BY s_store_name, i_item_desc` and `LIMIT 100`.

The average is over item totals, not sale prices or individual transactions.
Changing the measure to extended sales price would also change the query.

## Steps and why they help

1. The original contains the store/item revenue aggregation twice: once to
   calculate store averages and once to supply the item totals. `EXPLAIN`
   showed separate sales access paths for these two branches.
2. Build `item_revenue` once, then calculate `AVG(revenue)` with a window over
   the store partition. The final plan contains one `store_sales` scan for
   this aggregation, followed by the window stage.
3. The saved SQL has `ORDER BY ss_item_sk` inside the window, so its explicit
   frame is essential:

   ```sql
   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
   ```

   It averages the whole store partition, rather than a running prefix.
4. Calculate the average **before** the final item/store joins. A fact group
   with a missing item dimension row must still contribute to the original
   average before that group disappears from the final output. `AVG` also
   continues to ignore NULL totals; zero and negative totals are not removed.
5. Remove the joined bounds CTE from an earlier attempt. Use scalar `MIN` and
   `MAX` date-key subqueries as a redundant filter on `ss_sold_date_sk`.
   `EXPLAIN` places that condition on the fact scan, before date lookups.
   Keep the original date join/month filter: the numeric bounds alone would
   not prove exact membership if the qualifying keys had gaps.

An earlier in-place window rewrite, before the final date filtering/window
revision, took **57.345s**, against **91.205s** for its control. Its ordered
comparison differed; a full row-multiset check was not recorded for that
intermediate. Its SQL was not saved separately. The final pair above validates
the final SQL's returned row multiset; the intermediate is not a certified
ablation of the individual changes.

## Correctness and the ordering caveat

The final ordered comparison was **false**; the full row-multiset comparison,
including column labels, exact values, NULLs and duplicate counts, was **true**.
For example, rows with the same store name and item description but revenues
`2.56` and `0.35` exchanged places. The original ORDER BY does not distinguish
those rows. The window's internal ordering does not resolve the outer ties.

Do not describe this result as byte-identical output. The existing strict
runner can report `RESULT_DIFF` and stop on this tie-order difference. On a
different scale or plan, a tie crossing the LIMIT boundary could also change
which tied rows are selected. A deterministic tie-breaking policy for both
versions is still needed before claiming strict agreement across machines;
this change leaves the original baseline and final ORDER BY untouched.

A separate nonempty temporary-table fixture matched exactly: **11 rows**. It
covered orphan item/store keys, NULL revenue groups, zero/negative totals,
values exactly on the threshold, date boundaries and out-of-period keys
inside the numeric bounds. This fixture was executed in memory, not saved.

The full fact scan remains: this rewrite reduced runtime without adding an
index, but did not make Q65 a sub-20-second query on this laptop.

## Reproduce

From the repository root, with the SF=4/seed=10 database already loaded:

```bash
python3 scripts/sf4.py compare \
  --database tpcds_sf4_seed10 \
  --baseline queries/optimized/q65/query65_v0.sql \
  --optimized queries/optimized/q65/query65_BEST.sql \
  --repeats 3 --timeout 300 \
  --out experiments/local/q65_best_sf4.csv
```

This command runs new alternating comparisons and saves their timings; it
does not reproduce a controlled cold-cache state. It requires the existing
`scripts/sf4.py` helper and MariaDB client on `PATH`.

For this query, inspect the saved XML if the strict runner reports
`RESULT_DIFF`. Compare complete rows with duplicate counts and NULLs preserved,
then inspect tied sort keys and the LIMIT boundary; matching row counts alone
are insufficient. The 2.03x timing ratio is an observed local ratio, not a
strict-result-pass claim from that runner.
