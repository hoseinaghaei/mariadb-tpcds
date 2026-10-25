#!/bin/bash
#
# analyze.sh — where does q23's time actually go?
#
# ANALYZE FORMAT=JSON executes the query and annotates each node with measured
# values (r_total_time_ms, r_loops).  For q59 this was decisive: it showed one
# node running 7,665 times, which no amount of plan-reading had revealed.
#
# q23 is two statements sharing three identical CTEs, so the first thing to
# check is whether those CTEs are being computed more than once.
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
CLI="mariadb --socket=$SOCK --user=$ME"

# q23 has two statements; analyse each separately
python3 - "$REPO/queries/mariadb/query23.sql" <<'SPLIT'
import sys
parts = [p.strip() for p in open(sys.argv[1]).read().split(';') if p.strip()]
for i, p in enumerate(parts, 1):
    open(f'/tmp/q23-stmt{i}.sql', 'w').write(p + ';\n')
print(f"  split into {len(parts)} statements")
SPLIT

for i in 1 2; do
  echo "=== statement $i"
  SQL=$(grep -v '^[[:space:]]*--' "/tmp/q23-stmt$i.sql" | tr '\n' ' ' | sed 's/;[[:space:]]*$//')
  $CLI -N -B tpcds -e "$PRE ANALYZE FORMAT=JSON $SQL" > "/tmp/q23-an$i.json" 2>&1
  python3 - "$i" <<'PY'
import json, sys
i = sys.argv[1]
raw = open(f'/tmp/q23-an{i}.json').read()
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
            rows.append((float(t), str(o.get('table_name') or parent)[:36],
                         o.get('r_loops'), o.get('r_rows'), str(o.get('key', ''))[:22]))
        for k, v in o.items():
            walk(v, k if k not in ('table', 'query_block', 'nested_loop') else parent)
    elif isinstance(o, list):
        for v in o: walk(v, parent)
walk(d)
rows.sort(reverse=True)
print(f"  {'ms':>10}  {'node':<36} {'loops':>8} {'rows':>12}  key")
for t, n, l, r, k in rows[:10]:
    print(f"  {t:>10,.0f}  {n:<36} {str(l):>8} {str(r):>12}  {k}")
PY
done
