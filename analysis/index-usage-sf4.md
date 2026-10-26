# Index usefulness at SF=4

Counters zeroed, then the 40 tier-4/5 queries in `queries/tuned/` run once. `UNUSED` means **not read by those 40 queries at this scale under this configuration** — it is not a property of the index.

| | indexes | disk |
|---|---:|---:|
| read at least once | 55 | 16,165 MB |
| enabled but never read | 135 | **16,914 MB** |
| currently IGNORED | 1 | 512 MB |
| total | 191 | 33,591 MB |

The IGNORED ones are listed separately because they **cannot** be read — the optimizer is not allowed to use them — so a zero read count says nothing about whether they are worth keeping. Counting them as dead weight would be circular.

| table | index | MB |
|---|---|---:|
| store_sales | `idx_ss_date_store_profit` | 511.8 |

## Never read, largest first

| table | index | MB |
|---|---|---:|
| inventory | `idx_inv_date_sk` | 1,030.0 |
| inventory | `idx_inv_item_sk` | 1,030.0 |
| inventory | `idx_inv_warehouse_sk` | 1,030.0 |
| store_sales | `idx_ss_q61` | 640.0 |
| store_sales | `idx_ss_date_store_price` | 469.7 |
| store_sales | `idx_ss_qty_q28` | 469.7 |
| store_sales | `idx_store_sales_quantity_2` | 469.7 |
| store_sales | `idx_ss_cust_date` | 425.6 |
| store_sales | `idx_ss_qty_cover` | 425.6 |
| store_sales | `idx_store_sales_2` | 425.6 |
| store_sales | `idx_ss_addr_sk` | 341.4 |
| store_sales | `idx_ss_cdemo_sk` | 341.4 |
| store_sales | `idx_ss_customer_sk` | 341.4 |
| store_sales | `idx_ss_hdemo_sk` | 341.4 |
| store_sales | `idx_ss_promo_sk` | 341.4 |
| store_sales | `idx_ss_sold_time_sk` | 341.4 |
| store_sales | `idx_ss_store_sk` | 341.4 |
| store_sales | `idx_store_sales_1` | 341.4 |
| store_sales | `idx_store_sales_quantity_1` | 341.4 |
| store_returns | `PRIMARY` | 301.4 |
| store_sales | `idx_ss_ticket_number` | 247.2 |
| catalog_sales | `idx_cs_cust_date_price` | 243.4 |
| catalog_sales | `idx_cs_price_date_cust` | 243.4 |
| catalog_sales | `idx_cs_cust_date` | 221.3 |
| catalog_returns | `PRIMARY` | 207.3 |
| catalog_sales | `idx_cs_bill_addr_sk` | 177.2 |
| catalog_sales | `idx_cs_bill_cdemo_sk` | 177.2 |
| catalog_sales | `idx_cs_bill_customer_sk` | 177.2 |
| catalog_sales | `idx_cs_bill_hdemo_sk` | 177.2 |
| catalog_sales | `idx_cs_call_center_sk` | 177.2 |

### Turning them off

Reversible, metadata-only, about 0.15s each — measure before dropping:

```sql
ALTER TABLE inventory ALTER INDEX idx_inv_date_sk IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_item_sk IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_warehouse_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_q61 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_date_store_price IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_qty_q28 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_store_sales_quantity_2 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_cust_date IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_qty_cover IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_store_sales_2 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_addr_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_cdemo_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_customer_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_hdemo_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_promo_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_sold_time_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_store_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_store_sales_1 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_store_sales_quantity_1 IGNORED;
ALTER TABLE store_returns ALTER INDEX PRIMARY IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_ticket_number IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_cust_date_price IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_price_date_cust IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_cust_date IGNORED;
ALTER TABLE catalog_returns ALTER INDEX PRIMARY IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_addr_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_cdemo_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_customer_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_hdemo_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_call_center_sk IGNORED;
```

Restore everything with `mariadb tpcds < sql/all_indexes.sql`.

## Most read

| table | index | rows read | MB |
|---|---|---:|---:|
| store_sales | `idx_ss_q78` | 84,676,586 | 598.0 |
| store_sales | `idx_ss_sold_date_sk` | 35,172,464 | 341.4 |
| store_sales | `idx_ss_sold_date_sk_store_sales_price` | 15,352,151 | 469.7 |
| inventory | `PRIMARY` | 12,282,535 | 2,528.0 |
| customer | `PRIMARY` | 11,698,751 | 57.1 |
| catalog_sales | `idx_cs_date_cover` | 7,040,380 | 375.8 |
| store | `PRIMARY` | 5,464,445 | 0.0 |
| store_sales | `idx_ss_date_cust` | 4,981,496 | 425.6 |
| store_sales | `PRIMARY` | 4,723,908 | 2,681.8 |
| catalog_sales | `idx_cs_sold_date_ext_price` | 4,634,536 | 199.3 |
| catalog_sales | `idx_cs_date_customer` | 3,610,983 | 221.3 |
| store_sales | `idx_ss_date_item_store_cover` | 2,694,696 | 469.7 |
| web_sales | `idx_ws_date_addr_item_price` | 2,686,075 | 127.2 |
| catalog_sales | `PRIMARY` | 2,384,346 | 1,836.0 |
| item | `PRIMARY` | 2,097,748 | 27.0 |
