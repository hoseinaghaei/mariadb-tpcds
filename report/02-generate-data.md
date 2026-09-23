# Step 2 — Generate the scale-factor-1 data set

## Command

```sh
cd DSGen-software-code-4.0.0/tools
mkdir -p ../data
./dsdgen -SCALE 1 -DIR ../data -FORCE
```

```
dsdgen Population Generator (Version 4.0.0)
Copyright Transaction Processing Performance Council (TPC) 2001 - 2021
Warning: This scale factor is valid for QUALIFICATION ONLY
```

Plain `dsdgen -SCALE 1` works identically but writes into the current
directory; `-DIR ../data` keeps the 1.2 GB of output out of `tools/`.
`-FORCE` overwrites existing `.dat` files without prompting.

The qualification warning is expected and correct. SF=1 is the qualification
size defined by the specification for validating an implementation against the
published answer sets; it is not a publishable benchmark scale. It is the right
size for this work.

## Output

25 files, 1.2 GB total, in `DSGen-software-code-4.0.0/data/`.

| Table | Rows | Size |
|---|---:|---:|
| inventory | 11,745,000 | 225 MB |
| store_sales | 2,880,404 | 370 MB |
| customer_demographics | 1,920,800 | 77 MB |
| catalog_sales | 1,441,548 | 282 MB |
| web_sales | 719,384 | 140 MB |
| store_returns | 287,514 | 31 MB |
| catalog_returns | 144,067 | 20 MB |
| customer | 100,000 | 13 MB |
| time_dim | 86,400 | |
| date_dim | 73,049 | 9.8 MB |
| web_returns | 71,763 | 9.4 MB |
| customer_address | 50,000 | |
| item | 18,000 | |
| catalog_page | 11,718 | |
| household_demographics | 7,200 | |
| promotion | 300 | |
| reason | 75 | |
| web_page | 60 | |
| web_site | 30 | |
| income_band | 20 | |
| ship_mode | 20 | |
| store | 12 | |
| call_center | 6 | |
| warehouse | 5 | |
| dbgen_version | 1 | |

## Validation

Row counts were checked against the TPC-DS SF=1 reference cardinalities:

| Table | Expected | Generated |
|---|---:|---:|
| store_sales | 2,880,404 | 2,880,404 ✓ |
| customer | 100,000 | 100,000 ✓ |
| item | 18,000 | 18,000 ✓ |
| date_dim | 73,049 | 73,049 ✓ |

Field counts were checked against the specification for **all 25 tables** —
every file's pipe-delimited field count equals its specified column count. See
[step 4](04-reconcile-discrepancies.md) for how that check was built.

## File format (needed for loading later)

- Pipe (`|`) delimited, one row per line, **with a trailing `|`** at the end of
  every line. A naive split therefore yields one extra empty field.
- Empty field = SQL NULL. `LOAD DATA` maps an empty string to `0` for numeric
  columns and `0000-00-00` for dates, so a loader must route nullable columns
  through `@vars` and `NULLIF(@v,'')`.
- **UTF-8 encoded.** `customer.dat` contains 910 lines with multi-byte
  characters (`c3 89` = É, `c3 94` = Ô) in the name columns. This is what
  determined the database character set — see
  [step 5](05-mariadb-design.md).

Sample (`item.dat`, truncated):

```
1|AAAAAAAABAAAAAAA|1997-10-27||Powers will not get influences...|27.02|23.23|...
```
