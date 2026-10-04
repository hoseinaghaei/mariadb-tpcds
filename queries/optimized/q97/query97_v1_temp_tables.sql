CREATE TEMPORARY TABLE ssci_t (customer_sk INT, item_sk INT, KEY k (customer_sk, item_sk))
AS SELECT ss_customer_sk customer_sk, ss_item_sk item_sk
   FROM store_sales, date_dim
   WHERE ss_sold_date_sk = d_date_sk AND d_month_seq BETWEEN 1176 AND 1176 + 11
   GROUP BY ss_customer_sk, ss_item_sk;

CREATE TEMPORARY TABLE csci_t (customer_sk INT, item_sk INT, KEY k (customer_sk, item_sk))
AS SELECT cs_bill_customer_sk customer_sk, cs_item_sk item_sk
   FROM catalog_sales, date_dim
   WHERE cs_sold_date_sk = d_date_sk AND d_month_seq BETWEEN 1176 AND 1176 + 11
   GROUP BY cs_bill_customer_sk, cs_item_sk;

SELECT
  SUM(c.customer_sk IS NULL AND s.customer_sk IS NOT NULL) AS store_only,
  (SELECT COUNT(customer_sk) FROM csci_t) - SUM(c.customer_sk IS NOT NULL) AS catalog_only,
  SUM(c.customer_sk IS NOT NULL) AS store_and_catalog
FROM ssci_t s
LEFT JOIN csci_t c ON s.customer_sk = c.customer_sk AND s.item_sk = c.item_sk;


