#!/bin/bash
#
# analyze-v3.sh -- is there anything left in q23 after the v3 rewrite?
#
# v3 brought 173.6s down to ~45s.  The original's problem was
# frequent_ss_items being split-materialised 55,882 times; this checks
# whether the CTEs are still being recomputed per outer row (in which case
# split_materialized=off is worth another look, now that materialising them
# once is cheap) or whether the remaining time has moved somewhere else.
#
# Loop counts, not clocks: four identical runs of the original measured
# 171.5-204.4s on this host, so timing cannot resolve what is left.
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$LAB/my-32k-sf4-t1exact.cnf" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
}

python3 - "$REPO/queries/optimized/q23-sf4/query23_v3_densekeys.sql" <<'SPLIT'
import sys
# strip comments first: a ';' inside one would split mid-comment, which is
# exactly how q4_BEST was broken once before
body = "\n".join(l for l in open(sys.argv[1]) if not l.lstrip().startswith('--'))
parts = [p.strip() for p in body.split(';') if p.strip()]
for i, p in enumerate(parts, 1):
    open(f'/tmp/q23v3-stmt{i}.sql', 'w').write(p + ';\n')
print(f"  split into {len(parts)} statements")
SPLIT

for i in 1 2; do
  echo "=== v3 statement $i"
  SQL=$(sed 's/;[[:space:]]*$//' "/tmp/q23v3-stmt$i.sql" | tr '\n' ' ')
  mariadb --socket="$SOCK" --user="$ME" -N -B tpcds \
    -e "$PRE ANALYZE FORMAT=JSON $SQL" > "/tmp/q23v3-an$i.json" 2>&1
  python3 - "$i" <<'PY'
import json, sys
i = sys.argv[1]
raw = open(f'/tmp/q23v3-an{i}.json').read()
raw = raw.replace('\\n', '\n').replace('\\"', '"').replace('\\t', '\t')
try:
    d = json.loads(raw[raw.index('{'):raw.rindex('}') + 1])
except Exception as e:
    print(f"  could not parse: {e}"); raise SystemExit
rows = []
def walk(o, parent=""):
    if isinstance(o, dict):
        t = o.get('r_total_time_ms')
        if t is not None:
            rows.append((float(t), str(o.get('table_name') or parent)[:34],
                         o.get('r_loops'), o.get('r_rows'), str(o.get('key', ''))[:26]))
        for k, v in o.items():
            walk(v, k if k not in ('table', 'query_block', 'nested_loop') else parent)
    elif isinstance(o, list):
        for v in o: walk(v, parent)
walk(d)
rows.sort(reverse=True)
print(f"  {'ms':>9}  {'node':<34} {'loops':>8} {'rows':>12}  key")
for t, n, l, r, k in rows[:10]:
    print(f"  {t:>9,.0f}  {n:<34} {str(l):>8} {str(r):>12}  {k}")
PY
done
