# query 87 — 145.224s → 55.183s (2.63x, SF=4)

Original: [`queries/mariadb/query87.sql`](../../mariadb/query87.sql).
[`query87_v0.sql`](query87_v0.sql) remains an exact copy.
The selected SQL is [`query87_BEST.sql`](query87_BEST.sql), renamed from
`query87_v2_single_except.sql` without changing its contents.
Both returned exactly **`184693`**, with the same `count(*)` column label.

| File | Recorded time | Change / decision |
|---|---:|---|
| [`query87_v0.sql`](query87_v0.sql) | 145.224s | Original, final comparison control |
| [`query87_v1_except_distinct.sql`](query87_v1_except_distinct.sql) | Not separately timed | Still an unchanged baseline copy, including its branch DISTINCT clauses |
| **[`query87_BEST.sql`](query87_BEST.sql)** | **55.183s** | Deduplicate customer/date pairs before dimension joins, then retain native EXCEPT |

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

Count distinct **(last name, first name, date)** combinations present in
store sales and absent from both catalog and web sales during month sequences
**1176–1187**:

```text
store name/date keys EXCEPT catalog name/date keys EXCEPT web name/date keys
```

This is not a count of transactions or customer surrogate keys. Different
customer keys with identical names can match across channels on the same date.
NULL names must retain the original set-operation matching behavior.

## Steps and why they help

1. Push scalar min/max date-key bounds into each fact scan. Retain the exact
   month filter and date-dimension inner join later, so bounds do not admit
   out-of-period or orphan dates into the final set.
2. Build `store_visits`, `catalog_visits` and `web_visits` by grouping each
   channel on **sold-date key + customer key**. Repeated line items for the
   same customer/day become one pair before the customer-name lookup.
   Use `ss_customer_sk`, `cs_bill_customer_sk` and `ws_bill_customer_sk`,
   matching the original customer roles.
3. Discard NULL customer keys before grouping: they could not survive the
   original customer inner join. Keep NULL first/last names in matching
   customer rows.
4. Use `SELECT STRAIGHT_JOIN` for each branch to read its grouped visits,
   then look up date and customer by primary key. The final plan has grouped
   fact materializations followed by those dimension lookups. Narrow key
   grouping reduces repeated joins and sends fewer name/date tuples into the
   final set operations; no runtime row-count reduction was separately saved.
5. Keep the two native `EXCEPT` operators on the **projected names and date**.
   They still remove duplicates, including different surrogate customers with
   identical names. The early grouping is an optimization, not a replacement
   for the original set key. Branch-level DISTINCT is consequently unnecessary.

## Rejected alternative

An earlier rewrite used `store EXCEPT (catalog UNION ALL web)`. It added a
combined right-hand materialization. In one bounded check, **both original and
candidate exceeded 120 seconds**; neither returned a result, so this was not
a correctness pass or a speedup. That intermediate was edited in place and
is not a retained SQL file.

The selected version uses the flat EXCEPT chain with early customer/date
preaggregation. Despite the former filename `v2_single_except`, the selected
SQL contains **two** EXCEPT operators. This is one single-statement query with
CTEs; it creates no permanent tables or indexes.

## Correctness

The final SF=4 comparison matched the full scalar result, including its column
label: **184,693 in both versions**. The original completed within a 300-second
cap; the selected query completed within a 180-second cap. Neither final timing
is a timeout value.

A separate temporary-table fixture compared both the count **and the actual
four remaining name/date members**, preserving NULLs and duplicates. It tested
repeated sales, different customer keys with identical names, NULL names,
exclusions through either channel, different dates, period endpoints,
out-of-period keys inside the numeric bounds and missing dimension keys.
The fixture passed and was executed in memory, not saved as a fixture file.

The full SF=4 member set was not separately compared or saved; the full-scale
check compared the scalar answer, while the fixture checked membership.
The three fact-table scans remain, explaining why the selected SQL can still
take tens of seconds on this laptop without additional indexes.

## Reproduce

From the repository root, with the SF=4/seed=10 database already loaded:

```bash
python3 scripts/sf4.py compare \
  --database tpcds_sf4_seed10 \
  --baseline queries/optimized/q87/query87_v0.sql \
  --optimized queries/optimized/q87/query87_BEST.sql \
  --repeats 3 --timeout 300 \
  --out experiments/local/q87_best_sf4.csv
```

This command runs new alternating comparisons and saves their timings; it
does not reproduce a controlled cold-cache state. It requires the existing
`scripts/sf4.py` helper and MariaDB client on `PATH`.
