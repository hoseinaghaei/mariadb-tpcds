# Index usefulness at SF=1

Counters zeroed, then the 40 tier-4/5 queries in `queries/tuned/` run once. `UNUSED` means **not read by those 40 queries at this scale under this configuration** — it is not a property of the index.

| | indexes | disk |
|---|---:|---:|
| read at least once | 52 | 4,615 MB |
| enabled but never read | 136 | **5,082 MB** |
| total | 188 | 9,696 MB |

## Never read, largest first

| table | index | MB |
|---|---|---:|
| inventory | `idx_inv_date_sk` | 341.4 |
| inventory | `idx_inv_item_sk` | 341.4 |
| inventory | `idx_inv_warehouse_sk` | 341.4 |
| store_sales | `idx_ss_q61` | 165.3 |
| store_sales | `idx_ss_date_store_price` | 123.2 |
| store_sales | `idx_ss_qty_q28` | 123.2 |
| store_sales | `idx_ss_sold_date_sk_store_sales_price` | 123.2 |
| store_sales | `idx_store_sales_quantity_2` | 123.2 |
| store_sales | `idx_ss_cust_date` | 113.2 |
| store_sales | `idx_ss_qty_cover` | 113.2 |
| store_sales | `idx_store_sales_2` | 113.2 |
| store_sales | `idx_ss_addr_sk` | 93.1 |
| store_sales | `idx_ss_cdemo_sk` | 93.1 |
| store_sales | `idx_ss_customer_sk` | 93.1 |
| store_sales | `idx_ss_hdemo_sk` | 93.1 |
| store_sales | `idx_ss_promo_sk` | 93.1 |
| store_sales | `idx_ss_sold_time_sk` | 93.1 |
| store_sales | `idx_ss_store_sk` | 93.1 |
| store_sales | `idx_store_sales_1` | 93.1 |
| store_sales | `idx_store_sales_quantity_1` | 93.1 |
| customer_demographics | `idx_customer_demographics_1` | 77.1 |
| store_returns | `PRIMARY` | 77.1 |
| store_sales | `idx_ss_item_sk` | 69.1 |
| store_sales | `idx_ss_ticket_number` | 69.1 |
| catalog_sales | `idx_cs_cust_date_price` | 67.1 |
| catalog_sales | `idx_cs_price_date_cust` | 67.1 |
| catalog_sales | `idx_cs_cust_date` | 61.1 |
| catalog_returns | `PRIMARY` | 55.1 |
| catalog_sales | `idx_cs_bill_addr_sk` | 49.1 |
| catalog_sales | `idx_cs_bill_cdemo_sk` | 49.1 |

### Turning them off

Reversible, metadata-only, about 0.15s each — measure before dropping:

```sql
ALTER TABLE inventory ALTER INDEX idx_inv_date_sk IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_item_sk IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_warehouse_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_q61 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_date_store_price IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_qty_q28 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_sold_date_sk_store_sales_price IGNORED;
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
ALTER TABLE customer_demographics ALTER INDEX idx_customer_demographics_1 IGNORED;
ALTER TABLE store_returns ALTER INDEX PRIMARY IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_item_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_ticket_number IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_cust_date_price IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_price_date_cust IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_cust_date IGNORED;
ALTER TABLE catalog_returns ALTER INDEX PRIMARY IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_addr_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_cdemo_sk IGNORED;
```

Restore everything with `mariadb tpcds < sql/all_indexes.sql`.

## Most read

| table | index | rows read | MB |
|---|---|---:|---:|
| store_sales | `idx_ss_q78` | 22,063,660 | 155.3 |
| inventory | `idx_inv_item_date_sk` | 11,793,753 | 437.6 |
| store_sales | `idx_ss_sold_date_sk` | 8,806,524 | 93.1 |
| store_sales | `idx_ss_date_item_store_cover` | 4,504,512 | 123.2 |
| customer | `PRIMARY` | 3,408,069 | 25.0 |
| catalog_sales | `idx_cs_date_cover` | 1,766,513 | 101.3 |
| inventory | `PRIMARY` | 1,620,000 | 868.0 |
| store | `PRIMARY` | 1,570,578 | 0.0 |
| store_sales | `PRIMARY` | 1,199,426 | 746.0 |
| catalog_sales | `idx_cs_sold_date_ext_price` | 1,158,154 | 55.1 |
| catalog_sales | `idx_cs_date_customer` | 904,090 | 61.1 |
| web_sales | `idx_ws_date_addr_item_price` | 674,725 | 35.1 |
| catalog_sales | `PRIMARY` | 603,550 | 614.0 |
| household_demographics | `PRIMARY` | 561,426 | 0.6 |
| customer_address | `PRIMARY` | 440,930 | 9.0 |
