-- v1: exact date-key ranges with redundant date_dim joins removed.
SELECT cd_gender,cd_marital_status,cd_education_status,COUNT(*) cnt1,cd_purchase_estimate,COUNT(*) cnt2,cd_credit_rating,COUNT(*) cnt3,cd_dep_count,COUNT(*) cnt4,cd_dep_employed_count,COUNT(*) cnt5,cd_dep_college_count,COUNT(*) cnt6
FROM customer c, customer_address ca, customer_demographics
WHERE c.c_current_addr_sk=ca.ca_address_sk AND ca_county IN ('Madison County','Wallowa County','Calhoun County','Broadwater County','McCone County') AND cd_demo_sk=c.c_current_cdemo_sk
 AND EXISTS (SELECT 1 FROM store_sales WHERE c.c_customer_sk=ss_customer_sk AND ss_sold_date_sk BETWEEN 2452001 AND 2452122)
 AND (EXISTS (SELECT 1 FROM web_sales WHERE c.c_customer_sk=ws_bill_customer_sk AND ws_sold_date_sk BETWEEN 2452001 AND 2452122) OR EXISTS (SELECT 1 FROM catalog_sales WHERE c.c_customer_sk=cs_ship_customer_sk AND cs_sold_date_sk BETWEEN 2452001 AND 2452122))
GROUP BY cd_gender,cd_marital_status,cd_education_status,cd_purchase_estimate,cd_credit_rating,cd_dep_count,cd_dep_employed_count,cd_dep_college_count
ORDER BY cd_gender,cd_marital_status,cd_education_status,cd_purchase_estimate,cd_credit_rating,cd_dep_count,cd_dep_employed_count,cd_dep_college_count LIMIT 100;
