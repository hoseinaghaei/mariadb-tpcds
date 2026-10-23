CREATE INDEX idx_dd_date    ON date_dim(d_date);       
CREATE INDEX idx_item_price ON item(i_current_price); 


-- Hardware parameter changes 
-- buffer pool: big enough to hold the hot data, e.g. 60-70% of RAM
SET GLOBAL innodb_buffer_pool_size = 8*1024*1024*1024;  

-- to avoid temp tables spilling to disk during GROUP BY
SET SESSION tmp_table_size = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;


