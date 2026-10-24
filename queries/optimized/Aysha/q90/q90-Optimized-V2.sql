select straight_join
       cast(sum(t_hour between 12 and 13) as decimal(15,4))
     / cast(sum(t_hour between 17 and 18) as decimal(15,4)) as am_pm_ratio
from web_page
join household_demographics on hd_dep_count = 1
join web_sales              on ws_web_page_sk = wp_web_page_sk
                           and ws_ship_hdemo_sk = hd_demo_sk
join time_dim               on t_time_sk = ws_sold_time_sk
                           and t_hour in (12,13,17,18)
where wp_char_count between 5000 and 5200;