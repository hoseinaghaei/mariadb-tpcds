#!/usr/bin/env python3
"""Build small temporary-table equivalence fixtures; does not connect to a DB."""
import argparse
import hashlib
import json
from pathlib import Path


def literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, str):
        return "'" + value.replace("'", "''") + "'"
    return str(value)


def table(name, columns, rows):
    sql = f"CREATE TEMPORARY TABLE {name} ({columns});\n"
    if rows:
        values = ",\n".join("(" + ",".join(map(literal, row)) + ")" for row in rows)
        sql += f"INSERT INTO {name} VALUES\n{values};\n"
    return sql


def fixture31():
    sql = table("date_dim", "d_date_sk BIGINT PRIMARY KEY,d_qoy BIGINT,d_year BIGINT",
                [(1,1,2001),(2,2,2001),(3,3,2001),(4,1,2000)])
    sql += table("customer_address", "ca_address_sk BIGINT PRIMARY KEY,ca_county VARCHAR(60)",
                 [(1,"A"),(2,"A"),(3,"Missing quarter"),(4,None),
                  (5,"Negative Q3"),(6,"NULL Q3")])
    sales = [(1,1,55),(1,2,45),(2,1,200),(3,2,300),(4,1,9999),
             (1,3,100),(2,3,200),(3,3,300),
             (1,4,100),(2,4,200),(3,4,300),
             (1,5,100),(2,5,200),(3,5,-100),
             (1,6,100),(2,6,200),(3,6,None),
             (1,99,999),(None,1,999)]
    web = [(1,1,100),(2,2,300),(3,1,900),
           (1,3,100),(2,3,300),
           (1,4,100),(2,4,300),(3,4,900),
           (1,5,100),(2,5,300),(3,5,1),
           (1,6,100),(2,6,300),(3,6,900),
           (1,99,999),(None,1,999)]
    sql += table("store_sales", "ss_sold_date_sk BIGINT,ss_addr_sk BIGINT,ss_ext_sales_price DECIMAL(7,2)", sales)
    sql += table("web_sales", "ws_sold_date_sk BIGINT,ws_bill_addr_sk BIGINT,ws_ext_sales_price DECIMAL(7,2)", web)
    return sql, [2], ["missing quarters", "NULL county and totals", "duplicate county addresses",
                     "negative third-quarter total", "out-of-year and orphan rows"]


def fixture4():
    sql = table("date_dim", "d_date_sk BIGINT PRIMARY KEY,d_year BIGINT",
                [(1,2001),(2,2002),(3,2000)])
    columns = ("c_customer_sk BIGINT PRIMARY KEY,c_customer_id CHAR(16) UNIQUE,"
               "c_first_name CHAR(20),c_last_name CHAR(30),c_preferred_cust_flag CHAR(1),"
               "c_birth_country VARCHAR(20),c_login VARCHAR(13),c_email_address VARCHAR(50)")
    customers = [(i,f"AAAAAAAA{i:08d}",None if i==1 else f"Name{i}",f"Last{i}",
                  "Y","Italy",None if i==1 else f"login{i}",f"person{i}@example.test")
                 for i in range(1,6)]
    sql += table("customer", columns, customers)
    channels = [
        ("store_sales","ss","ss_customer_sk",[(1,100,200),(2,100,200),(3,100,None),(4,100,200),(5,0,200)]),
        ("catalog_sales","cs","cs_bill_customer_sk",[(1,100,300),(2,100,150),(3,100,300),(4,100,"NULL"),(5,100,300)]),
        ("web_sales","ws","ws_bill_customer_sk",[(1,100,200),(2,100,140),(3,100,200),(4,100,200),(5,100,200)]),
    ]
    for name,prefix,key,totals in channels:
        columns = (f"{key} BIGINT,{prefix}_sold_date_sk BIGINT,"
                   f"{prefix}_ext_list_price DECIMAL(7,2),{prefix}_ext_wholesale_cost DECIMAL(7,2),"
                   f"{prefix}_ext_discount_amt DECIMAL(7,2),{prefix}_ext_sales_price DECIMAL(7,2)")
        rows = []
        for customer,y1,y2 in totals:
            rows.append((customer,1,0,0,0,y1*2))
            if y2 is not None:
                rows.append((customer,2,0,0,0,None if y2=="NULL" else y2*2))
        rows += [(1,3,0,0,0,9999),(99,1,0,0,0,200),(99,2,0,0,0,800)]
        sql += table(name,columns,rows)
    return sql,[1],["unique business IDs", "missing second-year group", "NULL second-year measure",
                    "zero first-year denominator", "NULL customer attributes", "orphan customer"]


