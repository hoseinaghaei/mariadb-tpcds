-- Add only the measured Q10 county index; run outside query timing.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q10_county ON customer_address (ca_county);
ALTER TABLE customer_address ALTER INDEX idx_nf_q10_county NOT IGNORED;
ANALYZE TABLE customer_address;
