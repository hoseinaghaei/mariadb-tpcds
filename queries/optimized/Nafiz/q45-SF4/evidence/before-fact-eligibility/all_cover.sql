SELECT ca_zip,ca_county,SUM(amount) FROM (
SELECT ca_zip,ca_county,SUM(ws_sales_price) amount FROM customer_address STRAIGHT_JOIN customer ON c_current_addr_sk=ca_address_sk
STRAIGHT_JOIN web_sales ON ws_bill_customer_sk=c_customer_sk
STRAIGHT_JOIN date_dim ON ws_sold_date_sk=d_date_sk
STRAIGHT_JOIN item ON ws_item_sk=i_item_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001 AND (ca_zip LIKE '85669%' OR ca_zip LIKE '86197%' OR ca_zip LIKE '88274%' OR ca_zip LIKE '83405%' OR ca_zip LIKE '86475%' OR ca_zip LIKE '85392%' OR ca_zip LIKE '85460%' OR ca_zip LIKE '80348%' OR ca_zip LIKE '81792%') AND SUBSTR(ca_zip,1,5) IN ('85669','86197','88274','83405','86475','85392','85460','80348','81792') GROUP BY ca_zip,ca_county
UNION ALL
SELECT ca_zip,ca_county,SUM(ws_sales_price) amount FROM item STRAIGHT_JOIN web_sales ON ws_item_sk=i_item_sk
STRAIGHT_JOIN date_dim ON ws_sold_date_sk=d_date_sk
STRAIGHT_JOIN customer ON ws_bill_customer_sk=c_customer_sk
STRAIGHT_JOIN customer_address ON c_current_addr_sk=ca_address_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001 AND i_item_id IN(SELECT i_item_id FROM item WHERE i_item_sk IN (2,3,5,7,11,13,17,19,23,29)) AND (SUBSTR(ca_zip,1,5) IN ('85669','86197','88274','83405','86475','85392','85460','80348','81792')) IS NOT TRUE GROUP BY ca_zip,ca_county
) branches GROUP BY ca_zip,ca_county ORDER BY ca_zip,ca_county LIMIT 100;