# Corrections needed in the optimized queries

Found while wiring the team's optimized queries into `queries/tuned/` and
verifying each one against the adapted TPC-DS original at SF=4.

**The files under `queries/optimized/` are unchanged.** Every correction below
is applied on the way out by `queries/build-tuned.py`, so the originals stay
as their authors wrote them. Please fold these back into your own copies.

Verified by running both versions and comparing output byte for byte.

---

## q14 (Aysha) — two issues, part B

### 1. A typo means part B has never executed

`Query-14-B/Q14-B-Optimized.sql`, line 16:

```sql
select item.i_braknd_id,     -- should be i_brand_id
```

Transposed letters. MariaDB rejects it outright:

```
ERROR 1054 (42S22): Unknown column 'item.i_braknd_id' in 'SELECT'
```

So part B has produced no result in any run we have made. Part A is fine.

### 2. Part B returns 8 columns; TPC-DS requires 12

The query emits:

```
channel, brand_id, class_id, category_id,
this_year_sales, this_year_number_of_sales,
last_year_sales, last_year_number_of_sales
```

TPC-DS q14 part B requires the `ty_`/`ly_` pairs, repeating the four key
columns once per year:

```
ty_channel, ty_brand, ty_class, ty_category, ty_sales, ty_number_sales,
ly_channel, ly_brand, ly_class, ly_category, ly_sales, ly_number_sales
```

The information is the same — the join forces `ty_channel = ly_channel` and so
on, which we confirmed against the original's own output, every row — but the
shape differs, so the result does not match the answer set.

**Fix:** emit the four key columns twice with the `ty_`/`ly_` aliases. The
expansion is in `build-tuned.py`.

### 3. The ORDER BY has to be renamed with them

Part B ends:

```sql
order by brand_id, class_id, category_id
```

Those are the aliases the expansion renames, so after fix 2 the clause refers
to columns that no longer exist and part B fails. It becomes:

```sql
order by ty_brand, ty_class, ty_category
```

We hit this ourselves: our first attempt at fix 2 left the ORDER BY alone,
part B errored, and the run returned part A's 100 rows instead of 201 — it
looked like a wrong row count rather than an error. Worth knowing if you
apply the expansion by hand.

(The original also orders by `channel` first. Part B is store-only, so
channel is constant and omitting it changes nothing.)

**Worth it:** part A already matched the original exactly and is much faster.
Part B's timing is still being verified — the 19.9s we measured earlier was
taken while part B was erroring, so it only timed part A and is not a valid
figure for the pair.

---

## q47 (Aysha) — select list transposed

`q47_Optimized_3secs.sql` ends:

```sql
SELECT *
FROM v1
```

and its `v1` CTE declares `sum_sales` before `avg_monthly_sales`. TPC-DS
requires the opposite order, so columns 7 and 8 come out swapped. Same 100
rows, same values, wrong positions — which fails a strict comparison.

**Fix:** name the columns instead of `SELECT *`:

```sql
SELECT i_category, i_brand, s_store_name, s_company_name,
       d_year, d_moy, avg_monthly_sales, sum_sales, psum, nsum
FROM v1
```

`SELECT *` over a CTE is worth avoiding generally here: the column order
becomes whatever the CTE happens to declare.

### Also: it forces an index that has no CREATE anywhere

```sql
store_sales FORCE INDEX (idx_ss_date_item_store_cover)
```

No `CREATE INDEX` for that name exists in the repository. We inferred it as

```sql
CREATE INDEX idx_ss_date_item_store_cover
  ON store_sales (ss_sold_date_sk, ss_item_sk, ss_store_sk, ss_sales_price);
```

and it is now in `sql/14_contributed_indexes.sql`. If your actual definition
differs, q47's timings move — please add the real DDL to the folder.

---

## q43 (Aysha) — DDL inside the query file

`q43_Optimized.sql` contains, alongside the query:

```sql
create index idx_date_year_sk_day on date_dim (...);
create index idx_ss_date_store_price on store_sales (...);
analyze table date_dim, store_sales;
```

Run as one file, `ANALYZE TABLE` prints its own result set
(`Table | Op | Msg_type | Msg_text`) into the output, so the query appears to
return 23 rows instead of 20.

**Fix:** keep DDL in a separate file from the query. The indexes are already
in `sql/14_contributed_indexes.sql`.

---

## q97 (Aysha) — not a defect, our harness was wrong

`query97_BEST.sql` creates `ssci_t` and `csci_t` as temporary tables and then
uses them. We previously reported it as broken with

```
ERROR 1146 (42S02): Table 'tpcds.ssci_t' doesn't exist
```

That was **our** fault: the old runner split files on `;` and ran each
statement in a separate connection, so the temp tables vanished between
statements. Fed whole, the query is fine. Apologies for the misreport.

---

## q35 and q38 (Aysha) — index-only, no query to substitute

Both `q35_Optimized.sql` and `q38_Optimized.sql` contain only `CREATE INDEX`
statements and no query, so there is nothing to run in place of the original.
Their indexes are in `sql/14_contributed_indexes.sql`. If a rewritten query
exists for either, it has not been committed.

---

## Not a correction: q4 (riccio)

We briefly recorded `query4_BEST.sql` as failing. That was a bug in our
generator, not the query: it split SQL on `;` before stripping comments, and
the file opens with

```sql
-- Requires unique customer.c_customer_id; validate that assumption separately.
```

The semicolon inside that comment split it, leaving stray text ahead of the
query. Fixed on our side. The query is sound.

---

## How to check your own changes

```bash
queries/verify-tuned.sh 14 43 47      # runs original and tuned, diffs output
```

It reports `IDENTICAL`, `row order only` (where the `ORDER BY` is not a total
order, as in q65 and q71), or `DIFFERS` with the row counts.

Two things worth knowing when you re-check:

- **`PIPES_AS_CONCAT` is required.** TPC-DS concatenates with ANSI `||` in q5,
  q66, q80 and q84. Without that sql_mode MariaDB reads `||` as logical OR,
  and q5 returns **7 rows instead of 100** with no error.
- **Column order and column names are part of the answer.** Several
  differences we chased turned out to be renamed or reordered columns rather
  than changed data.
