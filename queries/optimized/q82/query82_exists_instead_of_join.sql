SELECT
    i.i_item_id,
    i.i_item_desc,
    i.i_current_price
FROM item i
WHERE
    i.i_current_price BETWEEN 33 AND 63
    AND i.i_manufact_id IN (306, 845, 203, 671)

    AND EXISTS (
        SELECT 1
        FROM inventory inv
        JOIN date_dim d
            ON d.d_date_sk = inv.inv_date_sk
        WHERE
            inv.inv_item_sk = i.i_item_sk
            AND d.d_date BETWEEN '2000-01-15'
                             AND '2000-01-15' + INTERVAL 60 DAY
            AND inv.inv_quantity_on_hand BETWEEN 100 AND 500
    )

    AND EXISTS (
        SELECT 1
        FROM store_sales ss
        WHERE ss.ss_item_sk = i.i_item_sk
    )

GROUP BY
    i.i_item_id,
    i.i_item_desc,
    i.i_current_price
ORDER BY i.i_item_id
LIMIT 100;