# Step 18 — Query optimisation log

> **NOT COMPARABLE TO TPC BENCHMARK RESULTS.**

A running record of hand-optimised queries. Each entry states the change, the
measured effect, and — critically — confirmation that the output is
**byte-identical** to the unmodified query. An optimisation that changes
results is not an optimisation.

---

## query 72 — 719.3s → 1.0s (**719x**)

The worst query in the set. It failed to complete within `max_statement_time`
in every benchmark run, and consumed 21 and 29 minutes on two earlier attempts
before the cap existed.

### Result

| Version | Time | Output |
|---|---:|---|
| Original | **719.3s** | — |
| Original + `idx_dd_week_seq` | 87.8s | identical |
| v2: join reorder, no hint | 619.3s → 90.4s | identical |
| v3: original order + hint | 13.0s | identical |
| **v1: reorder + hint** *(contributed)* | **13.1s → 2.7s** | identical |
| **v5: `JOIN_PREFIX(d1, catalog_sales, hd, cd)`** | **1.0s** | **identical** |

All variants verified byte-for-byte against the original's 100 rows.

### What actually causes the speedup

Two independent factors, isolated by ablation:

**1. The optimizer hint — worth ~55x on its own.**

MariaDB 13.0.2 supports optimizer hints (confirmed: a bogus hint name raises
`Warning 1064: Optimizer hint syntax error`, so they are parsed, not ignored).

Ablation:

| | |
|---|---:|
| original order, **no** hint | 719.3s |
| reordered FROM clause, **no** hint | 619.3s |
| original order, **with** hint | **13.0s** |

**The FROM-clause reorder is worth 14%. The hint is worth 55x.** Rewriting the
join order in the SQL text barely moves MariaDB; the hint is what moves it.

**2. A missing index on `date_dim(d_week_seq)` — worth another ~13x.**

Query 72 self-joins `date_dim` as `d1` and `d2` and correlates them on
`d1.d_week_seq = d2.d_week_seq`. **No index existed on `d_week_seq`**, so that
join was resolved by a full scan of 72,124 rows per driving row.

```sql
CREATE INDEX idx_dd_week_seq ON date_dim (d_week_seq);
```

**Only `d_week_seq` is declared.** InnoDB appends the primary key to every
secondary index leaf, so adding `d_date_sk` explicitly is redundant. Verified
both ways:

| Definition | Index size | `key_len` | `Extra` | query 72 |
|---|---:|---:|---|---:|
| `(d_week_seq, d_date_sk)` | 161 pages | 9 | `Using index` | 1.0s |
| `(d_week_seq)` | **161 pages** | **9** | **`Using index`** | **1.0s** |

Identical on every measure. The `Using index` is the proof: the query needs
`d2.d_date_sk` for the `inv_date_sk = d2.d_date_sk` join, and the plan reports
a covering index even though only `d_week_seq` is declared — so the implicit
primary-key suffix is genuinely being served from the index.

`d2` becomes `ref rows=6`. And because `d2` now resolves cheaply, `inventory`
can be reached through its **PRIMARY KEY** `(inv_date_sk, inv_item_sk)` —
`ref rows=4` — instead of the secondary index `idx_inv_item_sk` at
`ref rows=527`. A 130x tighter inner loop.

This is the same `inventory` secondary index implicated in the
[step 13](13-benchmark-results.md) regressions. Here the fix is not to hide it
but to give the optimizer a better path to prefer.

### The winning plan

```
d1                     ref     inx_date_dim_year              rows=365
catalog_sales          ref     idx_cs_sold_date_sk            rows=955
household_demographics eq_ref  idx_hd_demo_sk_buy_potential   rows=1
customer_demographics  eq_ref  idx_cd_demo_sk_marital_status  rows=1
item                   eq_ref  PRIMARY                        rows=1
d3                     eq_ref  PRIMARY                        rows=1
promotion              eq_ref  PRIMARY                        rows=1
d2                     ref     idx_dd_week_seq                rows=6
inventory              ref     PRIMARY                        rows=4
warehouse              eq_ref  PRIMARY                        rows=1
```

Driving from `date_dim` filtered to 1999 (365 rows) means `catalog_sales` is
filtered **before** the inventory join rather than after — 955 rows per date
instead of a 1.76M-row full scan.

