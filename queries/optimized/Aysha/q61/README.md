# TPC-DS Query 61 optimization

Promo share of December 2000 Books sales (stores and customers at GMT-7). Scale factor 1, MariaDB. No schema changes, only indexes and a query rewrite.

## Results

| Version | What changed | Time |
|---|---|---|
| Original | nothing | 1.42 s |
| v1 | same sql + 5 new indexes | 0.4-0.8 s |
| v2 | indexes + rewritten query | 0.001 s |

v1 timing varies between runs (cache effects). The original time comes from its first `analyze format=json` plan.

## Step 1: indexes

```sql
-- fact table: join keys first, then every column the query reads (covering)
create index idx_ss_q61 on store_sales
  (ss_store_sk, ss_sold_date_sk, ss_item_sk, ss_customer_sk, ss_promo_sk, ss_ext_sales_price);

-- dimensions: make the filters index-driven
create index idx_store_gmt on store (s_gmt_offset);
create index idx_date_ym   on date_dim (d_year, d_moy, d_date_sk);
create index idx_item_cat  on item (i_category);
create index idx_ca_gmt    on customer_address (ca_gmt_offset);
```

- Optimizer now starts at `store` instead of scanning `store_sales`.
- Every lookup is index-only, with no row fetches.

## Step 2: query rewrite (v2)

```sql
select promotions, total,
       cast(promotions as decimal(15,4)) / cast(total as decimal(15,4)) * 100
from (
  select straight_join
    sum(case when p.p_channel_dmail = 'Y' or p.p_channel_email = 'Y' or p.p_channel_tv = 'Y'
             then ss.ss_ext_sales_price end) as promotions,
    sum(ss.ss_ext_sales_price) as total
  from store s
  join date_dim d          on d.d_year = 2000 and d.d_moy = 12
  join store_sales ss      on ss.ss_store_sk = s.s_store_sk
                          and ss.ss_sold_date_sk = d.d_date_sk
  join item i              on i.i_item_sk = ss.ss_item_sk
  join customer c          on c.c_customer_sk = ss.ss_customer_sk
  join customer_address ca on ca.ca_address_sk = c.c_current_addr_sk
  left join promotion p    on p.p_promo_sk = ss.ss_promo_sk
  where s.s_gmt_offset = -7
    and i.i_category = 'Books'
    and ca.ca_gmt_offset = -7
) x;
```

## What changed

- `store_sales` is read once, not twice.
- Both sums come from the same rows, so there are no derived tables and no join between them.
- Join order is forced: `store` -> `date_dim` -> `store_sales` -> rest (`straight_join`).
- `store_sales` is probed by store and day together, using both columns of the index.
- `left join promotion` keeps sales with no promotion, so `total` counts every sale.
- `case when` counts a sale in `promotions` only for the right channels.
- `order by` and `limit 100` removed (the result is one row).

## Caveat

No store has `s_gmt_offset = -7` in this data, so the query exits at `store` and returns `null`. The 0.001 s proves the join order, not the speed with real rows. Retest with an offset that exists in both `store` and `customer_address` (check with `select s_gmt_offset, count(*) from store group by 1`).

## Undo

```sql
drop index idx_ss_q61    on store_sales;
drop index idx_store_gmt on store;
drop index idx_date_ym   on date_dim;
drop index idx_item_cat  on item;
drop index idx_ca_gmt    on customer_address;
```