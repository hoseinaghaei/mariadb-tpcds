SELECT COUNT(*) AS customer_rows, COUNT(DISTINCT c_customer_id) AS distinct_customer_ids, SUM(c_customer_id IS NULL) AS null_ids FROM customer;
