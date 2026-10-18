-- First index created 
-- Takes up extra space as ws_bill_customer_sk is not required
create index idx_ws_date_item_cust
  on web_sales (ws_sold_date_sk, ws_item_sk, ws_bill_customer_sk, ws_net_paid);

drop index idx_ws_date_item_cust on web_sales;

-- New index created and being useda
CREATE INDEX idx_ws_date_item_paid
ON web_sales (
    ws_sold_date_sk,
    ws_item_sk,
    ws_net_paid
);

drop index idx_ws_date_item_paid on web_sales;

