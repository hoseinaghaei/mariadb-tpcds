WITH book_manufacturers AS (SELECT DISTINCT i_manufact_id FROM item WHERE i_category='Books'), channel_sales AS (SELECT f.ss_item_sk AS item_sk,f.ss_ext_sales_price AS sales FROM store_sales f JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.ss_addr_sk=a.ca_address_sk
WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5
UNION ALL
SELECT f.cs_item_sk AS item_sk,f.cs_ext_sales_price AS sales FROM catalog_sales f JOIN date_dim d ON f.cs_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.cs_bill_addr_sk=a.ca_address_sk
WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5
UNION ALL
SELECT f.ws_item_sk AS item_sk,f.ws_ext_sales_price AS sales FROM web_sales f JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.ws_bill_addr_sk=a.ca_address_sk
WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5)
SELECT i.i_manufact_id,SUM(f.sales) total_sales FROM channel_sales f
JOIN item i ON f.item_sk=i.i_item_sk JOIN book_manufacturers b ON b.i_manufact_id=i.i_manufact_id
GROUP BY i.i_manufact_id ORDER BY total_sales LIMIT 100;