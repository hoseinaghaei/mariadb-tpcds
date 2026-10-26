# query 70 — 93.248s → 24.549s (3.80x, SF=4)

Original: [`queries/mariadb/query70.sql`](../../mariadb/query70.sql).
[`query70_v0.sql`](query70_v0.sql) remains an exact copy.
The selected SQL is [`query70_BEST.sql`](query70_BEST.sql), renamed from
`query70_v2_store_preaggregation.sql` without changing its contents.
Both returned **3 identical ordered rows** in the final SF=4 check.

| File | Recorded time | Change / decision |
|---|---:|---|
| [`query70_v0.sql`](query70_v0.sql) | 93.248s | Original, final comparison control |
| [`query70_v1_state_filter.sql`](query70_v1_state_filter.sql) | Not separately timed | Still an unchanged baseline copy; placeholder |
| **[`query70_BEST.sql`](query70_BEST.sql)** | **24.549s** | Remove redundant inner ranking, aggregate by store once, filter dates early |

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

Sum store net profit over month sequences **1176–1187**, group by state and
county with `ROLLUP`, and rank the grouped totals within the original
hierarchy partitions. Keep subtotal/grand-total rows, hierarchy flags,
`RANK` tie behavior, output order and `LIMIT 100`.

The supplied SQL has two different rankings. The outer rank is returned and
must remain. The inner state-membership rank is redundant for this particular
query; it does not implement a global top-five-state selection.

## Steps and why they help

1. The inner subquery groups by state and then calculates:

   ```sql
   RANK() OVER (PARTITION BY s_state ORDER BY SUM(ss_net_profit) DESC)
   ```

   Every state partition contains one grouped row, so every rank is 1 and
   passes `ranking <= 5`.
2. The inner and outer branches use the same sales/date/store joins and
   period. Every eligible non-NULL outer state is therefore present in the
   inner result. Replace the membership subquery with `s.s_state IS NOT NULL`.
   A NULL state would not pass the original `IN` condition.
3. Apply that condition **before** `GROUP BY ... WITH ROLLUP`. Filtering
   generated rollup NULLs afterward would remove valid totals. Preserve the
   outer window rank and the original NULL-based hierarchy expressions.
4. Aggregate filtered sales into `profit_by_store` first, then join the store
   dimension and roll up its states/counties. This sends store totals to the
   geographical grouping rather than individual sale rows. The original
   inner branch no longer causes a second fact aggregation.
5. Remove the earlier joined bounds CTE. Add scalar min/max bounds on the
   fact date key while retaining the exact date join/month predicate.
   The final `EXPLAIN` shows one fact scan with that filter, then the grouped
   store result feeding the rollup.

| Development check | Original | Candidate | Correctness |
|---|---:|---:|---|
| Inner-rank removal + store preaggregation, before final scalar bounds | 94.949s | 37.268s | Exact match, 3 rows |
| Final selected SQL | 93.248s | 24.549s | Exact match, 3 rows |

The earlier intermediate was edited in place and is not a retained SQL file.
These are separate single-pair checks. Inner-rank removal and preaggregation
were tested together; their individual speedup contributions were not isolated.

## Correctness

The final comparison matched all output column labels, full decimal values,
NULLs, ranks and all 3 rows in order. A separate temporary-table fixture also
matched exactly: **13 rows**, with six eligible non-NULL states plus a NULL
state, a NULL county, multiple stores in one county, tied profits, NULL and
negative profits, missing dimension keys and period boundaries. The fixture
was executed in memory, not saved as a fixture file.

Keeping all six eligible states in that fixture confirms that the rewrite
did not accidentally introduce a global top-five rule. Rollup-generated NULLs
and the outer rank remain. No index or server configuration change was used;
the large sales scan is still present.

## Reproduce

From the repository root, with the SF=4/seed=10 database already loaded:

```bash
python3 scripts/sf4.py compare \
  --database tpcds_sf4_seed10 \
  --baseline queries/optimized/q70/query70_v0.sql \
  --optimized queries/optimized/q70/query70_BEST.sql \
  --repeats 3 --timeout 300 \
  --out experiments/local/q70_best_sf4.csv
```

This command runs new alternating comparisons and saves their timings; it
does not reproduce a controlled cold-cache state. It requires the existing
`scripts/sf4.py` helper and MariaDB client on `PATH`.
