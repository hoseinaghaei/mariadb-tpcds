create index idx_ws_page_hdemo_time
  on web_sales (ws_web_page_sk, ws_ship_hdemo_sk, ws_sold_time_sk);

analyze format=json
select straight_join
       cast(sum(t_hour between 12 and 13) as decimal(15,4))
     / cast(sum(t_hour between 17 and 18) as decimal(15,4)) as am_pm_ratio
from web_sales
join web_page              on wp_web_page_sk = ws_web_page_sk
                          and wp_char_count between 5000 and 5200
join household_demographics on hd_demo_sk = ws_ship_hdemo_sk
                          and hd_dep_count = 1
join time_dim              on t_time_sk = ws_sold_time_sk
                          and t_hour in (12,13,17,18);