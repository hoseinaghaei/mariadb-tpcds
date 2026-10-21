select
  -- Bucket 1: quantity 0 to 5
  avg(case when ss_quantity between 0 and 5
            and (ss_list_price between 69 and 79
              or ss_coupon_amt between 10692 and 11692
              or ss_wholesale_cost between 77 and 97)
           then ss_list_price end)            B1_LP,
  count(case when ss_quantity between 0 and 5
              and (ss_list_price between 69 and 79
                or ss_coupon_amt between 10692 and 11692
                or ss_wholesale_cost between 77 and 97)
             then ss_list_price end)          B1_CNT,
  count(distinct case when ss_quantity between 0 and 5
              and (ss_list_price between 69 and 79
                or ss_coupon_amt between 10692 and 11692
                or ss_wholesale_cost between 77 and 97)
             then ss_list_price end)          B1_CNTD,
  -- Bucket 2: quantity 6 to 10
  avg(case when ss_quantity between 6 and 10
            and (ss_list_price between 46 and 56
              or ss_coupon_amt between 15362 and 16362
              or ss_wholesale_cost between 17 and 37)
           then ss_list_price end)            B2_LP,
  count(case when ss_quantity between 6 and 10
              and (ss_list_price between 46 and 56
                or ss_coupon_amt between 15362 and 16362
                or ss_wholesale_cost between 17 and 37)
             then ss_list_price end)          B2_CNT,
  count(distinct case when ss_quantity between 6 and 10
              and (ss_list_price between 46 and 56
                or ss_coupon_amt between 15362 and 16362
                or ss_wholesale_cost between 17 and 37)
             then ss_list_price end)          B2_CNTD,
  -- Bucket 3: quantity 11 to 15
  avg(case when ss_quantity between 11 and 15
            and (ss_list_price between 38 and 48
              or ss_coupon_amt between 7604 and 8604
              or ss_wholesale_cost between 80 and 100)
           then ss_list_price end)            B3_LP,
  count(case when ss_quantity between 11 and 15
              and (ss_list_price between 38 and 48
                or ss_coupon_amt between 7604 and 8604
                or ss_wholesale_cost between 80 and 100)
             then ss_list_price end)          B3_CNT,
  count(distinct case when ss_quantity between 11 and 15
              and (ss_list_price between 38 and 48
                or ss_coupon_amt between 7604 and 8604
                or ss_wholesale_cost between 80 and 100)
             then ss_list_price end)          B3_CNTD,
  -- Bucket 4: quantity 16 to 20
  avg(case when ss_quantity between 16 and 20
            and (ss_list_price between 89 and 99
              or ss_coupon_amt between 8578 and 9578
              or ss_wholesale_cost between 43 and 63)
           then ss_list_price end)            B4_LP,
  count(case when ss_quantity between 16 and 20
              and (ss_list_price between 89 and 99
                or ss_coupon_amt between 8578 and 9578
                or ss_wholesale_cost between 43 and 63)
             then ss_list_price end)          B4_CNT,
  count(distinct case when ss_quantity between 16 and 20
              and (ss_list_price between 89 and 99
                or ss_coupon_amt between 8578 and 9578
                or ss_wholesale_cost between 43 and 63)
             then ss_list_price end)          B4_CNTD,
  -- Bucket 5: quantity 21 to 25
  avg(case when ss_quantity between 21 and 25
            and (ss_list_price between 97 and 107
              or ss_coupon_amt between 12825 and 13825
              or ss_wholesale_cost between 37 and 57)
           then ss_list_price end)            B5_LP,
  count(case when ss_quantity between 21 and 25
              and (ss_list_price between 97 and 107
                or ss_coupon_amt between 12825 and 13825
                or ss_wholesale_cost between 37 and 57)
             then ss_list_price end)          B5_CNT,
  count(distinct case when ss_quantity between 21 and 25
              and (ss_list_price between 97 and 107
                or ss_coupon_amt between 12825 and 13825
                or ss_wholesale_cost between 37 and 57)
             then ss_list_price end)          B5_CNTD,
  -- Bucket 6: quantity 26 to 30
  avg(case when ss_quantity between 26 and 30
            and (ss_list_price between 94 and 104
              or ss_coupon_amt between 5766 and 6766
              or ss_wholesale_cost between 2 and 22)
           then ss_list_price end)            B6_LP,
  count(case when ss_quantity between 26 and 30
              and (ss_list_price between 94 and 104
                or ss_coupon_amt between 5766 and 6766
                or ss_wholesale_cost between 2 and 22)
             then ss_list_price end)          B6_CNT,
  count(distinct case when ss_quantity between 26 and 30
              and (ss_list_price between 94 and 104
                or ss_coupon_amt between 5766 and 6766
                or ss_wholesale_cost between 2 and 22)
             then ss_list_price end)          B6_CNTD
from store_sales
where ss_quantity between 0 and 30;