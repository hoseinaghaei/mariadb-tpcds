# Indexes we build without, and why

> ## ⚠ This list is not yet trustworthy for the container
>
> The usage evidence behind it was collected on the **macOS host** — and at
> SF=4 on a dataset generated without `-RNGSEED 10`, which is a *different
> database*. It describes what those instances read, not what the container
> reads.
>
> Building this set in the container measured **738.3s at SF=4 against
> 491.4s for the full set**, and **156.9s at SF=1 against 114.8s** — the
> opposite of the 13% improvement the macOS evidence predicted.
>
> The container therefore still builds the full index set by default.
> `KEPT_INDEXES=1` opts into this one. The list has to be re-derived from
> container measurements before it means anything here.


Generated 2026-10-26 22:37 by `scripts/build-index-set.py`.

A new database builds **39 secondary indexes**. **128 others — 16,826 MB (16.4 GB) — are not built.**

These came from the reference repository, from our own optimizer experiments, and from indexes classmates contributed. They are not wrong; the 40 tier-4/5 queries simply never read them, at either scale factor, under this configuration.

Dropping them is not only free, it is faster: with 127 of them gone the suite ran **114.8s → 100.0s at SF=1 with identical answers**, because index pages stop competing with data pages for the buffer pool. The same effect in reverse once made 16K/SF=1 **40% slower** when six indexes were added.

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
| store_sales | `idx_ss_date_store_profit` | 512 | measured here | built for q77 and does nothing for q77; helps q5 (~2.4x) and q70 (~2.9x) reproducibly but costs 512 MB and more than doubles store_sales index storage. Left out pending a decision; sql/15_q77_covering_index.sql creates it. |
| store_sales | `idx_ss_date_store_price` | 470 | contributed by the team | read by neither SF=1 nor SF=4 |
| store_sales | `idx_ss_qty_q28` | 470 | contributed by the team | read by neither SF=1 nor SF=4 |
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
| web_sales | `idx_ws_sold_date_ext_price` | 105 | optimizer experiments | read by neither SF=1 nor SF=4 |
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
| web_page | `idx_wp_access_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_page | `idx_wp_creation_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_page | `idx_wp_customer_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_site | `idx_web_close_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
| web_site | `idx_web_open_date_sk` | 0 | reference repo | read by neither SF=1 nor SF=4 |
