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

---

## Seven indexes duplicate their own PRIMARY KEY — 470 MB wasted

Prompted by noticing that `date_dim(d_week_seq, d_date_sk)` named the primary
key redundantly, the whole index set was audited for the same mistake.

InnoDB appends the primary key to every secondary index leaf. So an index whose
columns are a **leading prefix of the PRIMARY KEY** indexes nothing the
clustered index does not already index, in the same order.

Seven of the 124 are exactly that:

| Table | Index | Index cols | PRIMARY KEY | Pages | Size |
|---|---|---|---|---:|---:|
| `inventory` | `idx_inv_date_sk` | `inv_date_sk` | `(inv_date_sk, inv_item_sk, inv_warehouse_sk)` | 21,759 | **340 MB** |
| `store_sales` | `idx_ss_item_sk` | `ss_item_sk` | `(ss_item_sk, ss_ticket_number)` | 4,135 | 65 MB |
| `catalog_sales` | `idx_cs_item_sk` | `cs_item_sk` | `(cs_item_sk, cs_order_number)` | 2,212 | 35 MB |
| `web_sales` | `idx_ws_item_sk` | `ws_item_sk` | `(ws_item_sk, ws_order_number)` | 1,123 | 18 MB |
| `store_returns` | `idx_sr_item_sk` | `sr_item_sk` | `(sr_item_sk, sr_ticket_number)` | 481 | 8 MB |
| `catalog_returns` | `idx_cr_item_sk` | `cr_item_sk` | `(cr_item_sk, cr_order_number)` | 225 | 4 MB |
| `web_returns` | `idx_wr_item_sk` | `wr_item_sk` | `(wr_item_sk, wr_order_number)` | 161 | 3 MB |

**470 MB total**, plus write amplification on every insert.

### Proof

```
SELECT COUNT(*) FROM store_sales WHERE ss_item_sk = 100

  with idx_ss_item_sk :  key=idx_ss_item_sk   key_len=8   rows=129
  with it IGNORED     :  key=PRIMARY          key_len=8   rows=129
```

Identical access path, key length and row estimate. For `inventory` the
optimizer **already** prefers `PRIMARY` and never touches `idx_inv_date_sk` —
which is why that index turned up in the never-read set in
[step 15](15-index-statistics.md).

### Why this differs from the "never read" set

[Step 17](17-unused-indexes-are-not-safe-to-drop.md) showed that "no query read
it" is a weak basis for dropping an index — an index can shape a plan without
being read.

This is a **structural** argument instead: a leading prefix of the primary key
is redundant by definition, on any workload, because InnoDB's clustered index
already provides exactly that ordering. It does not depend on which queries
happen to run.

`sql/12_drop_redundant_indexes.sql`.

### Indexes that are *not* redundant

An index on a **non-leading** primary key column is not redundant — the
clustered index cannot serve a lookup that skips its first column. So
`idx_ss_ticket_number`, `idx_inv_item_sk`, `idx_inv_warehouse_sk`,
`idx_cs_order_number` and the rest are all legitimate, even though every one of
their columns appears in a primary key.

That distinction matters: `idx_inv_item_sk` and `idx_inv_warehouse_sk` are the
two indexes causing the worst regressions in
[step 13](13-benchmark-results.md), and they are *not* structurally redundant —
they are genuinely useful access paths that the optimizer mis-costs.

### General rule

Never name primary key columns in a secondary index on InnoDB, and never create
a secondary index on a leading prefix of the primary key.

---

## query 59 — 7.3s → 1.2s (**6.1x**)

### Result

| Version | Time | Output |
|---|---:|---|
| Original | **7.3s** | — |
| + covering index *(contributed)* | 3.0s | identical |
| **+ CTE date-range filter** | **1.2s** | **identical** |

Measured three times at 1.2–1.3s. All variants byte-identical to the original's
100 rows.

### What the contributed index does

```sql
CREATE INDEX idx_ss_sold_date_sk_store_sales_price
    ON store_sales (ss_sold_date_sk, ss_store_sk, ss_sales_price);
```

Query 59's CTE sums `ss_sales_price` grouped by `(d_week_seq, ss_store_sk)`.
This index carries all three columns the CTE touches, so the scan is satisfied
entirely from the index — `Using index`, no row lookups. **7.3s → 3.0s.**

The query text was unchanged; the whole gain is the index.

### What was left on the table

`EXPLAIN` showed two problems:

1. **The CTE is materialised twice** — two `DERIVED` entries, each scanning
   `store_sales`.
2. **It scans all 2,879,152 rows** when only **1,101,383** are needed. The
   outer query only uses weeks in `d_month_seq` 1192–1215, which is 105 of the
   10,436 week values in `date_dim`.

Restricting the CTE fixes both copies at once:

```sql
where d_date_sk = ss_sold_date_sk
  and ss_sold_date_sk between
      (select min(d_date_sk) from date_dim
        where d_week_seq in (select d_week_seq from date_dim
                             where d_month_seq between 1192 and 1192 + 23))
  and (select max(d_date_sk) from date_dim
        where d_week_seq in (select d_week_seq from date_dim
                             where d_month_seq between 1192 and 1192 + 23))
```

**Why this is safe.** It selects *whole weeks*, so every surviving week's
aggregate is computed over all of its sales, exactly as before. Weeks outside
the range were going to be discarded by the outer join's month filter anyway.
Filtering on the sales' own `d_month_seq` instead would **not** be safe — a
week straddling a month boundary would lose part of its total.

### Variants that lost

| Variant | Time | Why |
|---|---:|---|
| `d_week_seq IN (...)` instead of a date range | 2.1s | set membership, not a range — the covering index cannot range-scan |
| `d_month_seq between 1191 and 1216` (wider, no subquery) | 1.9s | simpler and still safe, but the plan applies the filter *after* scanning `store_sales` |
| the above + `JOIN_PREFIX(date_dim)` | 1.6s | the hint reached only one of the two CTE copies |

The wide-month form is the most readable and only 0.7s behind. It is safe
because a week spans 7 days and a month at least 28, so any week touching
months 1192–1215 lies entirely inside 1191–1216.

### An index that looked obvious and was 10x wrong

`date_dim` has no index on `d_month_seq`, and several queries filter on it, so
adding one seemed clearly right:

```sql
CREATE INDEX idx_dd_month_seq ON date_dim (d_month_seq);
```

Query 59 went from **1.2s to 12.7s**. Three-pass confirmed:

| | query 59 |
|---|---:|
| index visible | 12.7s |
| **IGNORED** | **1.2s** |
| visible again | 12.6s |

Dropped. It is recorded as rejected in `sql/11_optimizer_indexes.sql` so nobody
adds it again on the same reasoning.

This is the third time in this project that an index has made things
dramatically worse — see also the two `inventory` indexes in
[step 13](13-benchmark-results.md). On this workload, adding an index is about
as likely to hurt as to help, and only measurement distinguishes the cases.
