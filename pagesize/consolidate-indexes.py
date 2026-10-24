#!/usr/bin/env python3
"""Flatten the per-configuration index-usage TSVs into one wide CSV.

One row per index, one column per configuration holding the rows-read count
(empty = never read in that configuration), plus a verdict:

  always   read in every configuration        -> earning its keep
  never    read in none                       -> dead weight everywhere
  FLIPS    read in some, not others           -> unsafe to judge from one run

Writes pagesize/results/index-usage.csv and prints the summary.
"""
import csv, glob, os, re

LAB = "/Users/hosseinaghaei/Desktop/projects/dw/pagesize"
RES = f"{LAB}/results"


def label(path):
    """idxuse-32k-sf4-stats160.tsv -> '32K/SF4/s160'"""
    b = os.path.basename(path)[len('idxuse-'):-len('.tsv')]
    m = re.match(r'(\d+)k-sf(\d+)(?:-stats(\d+))?', b)
    if not m:
        return b
    return f"{m.group(1)}K/SF{m.group(2)}/s{m.group(3) or '20'}"


files = sorted(glob.glob(f"{RES}/idxuse-*.tsv"))
if not files:
    raise SystemExit("no idxuse-*.tsv files found")

cols, data = [], {}
for f in files:
    name = label(f)
    cols.append(name)
    for line in open(f):
        tbl, idx, reads, status = line.rstrip('\n').split('\t')
        data.setdefault((tbl, idx), {})[name] = int(reads)

rows = []
for (tbl, idx), per in sorted(data.items()):
    present = [per.get(c, 0) for c in cols]
    used = [c for c in cols if per.get(c, 0) > 0]
    verdict = ('always' if len(used) == len(cols)
               else 'never' if not used
               else 'FLIPS')
    rows.append({'table': tbl, 'index': idx, 'verdict': verdict,
                 'peak_reads': max(present),
                 **{c: (per.get(c, 0) or '') for c in cols}})

out = f"{RES}/index-usage.csv"
with open(out, 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['table', 'index', 'verdict', 'peak_reads'] + cols)
    w.writeheader()
    w.writerows(sorted(rows, key=lambda r: (r['verdict'] != 'FLIPS', -r['peak_reads'])))

n = {v: sum(1 for r in rows if r['verdict'] == v) for v in ('always', 'FLIPS', 'never')}
print(f"wrote {out}  ({len(rows)} indexes across {len(cols)} configurations)\n")
print(f"  always read : {n['always']:>4}   earning their keep in every configuration")
print(f"  FLIPS       : {n['FLIPS']:>4}   read in some configurations, not others")
print(f"  never read  : {n['never']:>4}   dead weight in all of them")
print(f"\nconfigurations: {', '.join(cols)}\n")
print("the flips, by peak rows read:")
print(f"  {'index':<50} " + " ".join(f"{c:>14}" for c in cols))
for r in sorted((r for r in rows if r['verdict'] == 'FLIPS'),
                key=lambda r: -r['peak_reads']):
    cells = " ".join(f"{(format(r[c], ',') if r[c] else 'UNUSED'):>14}" for c in cols)
    print(f"  {(r['table'] + '.' + r['index']):<50} {cells}")
