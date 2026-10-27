# Indexes we build without, and why

Generated 2026-10-27 02:15 by `scripts/build-index-set.py`.

A new database builds **37 secondary indexes**. **130 others — 16,685 MB (16.3 GB) — are not built.**

These came from the reference repository, from our own optimizer experiments, and from indexes classmates contributed. They are not wrong; the 40 tier-4/5 queries simply never read them, at either scale factor, under this configuration — **as measured inside the container itself**. An earlier version of this list was derived from macOS measurements and was wrong: at SF=1, with identical data and the same MariaDB version, the two environments disagreed about 6 of 188 indexes, three of which the container reads and macOS does not.

## It satisfies the usage rule and still costs SF=4 dearly

Measured in the container with this exact set:

| | SF=1 | SF=4 |
|---|---:|---:|
| full set (166) | 114.8–205.2s over five runs | **491.4s** |
| this set (37) | **101.7s** | **1487.0s** |

At SF=1 it is the best result measured. At SF=4 it is **3x worse**, and a second pruned set built from different evidence was also worse (738.3s), so the direction is not an accident.

**Why a usage-derived set can still be wrong.** The counters were taken with all 166 indexes present, and they record which indexes the optimizer *chose* — not which ones it needed in order to choose well. Remove 129 of them and the cost estimates move, so the plans move. The proof is in this run's own report: **7 of the 37 kept indexes were never read**, and 8 at SF=1. If the plans had survived the pruning, all 37 would still be in use.

At SF=1 the database nearly fits the 8 GB pool, so freeing 16 GB of index pages outweighs the worse plans. At SF=4 it does not fit either way, and the worse plans are all that is left.

**On timing, this list makes no promise.** An earlier attempt claimed dropping indexes made the suite faster; that rested on two noisy measurements and is withdrawn. Five runs of the *unchanged* full set at SF=1 measured 114.8, 142.0, 191.6, 200.7 and 205.2s — a spread far wider than any index effect being looked for. What this list rests on instead is read counters, which are exact: an index was read or it was not.

## Getting them back

```bash
mariadb tpcds < sql/all_indexes.sql     # every index, one command
```

Worth knowing before you decide they are gone for good: **"unused" is a property of an index *and* a workload *and* a configuration**, not of the index. This project measured the same set at 16K and at 32K pages and got different answers about which members were idle (`report/17`, `report/22`).

## What is not built

