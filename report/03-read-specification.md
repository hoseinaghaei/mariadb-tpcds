# Step 3 — Read the specification and identify the schema

## The specification folder

```
DSGen-software-code-4.0.0/specification/
└── specification_4.0.0.pdf      3.0 MB, 146 pages
```

Extracted to text for systematic reading:

```sh
pdftotext -layout specification/specification_4.0.0.pdf spec.txt
```

## Which schema to build

**Clause 2 — Logical Database Design** defines it. Clause 2.1:

> The TPC-DS schema models the sales and sales returns process for an
> organization that employs three primary sales channels: stores, catalogs,
> and the Internet. The schema includes seven fact tables: [...] In addition,
> the schema includes 17 dimension tables that are associated with all sales
> channels.

So: **7 fact + 17 dimension = 24 tables**, defined column-by-column in
Clause 2.3 (facts, Tables 2-1 … 2-7) and Clause 2.4 (dimensions, Tables
2-8 … 2-24).

Table 2-25 adds `dsdgen_version`, described as:

> This table is not employed during the benchmark. [...] it can be helpful in
> assuring that the current data set was built with the correct version of the
> TPC-DS toolkit. It is included here for completeness.

That is the 25th table and the 25th `.dat` file. It is included in the build
(named `dbgen_version`, matching the toolkit's DDL and the generated
`dbgen_version.dat`) but it carries no benchmark meaning.

### The seven fact tables

`store_sales`, `store_returns`, `catalog_sales`, `catalog_returns`,
`web_sales`, `web_returns`, `inventory`

A sales/returns pair per channel, plus one inventory fact for the catalog and
web channels.

### The seventeen dimension tables

`date_dim`, `time_dim`, `customer`, `customer_address`,
`customer_demographics`, `household_demographics`, `income_band`, `item`,
`store`, `call_center`, `catalog_page`, `web_site`, `web_page`, `warehouse`,
`promotion`, `reason`, `ship_mode`

This is a snowflaked star: fact tables carry surrogate-key foreign keys into
the dimensions, and a few dimensions reference others (`customer` →
`customer_address`, `customer_demographics`, `household_demographics`,
`date_dim`).

## Rules that constrain the MariaDB implementation

### Clause 2.2.2 — Datatypes

The specification defines its own abstract types, explicitly not SQL types
(2.2.2.2: *"The datatypes do not correspond to any specific SQL-standard
datatype"*):

| Spec type | Requirement |
|---|---|
| `identifier` | must hold any key value generated for that column |
| `integer` | exact integers over at least −2⁶³ … 2⁶³−1 (**n is 64**) |
| `decimal(d,f)` | up to `d` digits, `f` to the right of the point |
| `char(N)` | fixed-length string of N characters |
| `varchar(N)` | variable length, max N; may be implemented as `char(N)` |
| `date` | any day from 1900-01-01 to 2199-12-31 |

Two clauses shape the mapping:

- **2.2.2.1(b)** — `integer` needs a **64-bit** range. Not 32-bit.
- **2.2.2.3** — the chosen SQL type must be applied consistently to every
  instance of a spec type, *"except for identifier columns, whose datatype may
  be selected to satisfy database scaling requirements."*

### Clause 2.2.3 — NULLs

> If a column definition includes an 'N' in the NULLs column this column is
> populated in every row of the table for all scale factors. If the field is
> blank this column may contain NULLs.

### Clause 2.5.2 — Tables and columns

- **2.5.2.7** each table shall be implemented according to the column
  definitions given
- **2.5.2.8** column names shall match those defined in Clauses 2.3 and 2.4
- **2.5.2.9** columns may be in any order, but all shall be implemented and
  **no columns may be added**
- **2.5.2.10** columns shall not be merged or split

### Clause 2.5.4 — Constraints

- **2.5.1.8** *"The definition of primary and foreign keys is optional."*
- **2.5.4.1** constraints *"are limited to primary key, foreign key, and NOT
  NULL constraints"* — so no `CHECK` constraints
- **2.5.4.1** `NOT NULL` is allowed **only** on columns marked `N`
- **2.5.4.2** any FK delete/update action is acceptable

### Clause 2.5.3 — Auxiliary data structures

Indexes and materialized views beyond the base tables are tightly restricted.
Nothing beyond primary keys and the optional foreign-key indexes was created,
so this clause is not engaged.

## Machine-readable extraction

Reading 146 pages by eye is not a basis for a 429-column schema, so the
Clause 2.3/2.4 tables were parsed out of the extracted text into JSON —
column name, datatype, NOT NULL flag, primary-key flag and key ordinal — and
every later step was generated and checked against that structure.

```
25 tables parsed from spec
  store_sales                 23 cols     store                       29 cols
  store_returns               20 cols     call_center                 31 cols
  catalog_sales               34 cols     catalog_page                 9 cols
  catalog_returns             27 cols     web_site                    26 cols
  web_sales                   34 cols     web_page                    14 cols
  web_returns                 24 cols     warehouse                   14 cols
  inventory                    4 cols     customer                    18 cols
  customer_address            13 cols     item                        22 cols
  customer_demographics        9 cols     income_band                  3 cols
  date_dim                    28 cols     promotion                   19 cols
  household_demographics       5 cols     reason                       3 cols
  time_dim                    10 cols     ship_mode                    6 cols
  dbgen_version                4 cols
                                          total: 429 columns
```

This parse became the authoritative input for the DDL and for three
independent cross-checks in [step 4](04-reconcile-discrepancies.md).
