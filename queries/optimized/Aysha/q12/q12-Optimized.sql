-- Uses index idx_ws_date_item_price

analyze format=json
select straight_join i_item_id
      ,i_item_desc 
      ,i_category 
      ,i_class 
      ,i_current_price
      ,sum(ws_ext_sales_price) as itemrevenue 
      ,sum(ws_ext_sales_price)*100/sum(sum(ws_ext_sales_price)) over
          (partition by i_class) as revenueratio
from	
date_dim
straight_join web_sales on ws_sold_date_sk=d_date_sk 
straight_join item on i_item_sk =ws_item_sk 
where 
	ws_item_sk = i_item_sk 
  	and i_category in ('Music', 'Children', 'Men')
  	and ws_sold_date_sk = d_date_sk
	and d_date between cast('2002-02-23' as date) 
				and (cast('2002-02-23' as date) + interval 30 day)
group by 
	i_item_id
        ,i_item_desc 
        ,i_category
        ,i_class
        ,i_current_price
order by 
	i_category
        ,i_class
        ,i_item_id
        ,i_item_desc
        ,revenueratio
limit 100;
