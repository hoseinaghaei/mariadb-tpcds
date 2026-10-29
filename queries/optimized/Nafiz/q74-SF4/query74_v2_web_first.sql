WITH id_guard AS (SELECT COUNT(*)=COUNT(DISTINCT c_customer_id) ok FROM customer FORCE INDEX (idx_nf_q74_customer_order)), year_total as (
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,d_year as year
       ,max(ss_net_paid) year_total
       ,'s' sale_type
 from customer
     ,store_sales
     ,date_dim
 where c_customer_sk = ss_customer_sk
   and ss_sold_date_sk = d_date_sk
   and d_year in (1999,1999+1)
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,d_year
 union all
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,d_year as year
       ,max(ws_net_paid) year_total
       ,'w' sale_type
 from customer
     ,web_sales
     ,date_dim
 where c_customer_sk = ws_bill_customer_sk
   and ws_sold_date_sk = d_date_sk
   and d_year in (1999,1999+1)
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,d_year
         ), fast AS (SELECT c.c_customer_id customer_id,c.c_first_name customer_first_name,c.c_last_name customer_last_name
FROM customer c FORCE INDEX (idx_nf_q74_customer_order)
WHERE (SELECT ok FROM id_guard)=1 AND (SELECT STRAIGHT_JOIN f.ws_net_paid FROM web_sales f FORCE INDEX (idx_nf_q74_ws_top) JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
WHERE f.ws_bill_customer_sk=c.c_customer_sk AND d.d_year=1999 ORDER BY f.ws_net_paid DESC LIMIT 1)>0 AND (SELECT STRAIGHT_JOIN f.ss_net_paid FROM store_sales f FORCE INDEX (idx_nf_q74_ss_top) JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
WHERE f.ss_customer_sk=c.c_customer_sk AND d.d_year=1999 ORDER BY f.ss_net_paid DESC LIMIT 1)>0
AND CASE WHEN (SELECT STRAIGHT_JOIN f.ws_net_paid FROM web_sales f FORCE INDEX (idx_nf_q74_ws_top) JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
WHERE f.ws_bill_customer_sk=c.c_customer_sk AND d.d_year=1999 ORDER BY f.ws_net_paid DESC LIMIT 1)>0 THEN (SELECT STRAIGHT_JOIN f.ws_net_paid FROM web_sales f FORCE INDEX (idx_nf_q74_ws_top) JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
WHERE f.ws_bill_customer_sk=c.c_customer_sk AND d.d_year=2000 ORDER BY f.ws_net_paid DESC LIMIT 1)/(SELECT STRAIGHT_JOIN f.ws_net_paid FROM web_sales f FORCE INDEX (idx_nf_q74_ws_top) JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
WHERE f.ws_bill_customer_sk=c.c_customer_sk AND d.d_year=1999 ORDER BY f.ws_net_paid DESC LIMIT 1) ELSE NULL END > CASE WHEN (SELECT STRAIGHT_JOIN f.ss_net_paid FROM store_sales f FORCE INDEX (idx_nf_q74_ss_top) JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
WHERE f.ss_customer_sk=c.c_customer_sk AND d.d_year=1999 ORDER BY f.ss_net_paid DESC LIMIT 1)>0 THEN (SELECT STRAIGHT_JOIN f.ss_net_paid FROM store_sales f FORCE INDEX (idx_nf_q74_ss_top) JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
WHERE f.ss_customer_sk=c.c_customer_sk AND d.d_year=2000 ORDER BY f.ss_net_paid DESC LIMIT 1)/(SELECT STRAIGHT_JOIN f.ss_net_paid FROM store_sales f FORCE INDEX (idx_nf_q74_ss_top) JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
WHERE f.ss_customer_sk=c.c_customer_sk AND d.d_year=1999 ORDER BY f.ss_net_paid DESC LIMIT 1) ELSE NULL END
ORDER BY c.c_first_name,c.c_customer_id,c.c_last_name LIMIT 100), slow AS (select 
        t_s_secyear.customer_id, t_s_secyear.customer_first_name, t_s_secyear.customer_last_name
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
         and t_s_firstyear.year = 1999
         and t_s_secyear.year = 1999+1
         and t_w_firstyear.year = 1999
         and t_w_secyear.year = 1999+1
         and t_s_firstyear.year_total > 0
         and t_w_firstyear.year_total > 0
         and case when t_w_firstyear.year_total > 0 then t_w_secyear.year_total / t_w_firstyear.year_total else null end
           > case when t_s_firstyear.year_total > 0 then t_s_secyear.year_total / t_s_firstyear.year_total else null end
 AND (SELECT ok FROM id_guard)=0
 order by 2,1,3
limit 100) SELECT * FROM fast UNION ALL SELECT * FROM slow ORDER BY 2,1,3 LIMIT 100;