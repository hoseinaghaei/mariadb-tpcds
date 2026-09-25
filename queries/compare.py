#!/usr/bin/env python3
"""Compare TPC-DS runs: base (no indexes) vs indexed, plus the repo's 83-query subset."""
import glob, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _ansparse import norm, parse_ans, parse_out   # shared, fixed parser

ROOT='/Users/hosseinaghaei/Desktop/projects/dw/queries'
def load(tag):
    d={}
    for f in glob.glob(f'{ROOT}/results/{tag}/*.json'):
        j=json.load(open(f)); d[j['query']]=j
    return d

base=load('base'); idx=load('indexed')
repo=set(int(x) for x in open(f'{ROOT}/repo-subset.txt').read().split())

both=sorted(set(base)&set(idx))
print(f"base run: {len(base)}/99 queries   indexed run: {len(idx)}/99 queries   comparable: {len(both)}\n")

errs_b=[q for q in base if base[q]['status']=='ERROR']
errs_i=[q for q in idx  if idx[q]['status']=='ERROR']
print(f"SQL errors  base: {errs_b or 'none'}   indexed: {errs_i or 'none'}\n")

rows=[]
for q in both:
    b,i=base[q]['seconds'], idx[q]['seconds']
    sp = (b/i) if i>0 else float('inf')
    rows.append((q,b,i,sp))

def total(sel):
    tb=sum(r[1] for r in rows if r[0] in sel); ti=sum(r[2] for r in rows if r[0] in sel)
    return tb,ti

allq=set(both)
tb,ti = total(allq)
print(f"{'ALL 99 QUERIES':<28} base {tb:9.1f}s   indexed {ti:9.1f}s   speedup {tb/ti if ti else 0:5.2f}x")
rb,ri = total(allq & repo)
print(f"{'REPO SUBSET (83 queries)':<28} base {rb:9.1f}s   indexed {ri:9.1f}s   speedup {rb/ri if ri else 0:5.2f}x")
xb,xi = total(allq - repo)
print(f"{'THE 16 REPO EXCLUDED':<28} base {xb:9.1f}s   indexed {xi:9.1f}s   speedup {xb/xi if xi else 0:5.2f}x")

print("\n--- biggest wins ---")
for q,b,i,sp in sorted(rows,key=lambda r:-(r[1]-r[2]))[:10]:
    print(f"  query{q:<3} {b:8.1f}s -> {i:7.1f}s   {sp:6.2f}x   saved {b-i:7.1f}s")
print("\n--- regressions (slower with indexes) ---")
reg=[r for r in sorted(rows,key=lambda r:r[2]-r[1],reverse=True) if r[2]>r[1]*1.15 and r[2]-r[1]>1]
for q,b,i,sp in reg[:10]:
    print(f"  query{q:<3} {b:8.1f}s -> {i:7.1f}s   {sp:6.2f}x")
if not reg: print("  none")

print("\n--- result stability: did any query's row count change? ---")
ch=[(q,base[q].get('rows'),idx[q].get('rows')) for q in both
    if base[q].get('rows')!=idx[q].get('rows')]
print("  "+(str(ch) if ch else "no row count changed - indexes did not alter any result"))