def fixture39():
    dates = [(i,1998,4 if i<=4 else 5) for i in range(1,9)] + [(9,1999,4)]
    sql = table("date_dim","d_date_sk BIGINT PRIMARY KEY,d_year BIGINT,d_moy BIGINT",dates)
    sql += table("warehouse","w_warehouse_sk BIGINT PRIMARY KEY,w_warehouse_name VARCHAR(20)",
                 [(1,"Same name"),(2,"Same name")])
    sql += table("item","i_item_sk BIGINT PRIMARY KEY",[(i,) for i in range(1,7)])
    rows=[]
    for item,warehouse,april,may in [
        (1,1,[0,0,0,100],[0,0,0,80]),
        (2,1,[0,0,10,30],[0,0,0,40]),
        (3,1,[0,0,0,100],[]),
        (4,1,[0,0,0,0],[0,0,0,0]),
        (5,1,[1],[1]),
        (6,1,[None]*4,[None]*4),
        (1,2,[0,0,0,20],[0,0,0,40]),
        (99,1,[0,0,0,100],[0,0,0,80]),
        (1,99,[0,0,0,100],[0,0,0,80]),
    ]:
        rows += [(i+1,item,warehouse,value) for i,value in enumerate(april)]
        rows += [(i+5,item,warehouse,value) for i,value in enumerate(may)]
    rows.append((9,1,1,9999))
    sql += table("inventory",
                 "inv_date_sk BIGINT,inv_item_sk BIGINT,inv_warehouse_sk BIGINT,inv_quantity_on_hand BIGINT,"
                 "PRIMARY KEY(inv_date_sk,inv_item_sk,inv_warehouse_sk)", rows)
    return sql,[3,2],["both coefficient-of-variation thresholds", "missing month", "zero/NULL mean",
                      "single observation", "same warehouse name with different keys", "orphans"]


