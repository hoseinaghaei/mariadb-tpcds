# Step 4 — Reconcile the specification against the toolkit's own DDL

The toolkit ships reference DDL in `tools/tpcds.sql` (25 `create table`
statements) and referential integrity in `tools/tpcds_ri.sql` (109
constraints). Neither is fully consistent with `specification_4.0.0.pdf`.
Both were parsed and compared against the specification before anything was
written for MariaDB.

## Check 1 — specification vs. `tpcds.sql`

Compared table set, column names, column order, datatypes, nullability and
primary keys across all 25 tables and 429 columns.

**Agreement:** table set, column order, all datatypes, all 24 primary keys.

**Three disagreements:**

### 4.1 `customer.c_last_review_date_sk` — resolved in favour of the specification

| Source | Says |
|---|---|
| Specification, Table 2-14 | `c_last_review_date_sk`, `identifier`, FK → `d_date_sk` |
| `tools/tpcds.sql` | `c_last_review_date`, `char(10)` |
| `tools/tpcds_ri.sql` | `c_last_review_date_sk` → `date_dim(d_date_sk)` |
| `query_templates/query30.tpl` | `c_last_review_date_sk` |

`tpcds.sql` is the outlier — the toolkit's own RI script and query set both use
the `_sk` name. The generated data settles it. Column 18 of `customer.dat`:

```
2452508
2452318
2452313
```

Those are `d_date_sk` surrogate keys, not `char(10)` date strings.

**Decision: `c_last_review_date_sk BIGINT`.** This is not cosmetic — taking
`tpcds.sql` at face value would have made query 30 fail to compile and the
foreign key to `date_dim` impossible to declare.

### 4.2 `store.s_tax_percentage` — resolved in favour of the specification

`tpcds.sql` spells it `s_tax_precentage` (transposed letters). The
specification, Table 2-8, spells it `s_tax_percentage`. No query template
references the column either way, so nothing depends on the choice.

**Decision: `s_tax_percentage`,** per Clause 2.5.2.8 (column names shall match
Clause 2.3/2.4). If a downstream tool expects the toolkit's spelling:

```sql
ALTER TABLE store CHANGE s_tax_percentage s_tax_precentage DECIMAL(5,2);
```

### 4.3 `dbgen_version` nullability — resolved in favour of the specification

Table 2-25 marks all four columns `N` (NOT NULL); `tpcds.sql` leaves them
nullable. The specification was followed. The table holds one row and is not
used by the benchmark.

### Not a discrepancy

An earlier run of the comparison flagged `catalog_page.cp_catalog_number` and
`cp_catalog_page_number` as missing from the specification. That was a defect
in the text parser — the PDF prints those two rows as `integer,` with a
trailing comma, which the datatype pattern did not match. Both columns are in
the specification. Parser fixed; they agree.

## Check 2 — specification vs. the generated data

Independent confirmation that the parsed schema describes the actual files:
for each of the 25 `.dat` files, the pipe-delimited field count was compared
to the specified column count (accounting for dsdgen's trailing `|`).

```
All 25 tables: generated .dat field count == spec column count.
```

## Check 3 — `tpcds_ri.sql` structural validation

Every one of the 109 foreign keys was checked: does the child column exist?
does the parent column exist? is the parent column set the parent's primary
key?

### Two constraints name columns that do not exist

```
cp_p    catalog_page(cp_promo_id)         -> promotion(p_promo_sk)
cr_d2   catalog_returns(cr_ship_date_sk)  -> date_dim(d_date_sk)
```

`catalog_page` has no `cp_promo_id` and `catalog_returns` has no
`cr_ship_date_sk` — not in the specification, not in `tpcds.sql`, not in the
generated data. Both are dead references.

**Decision: dropped.** They cannot be created against a correct schema.

### Three constraint names are used twice within one table

MariaDB requires foreign-key constraint names to be unique, so these would
fail:

| Table | Name | Two uses |
|---|---|---|
| `catalog_returns` | `cr_i` | `cr_item_sk`→`item`, `cr_returned_time_sk`→`time_dim` |
| `web_returns` | `wr_ret_cd` | `wr_returning_cdemo_sk`→`customer_demographics`, `wr_returning_hdemo_sk`→`household_demographics` |
| `web_sales` | `ws_b_cd` | `ws_bill_cdemo_sk`→`customer_demographics`, `ws_bill_hdemo_sk`→`household_demographics` |

**Decision: second use of each suffixed `_2`** (`cr_i_2`, `wr_ret_cd_2`,
`ws_b_cd_2`). Constraint names carry no benchmark meaning.

### Result

109 − 2 invalid = **107 foreign keys**, 3 renamed. All 107 verified to
reference a genuine primary key on the parent table.

## Summary

| Finding | Source of truth | Action |
|---|---|---|
| `c_last_review_date` vs `_sk` | spec + RI + query30 + data | use `c_last_review_date_sk BIGINT` |
| `s_tax_precentage` typo | spec, Clause 2.5.2.8 | use `s_tax_percentage` |
| `dbgen_version` nullability | spec Table 2-25 | apply NOT NULL |
| `cp_p`, `cr_d2` phantom columns | spec + data | drop both constraints |
| 3 duplicate constraint names | MariaDB requirement | suffix `_2` |

**The specification was treated as authoritative throughout; `tpcds.sql` and
`tpcds_ri.sql` were treated as convenience scripts that have drifted from it.**
