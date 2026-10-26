-- Small, deliberately nonempty Q82 test input. Creates only session-local tables.
-- Concatenate this setup, query82_v0.sql and a candidate SQL file in one session.
-- Expected original output: four rows (A, B, C, K), including a NULL description.
-- This is test input, not a performance dataset or a recorded successful test.

CREATE TEMPORARY TABLE item (
    i_item_sk BIGINT PRIMARY KEY,
    i_item_id CHAR(16),
    i_item_desc VARCHAR(200),
    i_current_price DECIMAL(7,2),
    i_manufact_id BIGINT
);
CREATE TEMPORARY TABLE inventory (
    inv_date_sk BIGINT,
    inv_item_sk BIGINT,
    inv_warehouse_sk BIGINT,
    inv_quantity_on_hand BIGINT,
    PRIMARY KEY (inv_date_sk, inv_item_sk, inv_warehouse_sk)
);
CREATE TEMPORARY TABLE date_dim (
    d_date_sk BIGINT PRIMARY KEY,
    d_date DATE
);
CREATE TEMPORARY TABLE store_sales (
    ss_item_sk BIGINT,
    ss_ticket_number BIGINT,
    PRIMARY KEY (ss_item_sk, ss_ticket_number)
);

INSERT INTO date_dim VALUES
    (1, '2000-01-15'),
    (2, DATE_ADD('2000-01-15', INTERVAL 60 DAY)),
    (3, DATE_SUB('2000-01-15', INTERVAL 1 DAY)),
    (4, DATE_ADD('2000-01-15', INTERVAL 61 DAY));

INSERT INTO item VALUES
    (1,  'A', 'same projected item', 40.00, 306),
    (2,  'A', 'same projected item', 40.00, 306),
    (3,  'B', 'lower price and quantity bounds', 33.00, 845),
    (4,  'C', 'upper price and quantity bounds', 63.00, 203),
    (5,  'D', 'never sold', 40.00, 306),
    (6,  'E', 'no inventory observation', 40.00, 306),
    (7,  'F', 'quantity too low', 40.00, 306),
    (8,  'G', 'quantity too high', 40.00, 306),
    (9,  'H', 'wrong manufacturer', 40.00, 999),
    (10, 'I', 'price too low', 32.99, 306),
    (11, 'J', 'price too high', 63.01, 306),
    (12, 'N', 'NULL price', NULL, 306),
    (13, 'O', 'orphan inventory date', 40.00, 306),
    (14, 'P', 'NULL quantity', 40.00, 306),
    (15, 'K', NULL, 40.00, 671),
    (16, 'L', 'before interval', 40.00, 306),
    (17, 'M', 'after interval', 40.00, 306);

INSERT INTO inventory VALUES
    (1, 1, 1, 100), (1, 1, 2, 500), (2, 1, 1, 200),
    (1, 2, 1, 300), (1, 3, 1, 100), (2, 4, 1, 500),
    (1, 5, 1, 200), (1, 7, 1, 99), (1, 8, 1, 501),
    (1, 9, 1, 200), (1, 10, 1, 200), (1, 11, 1, 200),
    (1, 12, 1, 200), (999, 13, 1, 200), (1, 14, 1, NULL),
    (1, 15, 1, 200), (3, 16, 1, 200), (4, 17, 1, 200);

INSERT INTO store_sales VALUES
    (1, 101), (1, 102), (1, 103), (2, 201), (3, 301), (4, 401),
    (6, 601), (7, 701), (8, 801), (9, 901), (10, 1001), (11, 1101),
    (12, 1201), (13, 1301), (14, 1401), (15, 1501), (16, 1601), (17, 1701),
    (99, 9901);
