WITH fact_totals AS (SELECT f.ss_customer_sk customer_sk,d.d_year dyear,SUM(f.ss_ext_list_price-f.ss_ext_discount_amt) amount,'s' sale_type
FROM store_sales f JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
WHERE d.d_year IN (2001,2002) GROUP BY f.ss_customer_sk,d.d_year
UNION ALL
SELECT f.ws_bill_customer_sk customer_sk,d.d_year dyear,SUM(f.ws_ext_list_price-f.ws_ext_discount_amt) amount,'w' sale_type
FROM web_sales f JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
WHERE d.d_year IN (2001,2002) GROUP BY f.ws_bill_customer_sk,d.d_year), year_total AS (
SELECT c.c_customer_id customer_id,c.c_first_name customer_first_name,c.c_last_name customer_last_name,c.c_preferred_cust_flag customer_preferred_cust_flag,c.c_birth_country customer_birth_country,c.c_login customer_login,c.c_email_address customer_email_address,f.dyear,SUM(f.amount) year_total,f.sale_type FROM fact_totals f JOIN customer c ON c.c_customer_sk=f.customer_sk
GROUP BY c.c_customer_id,c.c_first_name,c.c_last_name,c.c_preferred_cust_flag,c.c_birth_country,c.c_login,c.c_email_address,f.dyear,f.sale_type)
select  
                  t_s_secyear.customer_id
                 ,t_s_secyear.customer_first_name
                 ,t_s_secyear.customer_last_name
                 ,t_s_secyear.customer_login
 from year_total t_s_firstyear
     ,year_total t_s_secyear
     ,year_total t_w_firstyear
     ,year_total t_w_secyear
 where t_s_secyear.customer_id = t_s_firstyear.customer_id
         and t_s_firstyear.customer_id = t_w_secyear.customer_id
         and t_s_firstyear.customer_id = t_w_firstyear.customer_id
         and t_s_firstyear.sale_type = 's'
         and t_w_firstyear.sale_type = 'w'
         and t_s_secyear.sale_type = 's'
         and t_w_secyear.sale_type = 'w'
         and t_s_firstyear.dyear = 2001
         and t_s_secyear.dyear = 2001+1
         and t_w_firstyear.dyear = 2001
         and t_w_secyear.dyear = 2001+1
         and t_s_firstyear.year_total > 0
         and t_w_firstyear.year_total > 0
         and case when t_w_firstyear.year_total > 0 then t_w_secyear.year_total / t_w_firstyear.year_total else 0.0 end
             > case when t_s_firstyear.year_total > 0 then t_s_secyear.year_total / t_s_firstyear.year_total else 0.0 end
 order by t_s_secyear.customer_id
         ,t_s_secyear.customer_first_name
         ,t_s_secyear.customer_last_name
         ,t_s_secyear.customer_login
limit 100;