### Variants that did not win

| Variant | Time | Why |
|---|---:|---|
| v9: restructured so `d2` precedes `inventory`, forcing PK access | 7.8s | the explicit restructure is unnecessary once `idx_dd_week_seq` exists — the optimizer finds it |
| v8: full `JOIN_ORDER(...)` for all 11 tables | 11.8s | over-constrains; the optimizer does better with a prefix and freedom after it |
| v10: v9's structure + v5's prefix | 5.1s | the two changes fight each other |

**Specifying a prefix and letting the optimizer choose the rest beat
specifying the whole order every time.**

### The final query

`queries/optimized/query72_BEST.sql`

```sql
select /*+ JOIN_PREFIX(d1, catalog_sales, household_demographics, customer_demographics) */
    i_item_desc, w_warehouse_name, d1.d_week_seq
     , sum(IF(p_promo_sk is null, 1, 0))     no_promo
     , sum(IF(p_promo_sk is not null, 1, 0)) promo
     , count(*)                              total_cnt
from catalog_sales
         join date_dim d1 on (cs_sold_date_sk = d1.d_date_sk)
         join inventory on (cs_item_sk = inv_item_sk)
         join warehouse on (w_warehouse_sk = inv_warehouse_sk)
         join item on (i_item_sk = cs_item_sk)
         join customer_demographics on (cs_bill_cdemo_sk = cd_demo_sk)
         join household_demographics on (cs_bill_hdemo_sk = hd_demo_sk)
         join date_dim d2 on (inv_date_sk = d2.d_date_sk)
         join date_dim d3 on (cs_ship_date_sk = d3.d_date_sk)
         left outer join promotion on (cs_promo_sk = p_promo_sk)
         left outer join catalog_returns on (cr_item_sk = cs_item_sk and cr_order_number = cs_order_number)
where d1.d_week_seq = d2.d_week_seq
  and inv_quantity_on_hand < cs_quantity
  and d3.d_date > d1.d_date + 5
  and hd_buy_potential = '1001-5000'
  and d1.d_year = 1999
  and cd_marital_status = 'M'
group by i_item_desc, w_warehouse_name, d1.d_week_seq
order by total_cnt desc, i_item_desc, w_warehouse_name, d_week_seq
limit 100;
```

`IF(x is null, 1, 0)` replaces `case when x is null then 1 else 0 end` —
equivalent, and shorter.

---

## Indexes added for optimisation

`sql/11_optimizer_indexes.sql` — seven beyond the repo's 117:

| Index | Purpose |
|---|---|
| **`date_dim(d_week_seq)`** | **the highest-value index found: query 72 alone, 13.1s → 1.0s** |
| `household_demographics(hd_demo_sk, hd_buy_potential)` | covering; join satisfied from the index |
| `customer_demographics(cd_demo_sk, cd_marital_status)` | covering; same |
| `date_dim(d_year)`, `(d_year, d_moy)`, `(d_date)`, `(d_date_sk, d_year, d_date)` | date access paths |

Clause 2.5.3 restricts auxiliary data structures, so these would need
justifying for an audited result. Fine for optimisation work.

---

## Method notes

1. **Always diff the output against the unmodified query.** Every figure here
   is backed by a byte-identical comparison of all 100 rows.
2. **Ablate.** The intuition was that the rewritten join order mattered; the
   ablation showed it was worth 14% while the hint was worth 55x. Without
   separating them, the wrong lesson gets learned.
3. **Re-run before believing.** v5 measured 1.0s twice. Absolute timings in
   this project vary by roughly ±50% with cache state — see
   [step 13](13-benchmark-results.md).
4. **Prefer a prefix hint to a full order.** `JOIN_PREFIX` beat `JOIN_ORDER`
   in every comparison here.

## Still open

- Query 72 is no longer the worst query. The remaining tier-5 queries
  (23, 5, 14, 2, 39) have not had this treatment.
- Query 39's regression is still unaddressed by hints — see
  [step 13](13-benchmark-results.md); its fix is hiding two `inventory`
  indexes, which is a different lever.
- Whether `idx_dd_week_seq` helps other queries is unmeasured. Several TPC-DS
  queries correlate dates on `d_week_seq`.
