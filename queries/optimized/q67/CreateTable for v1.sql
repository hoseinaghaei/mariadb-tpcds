USE tpcds;

DROP TABLE IF EXISTS q67_rollup;

CREATE TABLE q67_rollup (
    i_category VARCHAR(100) NULL,
    i_class VARCHAR(100) NULL,
    i_brand VARCHAR(100) NULL,
    i_product_name VARCHAR(200) NULL,
    d_year INT NULL,
    d_qoy INT NULL,
    d_moy INT NULL,
    s_store_id VARCHAR(100) NULL,
    sumsales DECIMAL(30,2) NULL
);

INSERT INTO q67_rollup
SELECT
    i_category,
    i_class,
    i_brand,
    i_product_name,
    d_year,
    d_qoy,
    d_moy,
    s_store_id,
    SUM(COALESCE(ss_sales_price * ss_quantity, 0))
FROM store_sales
JOIN date_dim
    ON ss_sold_date_sk = d_date_sk
JOIN store
    ON ss_store_sk = s_store_sk
JOIN item
    ON ss_item_sk = i_item_sk
WHERE d_month_seq BETWEEN 1176 AND 1187
GROUP BY
    i_category,
    i_class,
    i_brand,
    i_product_name,
    d_year,
    d_qoy,
    d_moy,
    s_store_id
WITH ROLLUP;

