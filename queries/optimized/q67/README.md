# Q67 follow-up: join order and aggregation pushdown

The adopted version remains
[`queries/tuned/query67.sql`](../../tuned/query67.sql), sourced from Aysha's v2.
Neither candidate in this directory has been adopted. Full measurements,
correctness reasoning and runtime observations are in
[`report/27-query-followup.md`](../../../report/27-query-followup.md).

| File | Hypothesis | Local SF=1 result, three alternating rounds |
|---|---|---|
| [v3](query67_v3_datefirst.sql) | Filter dates before accessing the fact table | 13.351s median vs adopted 11.593s; slower in every round |
| [v4](query67_v4_preaggregate.sql) | Aggregate on narrow item/store/month keys before joining descriptions | 11.240s median; only 1.03x, with overlapping ranges and no consistent win |

Both preserve the full descriptive ROLLUP and ranking. Pre-aggregation does
not authorize grouping the final answer by surrogate keys: different items
or stores can have identical descriptions, and their measures must still
merge at the original grouping levels. NULL measures retain the original
`COALESCE(price * quantity, 0)` handling.

All measured candidates matched the adopted query's complete 100-row answer.
A SELECT-only fixture also matched all 31 original rows with duplicate
descriptions, NULL grouping values, tied and negative amounts, orphan keys
and irregular date keys. The explicit month predicate remains in each
candidate, so key bounds do not replace the logical date condition.

These trials used MariaDB 10.11.14, SF=1 seed 10, 16K pages, a 2 GiB pool
and 117 secondary indexes. All versions used the same query-local 64 MiB
sort buffer and 256 MiB temporary-table/heap limits. The timing runner's
context is collected before query-local SET statements; the archived SQL
records those overrides. No DDL or global configuration changes were made.

The saved runtime plans show four disk temporary tables and 499,780 ROLLUP
rows in both the adopted query and v4. The additional aggregation reduces
some join/grouping input but does not remove that downstream workload. Keep
the adopted version and investigate the ROLLUP/window costs on the reference
machine before choosing another rewrite.