| table | index | MB | came from | why |
|---|---|---:|---|---|
| inventory | `idx_inv_date_sk` | 1,030 | reference repo | read by neither SF=1 nor SF=4 |
| inventory | `idx_inv_item_sk` | 1,030 | reference repo | read by neither SF=1 nor SF=4 |
| inventory | `idx_inv_warehouse_sk` | 1,030 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_q61` | 640 | contributed by the team | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_date_store_price` | 470 | contributed by the team | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_qty_q28` | 470 | contributed by the team | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_sold_date_sk_store_sales_price` | 470 | optimizer experiments | read by neither SF=1 nor SF=4 |
| store_sales | `idx_store_sales_quantity_2` | 470 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_cust_date` | 426 | contributed by the team | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_qty_cover` | 426 | contributed by the team | read by neither SF=1 nor SF=4 |
| store_sales | `idx_store_sales_2` | 426 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_addr_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_cdemo_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_customer_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_hdemo_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_promo_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_sold_time_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_store_sk` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_store_sales_1` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_store_sales_quantity_1` | 341 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_ticket_number` | 247 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_cust_date_price` | 243 | contributed by the team | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_price_date_cust` | 243 | contributed by the team | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_cust_date` | 221 | contributed by the team | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_bill_addr_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_bill_cdemo_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_bill_customer_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_bill_hdemo_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_call_center_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_catalog_page_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_promo_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_ship_addr_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_ship_cdemo_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_ship_customer_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_ship_date_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_ship_hdemo_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_ship_mode_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_sold_date_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_sold_time_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_warehouse_sk` | 177 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_sales | `idx_cs_order_number` | 127 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_cust_date` | 115 | contributed by the team | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_date_item_paid` | 105 | contributed by the team | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_bill_addr_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_bill_cdemo_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_bill_customer_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_bill_hdemo_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_promo_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_ship_addr_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_ship_cdemo_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_ship_customer_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_ship_date_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_ship_hdemo_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_ship_mode_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_sold_date_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_sold_time_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_warehouse_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_web_page_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_web_site_sk` | 93 | reference repo | read by neither SF=1 nor SF=4 |
| customer_demographics | `idx_customer_demographics_1` | 77 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_item_sk` | 69 | reference repo | read by neither SF=1 nor SF=4 |
| web_sales | `idx_ws_order_number` | 69 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_addr_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_cdemo_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_customer_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_hdemo_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_reason_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_returned_date_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_return_time_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_store_sk` | 39 | reference repo | read by neither SF=1 nor SF=4 |
| store_returns | `idx_sr_ticket_number` | 29 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_call_center_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_catalog_page_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_reason_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_refunded_addr_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_refunded_cdemo_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_refunded_customer_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_refunded_hdemo_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_returned_date_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_returned_time_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_returning_addr_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_returning_cdemo_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_returning_customer_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_returning_hdemo_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_ship_mode_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_warehouse_sk` | 21 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_returns | `idx_cr_order_number` | 15 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_reason_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_refunded_addr_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_refunded_cdemo_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_refunded_customer_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_refunded_hdemo_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_returned_date_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_returned_time_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_returning_addr_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_returning_cdemo_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_returning_customer_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_returning_hdemo_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_web_page_sk` | 11 | reference repo | read by neither SF=1 nor SF=4 |
| customer | `idx_c_addr` | 7 | contributed by the team | read by neither SF=1 nor SF=4 |
| customer | `idx_c_current_addr_sk` | 7 | reference repo | read by neither SF=1 nor SF=4 |
| customer | `idx_c_current_cdemo_sk` | 7 | reference repo | read by neither SF=1 nor SF=4 |
| customer | `idx_c_current_hdemo_sk` | 7 | reference repo | read by neither SF=1 nor SF=4 |
| customer | `idx_c_first_sales_date_sk` | 7 | reference repo | read by neither SF=1 nor SF=4 |
| customer | `idx_c_first_shipto_date_sk` | 7 | reference repo | read by neither SF=1 nor SF=4 |
| web_returns | `idx_wr_order_number` | 7 | reference repo | read by neither SF=1 nor SF=4 |
| customer_address | `idx_customer_address_1` | 5 | reference repo | read by neither SF=1 nor SF=4 |
| item | `idx_item_2` | 5 | reference repo | read by neither SF=1 nor SF=4 |
| item | `idx_item_cat` | 5 | contributed by the team | read by neither SF=1 nor SF=4 |
| item | `idx_item_category_id` | 5 | contributed by the team | read by neither SF=1 nor SF=4 |
| date_dim | `idx_date_month_date_sk` | 3 | contributed by the team | read by neither SF=1 nor SF=4 |
| date_dim | `idx_date_year_sk` | 3 | contributed by the team | read by neither SF=1 nor SF=4 |
| date_dim | `idx_date_ym` | 3 | contributed by the team | read by neither SF=1 nor SF=4 |
| item | `idx_item_price` | 1 | contributed by the team | read by neither SF=1 nor SF=4 |
| catalog_page | `idx_cp_end_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| catalog_page | `idx_cp_start_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| household_demographics | `idx_hd_income_band_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| call_center | `idx_cc_closed_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| call_center | `idx_cc_open_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| promotion | `idx_p_end_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| promotion | `idx_p_item_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| promotion | `idx_p_start_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| store | `idx_store_gmt` | 0 | contributed by the team | read by neither SF=1 nor SF=4 |
| store | `idx_s_closed_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_date_store_profit` | 0 | measured here | built for q77 and does nothing for q77; helps q5 (~2.4x) and q70 (~2.9x) reproducibly but costs 512 MB and more than doubles store_sales index storage. Left out pending a decision; sql/15_q77_covering_index.sql creates it. |
| web_page | `idx_wp_access_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_page | `idx_wp_creation_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_page | `idx_wp_customer_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_site | `idx_web_close_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_site | `idx_web_open_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
