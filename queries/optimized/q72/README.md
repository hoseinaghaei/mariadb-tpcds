# query 72 — 719.3s → 1.0s (719x)

Original: `queries/mariadb/query72.sql`.
Every variant produces **byte-identical output** to it (100 rows).

| File | Time | Change |
|---|---:|---|
| *(original)* | 719.3s | — |
| `query72_v2_nohint.sql` | 619.3s → 90.4s | reordered FROM, **no hint** |
| `query72_v7_pkdrive_nohint.sql` | 569.2s | restructured, no hint |
| `query72_v8_fullorder.sql` | 11.8s | full `JOIN_ORDER(...)` for all 11 tables |
| `query72_v6_pkdrive.sql` | 13.8s → 7.8s | `d2` before `inventory`, forcing PK access |
| `query72_v9_pkdrive_idx.sql` | 7.8s | v6 re-measured with `idx_dd_week_seq` |
| `query72_v10_combined.sql` | 5.1s | v6 structure + v5 prefix |
| `query72_v3_orig_plus_hint.sql` | 13.0s | original order + hint |
| `query72_v1_user.sql` | 13.1s → 2.7s | reorder + `JOIN_PREFIX(catalog_sales)` |
| **`query72_BEST.sql`** = `query72_v5_demofirst.sql` | **1.0s** | `JOIN_PREFIX(d1, catalog_sales, household_demographics, customer_demographics)` |

Where two numbers appear, the second is after adding `idx_dd_week_seq`.

## Two independent causes

**1. The optimizer hint — ~55x.** Ablation:

| | |
|---|---:|
| original order, no hint | 719.3s |
| reordered FROM, no hint | 619.3s |
| original order, **with hint** | **13.0s** |

Rewriting join order in SQL text is worth 14%. The hint is worth 55x.

**2. A missing index — ~13x.**

```sql
CREATE INDEX idx_dd_week_seq ON date_dim (d_week_seq);
```

The query self-joins `date_dim` on `d_week_seq`, which had **no index** — a
full scan of 72,124 rows per driving row. With it, `d2` becomes `ref rows=6`,
and `inventory` is then reached via its PRIMARY KEY at `ref rows=4` instead of
`idx_inv_item_sk` at `ref rows=527`.

## Lesson

`JOIN_PREFIX` beat full `JOIN_ORDER` every time. Give a prefix and let the
optimizer choose the rest.

Full writeup: [`report/18-query-optimization.md`](../../../report/18-query-optimization.md)
