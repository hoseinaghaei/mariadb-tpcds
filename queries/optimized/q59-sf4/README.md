# q59 at SF=4 — 186.7s to 4.8s

Measured on 32K pages, SF=4, 8 GB pool, sample 160, under the T1 tuning.
Output is **byte-for-byte identical** to the original at every step.

| version | time | vs original |
|---|---:|---:|
| original | 186.7s | — |
| week-filtered CTE alone | 167.8s | 1.05x |
| original + `split_materialized=off` | 14.6s | 12.0x |
| **both (`query59_BEST.sql`)** | **4.8s** | **38.9x** |

## The actual cost, found with ANALYZE FORMAT=JSON

| node | ms | loops |
|---|---:|---:|
| `materialized` | **164,024** | **7,665** |
| `materialized` | 2,351 | 1 |

q59 defines a CTE `wss` and references it twice. One reference materialises
once, in 2.4s. **The other is re-materialised 7,665 times — once per outer
row — accounting for 164s of the 167s.**

That is MariaDB's split-materialisation ("lateral derived") strategy: recompute
a derived table per outer row rather than once. It is a good trade when the
derived table is a selective lookup and a disaster when it is a full
aggregate over 15.5M rows, as here.

## This also explains why q59 looked unstable

q59 was measured at **15.3s in one run and ~155s in a dozen others**, with
identical output, and resisted explanation. Those are simply the two plans:
15.3s is the no-split plan, ~155s is the split plan. The optimizer picks
between them and its choice moved between runs.

Six candidate causes were eliminated by direct test before the real one was
found — worth recording so they are not re-investigated:

| hypothesis | test | result |
|---|---|---|
| histograms / EITS | cleared `column_stats` to 0 + `FLUSH TABLES` | still 157.8s |
| stale InnoDB stats | plain `ANALYZE TABLE` | still 159.2s |
| `join_cache_level=8` | session `join_cache_level=2` | still 162.6s |
| MRR forced on | session `mrr=off` | still 163.3s |
| OS / pool cache residency | three consecutive warm runs | 152–160s |
| `use_stat_tables=never` | both values, EITS empty | 156.5 / 153.7s |
| T1's exact config rebuilt | all of the above together | 166.4s, 170.9s |

## Change 1 — `split_materialized=off` (12.0x)

```sql
SET SESSION optimizer_switch = 'split_materialized=off';
```

Session-scoped, so it affects only this query. Worth 175.5s → 14.6s on the
**unmodified** query, which makes it the single most valuable change and one
that needs no rewrite at all.

## Change 2 — bound the CTE to the weeks the query can use (3.0x more)

The CTE aggregates all of `store_sales` grouped by `(d_week_seq,
ss_store_sk)`, but the outer query reads only two 12-month windows:
**105 weeks of 262, 2,310 groups of 5,764.**

```sql
and d_week_seq between (select min(d_week_seq) from date_dim
                         where d_month_seq between 1192 and 1192 + 23)
                   and (select max(d_week_seq) from date_dim
                         where d_month_seq between 1192 and 1192 + 23)
```

**Filtering by `d_week_seq` and not by date is what makes this safe.** A week
is included or excluded whole, so every surviving `(week, store)` group still
aggregates exactly the rows it did before — including days falling outside
months 1192–1215. Filtering on dates instead would be **wrong**: a boundary
week would lose days and its seven `sum(case ...)` values would change.

Over-inclusion is harmless as well, since the outer references re-filter on
`d_month_seq`.

On its own this change is worth only 1.05x — while the CTE was being
re-materialised 7,665 times, making it 60% cheaper barely moved the total.
Together with change 1 it is worth 3.0x. The order matters for understanding
the result, not for applying it.

## What did not help

Covering indexes on `date_dim(d_date_sk, d_week_seq, d_day_name)` and
`date_dim(d_month_seq, d_week_seq)` moved it 4.8s → 4.7s, inside noise, and
were dropped. `store_sales` already carries
`idx_ss_sold_date_sk_store_sales_price`, which the plan uses as a covering
index. **This query was never index-starved** — it was executing the right
access path thousands of times too often.

## Files

| file | |
|---|---|
| `query59_BEST.sql` | both changes, self-contained, 4.8s |
| `query59_v1_weekfilter.sql` | the CTE filter alone, 167.8s |
| `test.sh` | times any variant against the original and diffs the output |
