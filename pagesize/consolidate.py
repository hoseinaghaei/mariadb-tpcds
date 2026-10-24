#!/usr/bin/env python3
"""Flatten every page-size run into one CSV plus a summary table.

One row per (configuration, query): seconds, rows, md5.  The md5 is what
proves the configurations return the same answers.

Writes pagesize/results/all-runs.csv and prints the summary.
"""
import json, glob, os, csv, re

LAB = "/Users/hosseinaghaei/Desktop/projects/dw/pagesize"
RES = f"{LAB}/results"

# directory name -> (page_kb, sample_pages, pass, scale, indexes)
def describe(d):
    m = re.match(r'(\d+)k(?:-(r2|sf4|full188|stats(\d+)))?$', d)
    if not m:
        return None
    page = int(m.group(1))
    suffix, sample, npass, scale, nidx = m.group(2), 20, 1, 1, 182
    if suffix == 'r2':
        npass = 2
    elif suffix == 'sf4':
        scale, nidx = 4, 188
    elif suffix == 'full188':
        nidx = 188
    elif suffix and suffix.startswith('stats'):
        sample = int(m.group(3))
    return page, sample, npass, scale, nidx


rows, summary = [], []
for d in sorted(os.listdir(RES)):
    if not os.path.isdir(f"{RES}/{d}"):
        continue
    desc = describe(d)
    if not desc:
        continue
    page, sample, npass, scale, nidx = desc
    files = glob.glob(f"{RES}/{d}/query*.json")
    if not files:
        continue
    total, n, errs = 0.0, 0, 0
    for f in files:
        r = json.load(open(f))
        total += r['seconds']
        n += 1
        errs += (r['status'] != 'OK')
        rows.append({'config': d, 'page_kb': page, 'sample_pages': sample,
                     'pass': npass, 'scale': scale, 'indexes': nidx,
                     'query': r['query'], 'seconds': r['seconds'],
                     'status': r['status'], 'rows': r.get('rows', ''),
                     'md5': r.get('md5', '')})
    st = f"{RES}/{d}/_storage.json"
    stor = json.load(open(st)) if os.path.exists(st) else None
    mb = (sum(t['data'] + t['index'] for t in stor['tables']) / 2**20) if stor else None
    summary.append((d, page, sample, npass, scale, n, errs, total, mb))

rows.sort(key=lambda r: (r['scale'], r['page_kb'], r['sample_pages'], r['pass'], r['query']))
out = f"{RES}/all-runs.csv"
with open(out, 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['config', 'page_kb', 'sample_pages', 'pass',
                                       'scale', 'indexes', 'query', 'seconds',
                                       'status', 'rows', 'md5'])
    w.writeheader()
    w.writerows(rows)

print(f"wrote {out}  ({len(rows)} rows, {len(summary)} configurations)\n")
print(f"{'configuration':<16} {'page':>5} {'sample':>7} {'pass':>5} {'SF':>3} "
      f"{'n':>4} {'err':>4} {'total':>10} {'storage':>11}")
print("-" * 78)
for d, page, sample, npass, scale, n, errs, total, mb in sorted(
        summary, key=lambda x: (x[4], x[1], x[2], x[3])):
    print(f"{d:<16} {page:>4}K {sample:>7} {npass:>5} {scale:>3} {n:>4} {errs:>4} "
          f"{total:>9.1f}s {(f'{mb:,.0f} MB' if mb else '—'):>11}")

# cross-configuration answer check
print()
sigs = {}
for r in rows:
    if r['md5']:
        sigs.setdefault((r['scale'], r['query']), set()).add(r['md5'])
bad = {q: s for q, s in sigs.items() if len(s) > 1}
print(f"answer check: {len(sigs) - len(bad)}/{len(sigs)} (query, scale factor) pairs "
      f"return the same md5 in every configuration at that scale")
if bad:
    for (sf, q), s in sorted(bad.items()):
        print(f"  SF={sf} query{q}: {len(s)} distinct results")
