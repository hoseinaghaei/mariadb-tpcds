# q23 at SF=4 — diagnosed, two rewrites, no measurable gain

q23 is the most expensive query in the suite: **173.6s at SF=4, 28% of the
tier-4/5 total**, and nobody had optimized it. This records what was found,
what was tried, and why neither rewrite can be called an improvement.

## The diagnosis is solid

`ANALYZE FORMAT=JSON`, for **each** of q23's two statements:

| node | ms | loops |
|---|---:|---:|
| `materialized` | 30,782 | **55,882** |
| `materialized` | 15,537 | **28,222** |
| `materialized` | 12,485 | 1,987 |
| `materialized` | 10,918 | 1,034 |
| `materialized` | 10,138 | 1 |

That is 79.8s of statement 1's 90.2s. Statement 2 is the same query above its
final SELECT and measures 85.1s, so the total of ~175s is roughly 90%
re-materialisation of three CTEs — and the whole thing happens twice.

## Two rewrites, neither demonstrably better

| variant | runs (s) | min | max | mean | spread |
|---|---|---:|---:|---:|---:|
| original | 171.5, 184.2, 185, 198 | 171.5 | 198.0 | 184.7 | 15% |
| `query23_v1_joins.sql` | 166.1, 162.9, 206, 240 | 162.9 | 240.0 | 193.8 | **47%** |
| `query23_v2_unionfirst.sql` | 193, 148 | 148.0 | 193.0 | 170.5 | 30% |

**Every range overlaps the original's.** Both rewrites produce byte-identical
output with `rc=0`, so they are correct — but on this host q23's run-to-run
variation is larger than any difference between them, and no ranking drawn
from these numbers would survive another pass.

v1 is the clearest warning: its first two runs were 166.1s and 162.9s, which
looked like a consistent 7.5% gain. Two more runs gave 206s and 240s.

## What the rewrites do

**v1 — `IN` subqueries become joins.** Each set is produced and probed rather
than rebuilt. Exact because `frequent_ss_items` is reduced to
`SELECT DISTINCT item_sk` (its `(itemdesc, item_sk, d_date)` grouping repeats
`item_sk`, so a plain join would multiply fact rows), and `best_ss_customer`
groups by `c_customer_sk` and is already unique.

**v2 — union the channels first, then join once.**

```
(catalog ⋈ fsi ⋈ bsc) UNION ALL (web ⋈ fsi ⋈ bsc)
→  (catalog UNION ALL web) ⋈ fsi ⋈ bsc
```

This halves the references to each shared set, from two per statement to one.
The date filter deliberately stays inside each branch: `d_year = 1999 AND
d_moy = 7` is the most selective predicate available, and hoisting it would
union two whole fact tables first.

That v2 showed no reliable gain is itself informative — **the loop counts are
not driven by how many times a CTE appears in the query text**, which was the
hypothesis behind it.

## Why q23 resists in-query optimization

**Half the cost is structurally unreachable.** q23's two statements are
identical above their final SELECT, so the three CTEs are computed twice by
construction. Only materialising them once reaches that, and temporary tables
are not permitted in this project. A first attempt used them
(`CREATE TEMPORARY TABLE` for each CTE, indexed) and was removed for that
reason.

**The remaining cost is the CTEs themselves**, not how they are referenced:

- `frequent_ss_items` groups four years of `store_sales` joined to `item`
- `max_store_sales` aggregates four years by customer
- `best_ss_customer` aggregates **all** of `store_sales` — no date filter at
  all, unlike the other two

That last asymmetry looks like the obvious target, but adding a date filter
there would change the answer: the 95th-percentile threshold it compares
against is computed over four years, while the customer totals it ranks are
computed over all time. Narrowing one and not the other changes which
customers qualify.

## A caveat on correctness

**q23 returns nothing at SF=4**: statement 1 yields `sum(sales) = NULL`,
statement 2 yields zero rows. The 173.6s produces an empty result.

So "output identical" is weak evidence here — the same trap as q54 and q8. A
rewrite that wrongly dropped rows would look identical too. The `DISTINCT`
and uniqueness arguments above are checkable by inspection, which is firmer
ground than the comparison, but this is not the byte-for-byte verification
the other optimized queries have.

It also caused a false result: an earlier version of v1 had an ambiguous
`c_customer_sk` in statement 2 (`ERROR 1052` — both `best_ss_customer` and
`customer` expose it). Statement 2 never parsed, statement 1 returned `NULL`,
the original also returns nothing from statement 2, and the comparison
reported IDENTICAL. Only the exit code revealed it.

## Recommendation

Leave q23 on the original query. Neither rewrite is worth adopting on this
evidence, and both add complexity.

Worth trying, in order:

1. **Substitution parameters that return rows.** `d_year in (1999..2002)`
   with `d_moy = 7` is too selective against this data. Optimizing a query
   whose result is empty is measuring the wrong thing.
2. **Re-measure on Linux.** `./reproduce.sh full` — this host cannot resolve
   a 15% effect on a query with 15–47% variance, and `O_DIRECT` does not work
   here.
3. **Revisit if temporary tables are ever permitted.** The structural
   duplication between the two statements is the single largest lever and
   nothing else reaches it.

## Files

| file | |
|---|---|
| `query23_v1_joins.sql` | `IN` → joins |
| `query23_v2_unionfirst.sql` | union first, join the shared sets once |
| `analyze.sh` | the `ANALYZE FORMAT=JSON` breakdown above |
| `test.sh` | times variants against the original and diffs output |
