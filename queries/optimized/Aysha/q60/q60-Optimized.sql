create index idx_ss_date_addr_item_price on store_sales   (ss_sold_date_sk, ss_addr_sk, ss_item_sk, ss_ext_sales_price);
create index idx_cs_date_addr_item_price on catalog_sales (cs_sold_date_sk, cs_bill_addr_sk, cs_item_sk, cs_ext_sales_price);
create index idx_ws_date_addr_item_price on web_sales     (ws_sold_date_sk, ws_bill_addr_sk, ws_item_sk, ws_ext_sales_price);

-- helps in children item category check, no need ot look into the main table
create index idx_item_category_id on item (i_category, i_item_id);


-- DROP INDEX idx_ss_date_addr_item_price ON store_sales;
-- DROP INDEX idx_cs_date_addr_item_price ON catalog_sales;
-- DROP INDEX idx_ws_date_addr_item_price ON web_sales;
-- DROP INDEX idx_item_category_id ON item;





with ss as (
    select
        i_item_id, sum(ss_ext_sales_price) total_sales
    from date_dim d
        straight_join store_sales s
            on s.ss_sold_date_sk = d.d_date_sk
        straight_join customer_address ca
            on s.ss_addr_sk = ca.ca_address_sk
        straight_join item i
            on s.ss_item_sk = i.i_item_sk
    where
        i_item_id in (
            select i_item_id
            from item
            where i_category in ('Children')
        )
        and d_year = 2000
        and d_moy = 9
        and ca_gmt_offset = -6
    group by i_item_id
),
cs as (
    select
        i_item_id, sum(cs_ext_sales_price) total_sales
    from date_dim d
        straight_join catalog_sales c
            on c.cs_sold_date_sk = d.d_date_sk
        straight_join customer_address ca
            on c.cs_bill_addr_sk = ca.ca_address_sk
        straight_join item i
            on c.cs_item_sk = i.i_item_sk
    where
        i_item_id in (
            select i_item_id
            from item
            where i_category in ('Children')
        )
        and d_year = 2000
        and d_moy = 9
        and ca_gmt_offset = -6
    group by i_item_id
),
ws as (
    select
        i_item_id, sum(ws_ext_sales_price) total_sales
    from date_dim d
        straight_join web_sales w
            on w.ws_sold_date_sk = d.d_date_sk
        straight_join customer_address ca
            on w.ws_bill_addr_sk = ca.ca_address_sk
        straight_join item i
            on w.ws_item_sk = i.i_item_sk
    where
        i_item_id in (
            select i_item_id
            from item
            where i_category in ('Children')
        )
        and d_year = 2000
        and d_moy = 9
        and ca_gmt_offset = -6
    group by i_item_id
)
select
    i_item_id,
    sum(total_sales) total_sales
from (
    select * from ss
    union all
    select * from cs
    union all
    select * from ws
) tmp1
group by i_item_id
order by i_item_id, total_sales
limit 100;