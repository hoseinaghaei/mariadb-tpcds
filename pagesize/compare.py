#!/usr/bin/env python3
"""Compare the four page-size lab runs.

usage: compare.py [page_kb ...]      (default: 8 16 32 64)

Produces the storage table, the correctness cross-check (md5 of every query's
output must agree across page sizes), and the timing comparison with 16K --
InnoDB's default -- as the reference.
"""
import json, os, sys, glob

LAB = "/Users/hosseinaghaei/Desktop/projects/dw/pagesize"
PAGES = sys.argv[1:] or ['8', '16', '32', '64']
REF = '16'


def load(page):
    d = {}
    for f in glob.glob(f"{LAB}/results/{page}k/query*.json"):
        r = json.load(open(f))
        d[r['query']] = r
    st = f"{LAB}/results/{page}k/_storage.json"
    return d, (json.load(open(st)) if os.path.exists(st) else None)


runs = {p: load(p) for p in PAGES}
have = [p for p in PAGES if runs[p][0]]
if not have:
    sys.exit("no results yet")

print("# InnoDB page size: 8K / 16K / 32K / 64K\n")
print("Four standalone instances, identical in every respect but")
print("`innodb_page_size`: same 8 GB buffer pool, same 158 indexes, same")
print("scale-1 dataset, same serial 99-query run, each started cold.\n")

# ---------------------------------------------------------------- storage
print("\n## Storage\n")
sizes = {}
for p in have:
    st = runs[p][1]
    if st:
        d = sum(t['data'] for t in st['tables']) / 2**20
        i = sum(t['index'] for t in st['tables']) / 2**20
        sizes[p] = (d, i, d + i)
ref_total = sizes.get(REF, (0, 0, 0))[2]
print("| page | data | index | total | vs 16K |")
print("|---|---:|---:|---:|---:|")
for p in have:
    if p not in sizes:
        continue
    d, i, t = sizes[p]
    rel = "—" if (p == REF or not ref_total) else f"{(t/ref_total - 1) * 100:+.1f}%"
    print(f"| {p}K | {d:,.0f} MB | {i:,.0f} MB | {t:,.0f} MB | {rel} |")

# ---------------------------------------------------------------- correctness
print("\n## Correctness cross-check\n")
allq = sorted(set().union(*[set(runs[p][0]) for p in have]))
mismatch, errs = [], {}
for n in allq:
    sigs = {}
    for p in have:
        r = runs[p][0].get(n)
        if not r:
            continue
        if r['status'] != 'OK':
            errs.setdefault(n, []).append((p, r.get('detail', '')[:60]))
        else:
            sigs.setdefault(r['md5'], []).append(p)
    if len(sigs) > 1:
        mismatch.append((n, sigs))
ok = len(allq) - len(mismatch) - len(errs)
print(f"- **{ok} of {len(allq)} queries return a byte-identical result on every "
      f"page size.**")
if mismatch:
    print(f"- **{len(mismatch)} differ across page sizes** — page size must "
          f"never change an answer, so each of these is a bug:")
    for n, sigs in mismatch:
        groups = " vs ".join("/".join(f"{p}K" for p in v) for v in sigs.values())
        print(f"  - query{n}: {groups}")
if errs:
    print(f"- {len(errs)} errored:")
    for n, lst in errs.items():
        print(f"  - query{n}: " + "; ".join(f"{p}K {d}" for p, d in lst))

# ---------------------------------------------------------------- timing
print("\n\n## Total runtime\n")
print("| page | 99-query total | vs 16K |")
print("|---|---:|---:|")
tot = {}
for p in have:
    tot[p] = sum(r['seconds'] for r in runs[p][0].values())
for p in have:
    rel = f"{(tot[p]/tot[REF] - 1) * 100:+.1f}%" if REF in tot and p != REF else "—"
    print(f"| {p}K | {tot[p]:,.1f}s | {rel} |")

# ---------------------------------------------------------------- per query
print("\n\n## Per query\n")
print("Queries where page size moved the time by more than 20%, "
      "largest effect first.\n")
print("| query | " + " | ".join(f"{p}K" for p in have) +
      " | best | worst/best |")
print("|---|" + "---:|" * (len(have) + 1) + "---:|")
rows = []
for n in allq:
    ts = {p: runs[p][0][n]['seconds'] for p in have
          if n in runs[p][0] and runs[p][0][n]['status'] == 'OK'}
    if len(ts) != len(have):
        continue
    lo, hi = min(ts.values()), max(ts.values())
    if lo < 0.3:                       # too small to be meaningful
        continue
    rows.append((hi / lo, n, ts, lo))
rows.sort(reverse=True)
for ratio, n, ts, lo in rows:
    if ratio < 1.2:
        continue
    best = [p for p in have if ts[p] == lo][0]
    cells = " | ".join(f"**{ts[p]:.1f}s**" if ts[p] == lo else f"{ts[p]:.1f}s"
                       for p in have)
    print(f"| query{n} | {cells} | {best}K | {ratio:.2f}x |")

print(f"\n{sum(1 for r in rows if r[0] >= 1.2)} of {len(rows)} measurable "
      f"queries move by 20% or more.\n")

# who wins how often
print("\n## Which page size wins\n")
print("| page | queries fastest | queries slowest |")
print("|---|---:|---:|")
win = {p: 0 for p in have}
lose = {p: 0 for p in have}
for _, n, ts, lo in rows:
    hi = max(ts.values())
    for p in have:
        if ts[p] == lo:
            win[p] += 1
        if ts[p] == hi:
            lose[p] += 1
for p in have:
    print(f"| {p}K | {win[p]} | {lose[p]} |")
print(f"\n(of {len(rows)} queries that run long enough to measure)")
