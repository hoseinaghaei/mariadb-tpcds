-- Added index 
CREATE INDEX idx_ws_date_item_paid
ON web_sales (
    ws_sold_date_sk,
    ws_item_sk,
    ws_net_paid
);

-- Changed teh order of the join 
-- date dim -> web sales
-- web sales -> items

-- analyze format=json
select * from (
select   
    sum(ws_net_paid) as total_sum
   ,i_category
   ,i_class
   ,(i_category is null)+(i_class is null) as lochierarchy
   ,rank() over (
 	partition by (i_category is null)+(i_class is null),
 	case when (i_class is null) = 0 then i_category end 
 	order by sum(ws_net_paid) desc) as rank_within_parent
 FROM date_dim	d1
 	straight_join web_sales ON ws_sold_date_sk= d1.d_date_sk
 	straight_join item ON i_item_sk = ws_item_sk
 where
    d1.d_month_seq between 1176 and 1176+11
 and d1.d_date_sk = ws_sold_date_sk
 and i_item_sk  = ws_item_sk
 group by i_category,i_class with rollup
) tpcds_rollup
order by
   lochierarchy desc,
   case when lochierarchy = 0 then i_category end,
   rank_within_parent
 limit 100;

show profiles;
