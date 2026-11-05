-- Indexes added

-- CREATE INDEX idx_cs_cust ON catalog_sales (cs_bill_customer_sk, cs_sold_date_sk) ALGORITHM=INPLACE LOCK=NONE;
-- CREATE INDEX idx_ss_cust ON store_sales (ss_customer_sk, ss_sold_date_sk) ALGORITHM=INPLACE LOCK=NONE;
-- CREATE INDEX idx_ss_customer_date ON store_sales (ss_customer_sk, ss_sold_date_sk);

-- seperaet date ranges so that we can use BETWEEN in the main part fo teh SELECT query
SET @start_2001 = (SELECT MIN(d_date_sk) FROM date_dim WHERE d_year = 2001);
SET @start_2002 = (SELECT MIN(d_date_sk) FROM date_dim WHERE d_year = 2002);
SET @end_2002   = (SELECT MAX(d_date_sk) FROM date_dim WHERE d_year = 2002);
WITH w AS (
    SELECT ws_bill_customer_sk AS customer_sk,
           SUM(CASE WHEN ws_sold_date_sk <  @start_2002 THEN ((ws_ext_list_price - ws_ext_wholesale_cost - ws_ext_discount_amt) + ws_ext_sales_price) / 2 END) AS w_y1,
           SUM(CASE WHEN ws_sold_date_sk >= @start_2002 THEN ((ws_ext_list_price - ws_ext_wholesale_cost - ws_ext_discount_amt) + ws_ext_sales_price) / 2 END) AS w_y2
    FROM web_sales
    WHERE ws_sold_date_sk BETWEEN @start_2001 AND @end_2002
      AND ws_bill_customer_sk IS NOT NULL
    GROUP BY ws_bill_customer_sk
    HAVING w_y1 > 0 AND w_y2 IS NOT NULL
),
c AS (
    SELECT cs.cs_bill_customer_sk AS customer_sk,
           SUM(CASE WHEN cs.cs_sold_date_sk <  @start_2002 THEN ((cs.cs_ext_list_price - cs.cs_ext_wholesale_cost - cs.cs_ext_discount_amt) + cs.cs_ext_sales_price) / 2 END) AS c_y1,
           SUM(CASE WHEN cs.cs_sold_date_sk >= @start_2002 THEN ((cs.cs_ext_list_price - cs.cs_ext_wholesale_cost - cs.cs_ext_discount_amt) + cs.cs_ext_sales_price) / 2 END) AS c_y2
    FROM w
    STRAIGHT_JOIN catalog_sales cs ON cs.cs_bill_customer_sk = w.customer_sk
    WHERE cs.cs_sold_date_sk BETWEEN @start_2001 AND @end_2002
    GROUP BY cs.cs_bill_customer_sk, w.w_y1, w.w_y2
    HAVING c_y1 > 0 AND c_y2 IS NOT NULL
       AND c_y2 * w.w_y1 > w.w_y2 * c_y1
),
s AS (
    SELECT c.customer_sk
    FROM c
    STRAIGHT_JOIN store_sales ss ON ss.ss_customer_sk = c.customer_sk
    WHERE ss.ss_sold_date_sk BETWEEN @start_2001 AND @end_2002
    GROUP BY c.customer_sk, c.c_y1, c.c_y2
    HAVING SUM(CASE WHEN ss.ss_sold_date_sk <  @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END) > 0
       AND SUM(CASE WHEN ss.ss_sold_date_sk >= @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END) IS NOT NULL
       AND c.c_y2 * SUM(CASE WHEN ss.ss_sold_date_sk <  @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END)
         > SUM(CASE WHEN ss.ss_sold_date_sk >= @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END) * c.c_y1
)
SELECT cu.c_customer_id AS customer_id,
       cu.c_first_name  AS customer_first_name,
       cu.c_last_name   AS customer_last_name,
       cu.c_login       AS customer_login
FROM s
JOIN customer cu ON cu.c_customer_sk = s.customer_sk
ORDER BY customer_id, customer_first_name, customer_last_name, customer_login
LIMIT 100;