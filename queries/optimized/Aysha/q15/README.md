# TPC-DS Query 15: Optimization Notes (MariaDB)

Query 15 rewritten as two non-overlapping branches with their own join order and
indexes. The goal is a query that keeps scaling well as the data grows.

## Files

| File | What it is |
|---|---|
| `q15_optimized.sql` | Two-branch rewrite with `STRAIGHT_JOIN`, plus the index DDL as comments |

## Results

| Version | Time | Speedup vs original |
|---|---|---|
| Original query | 0.15 s | 1.0x |
| Original query + indexes | 0.10 s | ~1.5x |
| New two-branch query + indexes | 0.064 s | ~2.3x |

The absolute times are tiny on this data size. The rewrite is aimed at much larger
data, which has not been measured yet (see Open items).

## What the query does

For catalog sales in Q1 2001, find the buyer's current ZIP code and add up the sales
price per ZIP. A sale counts if any of these is true:

- the buyer's ZIP (first 5 characters) is one of 9 listed ZIPs,
- the buyer's state is CA, WA or GA,
- the sale price is over 500.

The result is the first 100 ZIPs in order, each with its total.

## Original query

```sql
select ca_zip, sum(cs_sales_price)
from catalog_sales, customer, customer_address, date_dim
where cs_bill_customer_sk = c_customer_sk
  and c_current_addr_sk = ca_address_sk
  and ( substr(ca_zip,1,5) in ('85669','86197','88274','83405','86475',
                               '85392','85460','80348','81792')
        or ca_state in ('CA','WA','GA')
        or cs_sales_price > 500)
  and cs_sold_date_sk = d_date_sk
  and d_qoy = 1 and d_year = 2001
group by ca_zip
order by ca_zip
limit 100;
```

Original plan: `date_dim` -> `catalog_sales` (`idx_cs_date_cust`) -> `customer` (PK)
-> `customer_address` (PK).

## Why the original is costly at scale

- Every Q1 2001 sale pays for an index read of `catalog_sales` plus two
  primary-key lookups (`customer`, `customer_address`).
- The `OR` filter runs only after all four tables are joined, because its conditions
  are split across two tables (`customer_address` and `catalog_sales`). No table can
  be filtered early, so rows that fail the `OR` are discarded after all the lookups
  have been paid for.
- Cost grows with the number of Q1 2001 sales.

## The rewrite

The `OR` is split into two branches that never overlap:

| Branch | Rows it takes | Join order |
|---|---|---|
| 1 | Address conditions true (any price) | `customer_address` (filtered) -> `customer` -> `catalog_sales` |
| 2 | Price over 500 and address conditions not true | `catalog_sales` (price index) -> `customer` -> `customer_address` |

Each branch is grouped by ZIP, combined with `UNION ALL`, then grouped, sorted and
limited again.

```
Branch 1                              Branch 2
customer_address (zip/state filter)   catalog_sales (price > 500, Q1 dates)
        |                                     |
customer (index on address)           customer (PK lookup)
        |                                     |
catalog_sales (customer, date range)  customer_address (PK, keep if A not true)
        |                                     |
GROUP BY ca_zip, SUM                  GROUP BY ca_zip, SUM
              \                         /
                    UNION ALL
                        |
          GROUP BY ca_zip, ORDER BY, LIMIT 100
```

### Design choices

- **`UNION ALL`, not `UNION`.** The branches never share a sale row, so there is
  nothing to remove. `UNION` would also risk merging two equal `(ca_zip, subtotal)`
  rows from different branches, which gives a wrong total.
- **`is not true` in branch 2.** A plain `not (...)` would drop rows where `ca_zip`
  or `ca_state` is NULL, but the original keeps them when the price is over 500.
- **Date filter as a key range.** The `date_dim` join becomes a
  `cs_sold_date_sk between min and max` range on the quarter's date keys, so each
  customer probe stays inside the Q1 slice of the index.
- **`STRAIGHT_JOIN` in each branch** fixes the join order so the plan cannot flip as
  table statistics change.

## Indexes

```sql
-- Branch 1: customers by address, then their Q1 sales (price included, no table fetch)
create index idx_cs_cust_date_price on catalog_sales (cs_bill_customer_sk, cs_sold_date_sk, cs_sales_price);
create index idx_c_addr on customer (c_current_addr_sk);

-- Branch 2: jump straight to sales over 500
create index idx_cs_price_date_cust on catalog_sales (cs_sales_price, cs_sold_date_sk, cs_bill_customer_sk);
```

Which step each one helps:

| Index | Step it helps |
|---|---|
| `idx_cs_cust_date_price` | Branch 1: reads each customer's Q1 sales from the index only |
| `idx_c_addr` | Branch 1: finds customers by address |
| `idx_cs_price_date_cust` | Branch 2: first step, seeks straight to sales over 500 |

## Why the results are identical

- Every row the original keeps has the address conditions true or the price over 500.
  Branch 1 takes the first case, branch 2 takes the second case when the first is not
  true. Together they cover exactly the original rows, with no overlap.
- Joins and the Q1 2001 filter are unchanged.
- Subtotals per ZIP are summed again in the outer query, which gives the same total
  as one `SUM` over all rows.

## Checks to run

1. **Contiguous Q1 date keys** (`max - min + 1` must equal `count`):
   ```sql
   select min(d_date_sk), max(d_date_sk), count(*) from date_dim where d_year = 2001 and d_qoy = 1;
   ```
2. **Same results**: run both queries and compare the outputs with `diff`.
3. **How selective the address conditions are** (branch 1 helps most when this is a
   small share of `select count(*) from customer_address`):
   ```sql
   select count(*) from customer_address
   where substr(ca_zip,1,5) in ('85669','86197','88274','83405','86475','85392','85460','80348','81792')
      or ca_state in ('CA','WA','GA');
   ```
4. **How many sales are over 500** (if very few, branch 2 costs almost nothing):
   ```sql
   select count(*) from catalog_sales where cs_sales_price > 500;
   ```
5. **Plan check**: branch 1 should start at `customer_address`, use `idx_c_addr` on
   `customer`, and read `catalog_sales` as `range` + `Using index`. Branch 2 should
   start at `catalog_sales` via `idx_cs_price_date_cust`.

## Open items

- Not yet measured at larger data sizes, which is the real target.
- `EXPLAIN` output for the new query has not been reviewed yet.
- Results have not been compared against the original with `diff` yet.
- If most sales are over 500, put the date key first in `idx_cs_price_date_cust`
  instead: `(cs_sold_date_sk, cs_sales_price, cs_bill_customer_sk)`.