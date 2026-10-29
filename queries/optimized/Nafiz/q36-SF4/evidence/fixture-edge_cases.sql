CREATE TEMPORARY TABLE nf_tmp_store_sales LIKE tpcds.store_sales;
CREATE TEMPORARY TABLE nf_tmp_date_dim LIKE tpcds.date_dim;
CREATE TEMPORARY TABLE nf_tmp_item LIKE tpcds.item;
CREATE TEMPORARY TABLE nf_tmp_store LIKE tpcds.store;
INSERT INTO nf_tmp_date_dim (d_date_sk,d_date_id,d_date,d_year) VALUES (2451911,'D1','2001-01-01',2001),(2452275,'D2','2001-12-31',2001),(2452276,'D3','2002-01-01',2002);
INSERT INTO nf_tmp_store (s_store_sk,s_store_id,s_state) VALUES (1,'S1','TN'),(2,'S2','CA');
INSERT INTO nf_tmp_item (i_item_sk,i_item_id,i_category,i_class) VALUES (1,'I1','A','One'),(2,'I2','A',NULL),(3,'I3',NULL,'One'),(4,'I4',NULL,NULL),(5,'I5','B','Two'),(6,'I6','B','Three'),(7,'I7','C','Only');
INSERT INTO nf_tmp_store_sales (ss_item_sk,ss_ticket_number,ss_sold_date_sk,ss_store_sk,ss_net_profit,ss_ext_sales_price) VALUES (1,1,2451911,1,10,100),(1,2,2452275,1,20,100),(2,3,2451911,1,5,100),(3,4,2451911,1,5,50),(4,5,2451911,1,NULL,30),(5,6,2451911,1,0,0),(6,7,2451911,1,NULL,NULL),(7,8,2451911,1,7,NULL),(1,9,2452276,1,999,1000),(1,10,2451911,2,999,1000),(99,11,2451911,1,999,1000),(1,12,2451912,1,999,1000),(1,13,2451911,99,999,1000);
