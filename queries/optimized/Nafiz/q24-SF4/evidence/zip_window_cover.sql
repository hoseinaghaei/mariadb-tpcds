with ssales as
(select c_last_name
      ,c_first_name
      ,s_store_name
      ,ca_state
      ,s_state
      ,i_color
      ,i_current_price
      ,i_manager_id
      ,i_units
      ,i_size
      ,sum(ss_ext_sales_price) netpaid
FROM store
STRAIGHT_JOIN customer_address ON s_zip=ca_zip
STRAIGHT_JOIN customer ON c_current_addr_sk=ca_address_sk
STRAIGHT_JOIN store_sales ON ss_customer_sk=c_customer_sk AND ss_store_sk=s_store_sk
STRAIGHT_JOIN store_returns ON ss_ticket_number=sr_ticket_number AND ss_item_sk=sr_item_sk
STRAIGHT_JOIN item ON ss_item_sk=i_item_sk
where ss_ticket_number = sr_ticket_number
  and ss_item_sk = sr_item_sk
  and ss_customer_sk = c_customer_sk
  and ss_item_sk = i_item_sk
  and ss_store_sk = s_store_sk
  and c_current_addr_sk = ca_address_sk
  and c_birth_country <> upper(ca_country)
  and s_zip = ca_zip
and s_market_id=10
group by c_last_name
        ,c_first_name
        ,s_store_name
        ,ca_state
        ,s_state
        ,i_color
        ,i_current_price
        ,i_manager_id
        ,i_units
        ,i_size), with_threshold AS (SELECT ssales.*,0.05*AVG(netpaid) OVER () threshold FROM ssales)
select c_last_name
      ,c_first_name
      ,s_store_name
      ,sum(netpaid) paid
from with_threshold
where i_color = 'sky'
group by c_last_name
        ,c_first_name
        ,s_store_name
having sum(netpaid) > MAX(threshold)
order by c_last_name
        ,c_first_name
        ,s_store_name
;


with ssales as
(select c_last_name
      ,c_first_name
      ,s_store_name
      ,ca_state
      ,s_state
      ,i_color
      ,i_current_price
      ,i_manager_id
      ,i_units
      ,i_size
      ,sum(ss_ext_sales_price) netpaid
FROM store
STRAIGHT_JOIN customer_address ON s_zip=ca_zip
STRAIGHT_JOIN customer ON c_current_addr_sk=ca_address_sk
STRAIGHT_JOIN store_sales ON ss_customer_sk=c_customer_sk AND ss_store_sk=s_store_sk
STRAIGHT_JOIN store_returns ON ss_ticket_number=sr_ticket_number AND ss_item_sk=sr_item_sk
STRAIGHT_JOIN item ON ss_item_sk=i_item_sk
where ss_ticket_number = sr_ticket_number
  and ss_item_sk = sr_item_sk
  and ss_customer_sk = c_customer_sk
  and ss_item_sk = i_item_sk
  and ss_store_sk = s_store_sk
  and c_current_addr_sk = ca_address_sk
  and c_birth_country <> upper(ca_country)
  and s_zip = ca_zip
  and s_market_id = 10
group by c_last_name
        ,c_first_name
        ,s_store_name
        ,ca_state
        ,s_state
        ,i_color
        ,i_current_price
        ,i_manager_id
        ,i_units
        ,i_size), with_threshold AS (SELECT ssales.*,0.05*AVG(netpaid) OVER () threshold FROM ssales)
select c_last_name
      ,c_first_name
      ,s_store_name
      ,sum(netpaid) paid
from with_threshold
where i_color = 'slate'
group by c_last_name
        ,c_first_name
        ,s_store_name
having sum(netpaid) > MAX(threshold)
order by c_last_name
        ,c_first_name
        ,s_store_name
;