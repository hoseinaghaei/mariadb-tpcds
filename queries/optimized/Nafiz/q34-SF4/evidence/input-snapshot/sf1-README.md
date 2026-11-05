# Query 34 optimization

## Versions

- `v0_original`: untouched TPC-DS query.
- `v1_range_simplified`: the exact date-key range and logically equivalent simplified predicates without the hint.

## What changed

The original repeatedly lists `Williamson County` and expresses the two household buying-potential values with `OR`. The optimized version replaces these with one equality and `IN (...)`, preserving the same meaning. It also adds the exact 1998-2000 `ss_sold_date_sk` range (2450815–2451910), allowing the existing date index to filter earlier.

## Verification

All saved versions returned byte-identical output. A five-run comparison measured the original at about 852ms on average and v1 at about 746ms on average. A date-first hinted experiment was slower and was removed, because only faster versions are retained. The runner writes the current CSV, HTML report, `.out` files, and `BEST` selection.
