WITH
w AS (
  SELECT DISTINCT c.c_last_name, c.c_first_name, d.d_date
  FROM date_dim d
  STRAIGHT_JOIN web_sales ws ON ws.ws_sold_date_sk = d.d_date_sk
  STRAIGHT_JOIN customer c   ON c.c_customer_sk = ws.ws_bill_customer_sk
  WHERE d.d_month_seq BETWEEN 1176 AND 1176 + 11
),
cw AS (
  SELECT DISTINCT c.c_last_name, c.c_first_name, d.d_date
  FROM date_dim d
  STRAIGHT_JOIN catalog_sales cs ON cs.cs_sold_date_sk = d.d_date_sk
  STRAIGHT_JOIN customer c       ON c.c_customer_sk = cs.cs_bill_customer_sk
  STRAIGHT_JOIN w ON w.c_last_name  <=> c.c_last_name
                 AND w.c_first_name <=> c.c_first_name
                 AND w.d_date       =   d.d_date
  WHERE d.d_month_seq BETWEEN 1176 AND 1176 + 11
)
SELECT COUNT(*) FROM (
  SELECT DISTINCT c.c_last_name, c.c_first_name, d.d_date
  FROM date_dim d
  STRAIGHT_JOIN store_sales ss ON ss.ss_sold_date_sk = d.d_date_sk
  STRAIGHT_JOIN customer c     ON c.c_customer_sk = ss.ss_customer_sk
  STRAIGHT_JOIN cw ON cw.c_last_name  <=> c.c_last_name
                  AND cw.c_first_name <=> c.c_first_name
                  AND cw.d_date       =   d.d_date
  WHERE d.d_month_seq BETWEEN 1176 AND 1176 + 11
) hot_cust;