def fixture5():
    sql = table("date_dim","d_date_sk BIGINT PRIMARY KEY,d_date DATE",
                [(1,"1998-08-28"),(2,"1998-09-11"),(3,"1998-09-12"),
                 (4,"1998-07-01"),(5,"1998-08-27")])
    sql += table("store","s_store_sk BIGINT PRIMARY KEY,s_store_id CHAR(16)",
                 [(1,"SAME"),(2,"SAME"),(3,"OTHER")])
    sql += table("catalog_page","cp_catalog_page_sk BIGINT PRIMARY KEY,cp_catalog_page_id CHAR(16)",
                 [(1,"P1"),(2,"P2")])
    sql += table("web_site","web_site_sk BIGINT PRIMARY KEY,web_site_id CHAR(16)",
                 [(1,"W1"),(2,"W2")])
    sql += table("store_sales","ss_store_sk BIGINT,ss_sold_date_sk BIGINT,ss_ext_sales_price DECIMAL(7,2),ss_net_profit DECIMAL(7,2)",
                 [(1,1,50,10),(2,2,25,5),(1,3,999,999),(1,None,999,999),
                  (99,1,300,20),(3,1,None,None)])
    sql += table("store_returns","sr_store_sk BIGINT,sr_returned_date_sk BIGINT,sr_return_amt DECIMAL(7,2),sr_net_loss DECIMAL(7,2)",
                 [(1,1,5,1),(3,2,None,None)])
    sql += table("catalog_sales","cs_catalog_page_sk BIGINT,cs_sold_date_sk BIGINT,cs_ext_sales_price DECIMAL(7,2),cs_net_profit DECIMAL(7,2)",
                 [(1,1,100,20),(2,2,None,7),(1,3,500,50)])
    sql += table("catalog_returns","cr_catalog_page_sk BIGINT,cr_returned_date_sk BIGINT,cr_return_amount DECIMAL(7,2),cr_net_loss DECIMAL(7,2)",
                 [(1,1,10,3),(2,2,None,None)])
    sql += table("web_sales","ws_item_sk BIGINT,ws_order_number BIGINT,ws_web_site_sk BIGINT,ws_sold_date_sk BIGINT,ws_ext_sales_price DECIMAL(7,2),ws_net_profit DECIMAL(7,2),PRIMARY KEY(ws_item_sk,ws_order_number)",
                 [(1,100,1,4,500,60),(2,200,2,1,40,8),(3,300,2,2,None,None),(4,400,1,5,99,9)])
    sql += table("web_returns","wr_item_sk BIGINT,wr_order_number BIGINT,wr_returned_date_sk BIGINT,wr_return_amt DECIMAL(7,2),wr_net_loss DECIMAL(7,2)",
                 [(1,100,2,20,4),(99,999,1,999,9),(2,200,3,1000,100),(3,300,2,None,None)])
    return sql,[10],["inclusive endpoints", "return from an older sale", "unmatched return",
                     "duplicate business IDs across store keys", "NULL measures", "rollup rows"]


def fixture51():
    sql = table("date_dim","d_date_sk BIGINT PRIMARY KEY,d_date DATE,d_month_seq BIGINT",
                [(1,"1998-01-01",1176),(2,"1998-01-02",1176),
                 (3,"1998-01-03",1176),(4,"1997-12-31",1175)])
    sql += table("web_sales","ws_item_sk BIGINT,ws_sold_date_sk BIGINT,ws_sales_price DECIMAL(7,2)",
                 [(1,1,4),(1,1,1),(1,3,1),(2,1,10),(2,2,-8),(3,1,None),
                  (4,2,9),(5,1,10),(1,4,999),(None,1,100)])
    sql += table("store_sales","ss_item_sk BIGINT,ss_sold_date_sk BIGINT,ss_sales_price DECIMAL(7,2)",
                 [(1,2,4),(1,3,6),(2,1,5),(2,3,5),(3,2,2),(4,1,None),(4,3,0),
                  (6,1,10),(1,4,1),(None,1,0)])
    return sql,[4],["channel-only dates", "NULL versus zero", "negative increments requiring MAX",
                    "multiple facts per day", "outside-window rows", "NULL item"]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--query",type=int,choices=[4,5,31,39,51],required=True)
    p.add_argument("--baseline",type=Path,required=True)
    p.add_argument("--variant",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    args=p.parse_args()
    setup,expected,cases={4:fixture4,5:fixture5,31:fixture31,39:fixture39,51:fixture51}[args.query]()
    baseline=args.baseline.read_text(encoding="utf-8")
    variant=args.variant.read_text(encoding="utf-8")
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open("x",encoding="utf-8") as out:
        out.write("-- Synthetic equivalence fixture; temporary tables shadow the source tables for this session only.\n")
        out.write(setup+"\n-- Baseline result set(s)\n"+baseline+"\n-- Candidate result set(s)\n"+variant+"\n")
    manifest={"query":args.query,"baseline":str(args.baseline),"variant":str(args.variant),
              "baseline_sha256":hashlib.sha256(baseline.encode()).hexdigest(),
              "variant_sha256":hashlib.sha256(variant.encode()).hexdigest(),
              "expected_rows_per_query":expected,"cases":cases}
    args.output.with_suffix(".json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(manifest,indent=2))


if __name__=="__main__":
    main()
