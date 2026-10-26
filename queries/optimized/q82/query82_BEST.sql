SELECT STRAIGHT_JOIN
    i.i_item_id,
    i.i_item_desc,
    i.i_current_price
FROM date_dim d
JOIN inventory inv
  ON inv.inv_date_sk = d.d_date_sk
JOIN item i
  ON i.i_item_sk = inv.inv_item_sk
WHERE i.i_current_price BETWEEN 33 AND 63
  AND i.i_manufact_id IN (306, 845, 203, 671)
  AND inv.inv_quantity_on_hand BETWEEN 100 AND 500
  AND d.d_date BETWEEN CAST('2000-01-15' AS DATE)
                   AND CAST('2000-01-15' AS DATE) + INTERVAL 60 DAY
  AND 1 = (
      SELECT 1
      FROM store_sales ss
      WHERE ss.ss_item_sk = i.i_item_sk
      LIMIT 1
  )
GROUP BY i.i_item_id, i.i_item_desc, i.i_current_price
ORDER BY i.i_item_id
LIMIT 100;
