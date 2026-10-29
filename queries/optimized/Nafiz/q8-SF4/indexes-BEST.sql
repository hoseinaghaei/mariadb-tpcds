-- Q8 SF4 additions to the shared 167-index reference. Run outside query timing.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q8_addr_pref ON customer (c_current_addr_sk,c_preferred_cust_flag);
CREATE INDEX IF NOT EXISTS idx_nf_q8_zip_cover ON customer_address (ca_zip);
ALTER TABLE customer ALTER INDEX idx_nf_q8_addr_pref NOT IGNORED;
ALTER TABLE customer_address ALTER INDEX idx_nf_q8_zip_cover NOT IGNORED;
ANALYZE TABLE customer,customer_address;
