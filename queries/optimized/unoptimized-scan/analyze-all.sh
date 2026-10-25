#!/bin/bash
#
# analyze-all.sh — ANALYZE FORMAT=JSON across the queries nobody has
# optimized, looking for structural defects rather than slow clocks.
#
# Why structure and not timing: on this host q23 measured 171.5-198s across
# four identical runs, and a rewrite measured 162.9-240s.  Timing cannot
# resolve a 15% effect here.  Loop counts and row counts from ANALYZE are
# deterministic, so a node executing 55,882 times is a finding no matter how
# noisy the clock is.
#
# Flags, per query:
#   - any node with r_loops > 100        (repeated materialisation)
#   - the node with the largest r_total_time_ms
#   - full scans (access_type ALL) over the big fact tables
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$LAB/my-32k-sf4-t1exact.cnf" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break; sleep 1; done
}
CLI="mariadb --socket=$SOCK --user=$ME"

# "${@:-a b c}" expands the default as ONE word; build the list explicitly
QS=("$@")
if [ ${#QS[@]} -eq 0 ]; then QS=(68 46 77 70 66 71 87 65 82 58); fi

for n in "${QS[@]}"; do
  SQL=$(grep -v '^[[:space:]]*--' "$REPO/queries/mariadb/query$n.sql" | tr '\n' ' ')
  $CLI -N -B tpcds -e "$PRE ANALYZE FORMAT=JSON $SQL" > "/tmp/an-$n.json" 2>"/tmp/an-$n.err"
  python3 - "$n" <<'PY'
import json, sys
n = sys.argv[1]
raw = open(f'/tmp/an-{n}.json').read().replace('\\n', '\n').replace('\\"', '"').replace('\\t', '\t')
try:
    d = json.loads(raw[raw.index('{'):raw.rindex('}') + 1])
except Exception:
    err = open(f'/tmp/an-{n}.err').read().strip()[:70]
    print(f"  q{n:<4} could not analyse  {err}")
    raise SystemExit
nodes = []
def walk(o, parent=""):
    if isinstance(o, dict):
        if 'r_total_time_ms' in o or 'r_loops' in o:
            nodes.append({
                'name': str(o.get('table_name') or parent)[:28],
                'ms': float(o.get('r_total_time_ms') or 0),
                'loops': o.get('r_loops'),
                'rows': o.get('r_rows'),
                'access': o.get('access_type', ''),
                'key': str(o.get('key', ''))[:20]})
        for k, v in o.items():
            walk(v, k if k not in ('table', 'query_block', 'nested_loop') else parent)
    elif isinstance(o, list):
        for v in o: walk(v, parent)
walk(d)
if not nodes:
    print(f"  q{n:<4} no measured nodes"); raise SystemExit
total = max(x['ms'] for x in nodes)
hot = max(nodes, key=lambda x: x['ms'])
loopy = [x for x in nodes if (x['loops'] or 0) > 100]
scans = [x for x in nodes if x['access'] == 'ALL' and (x['rows'] or 0) > 100000]
flags = []
if loopy:
    w = max(loopy, key=lambda x: x['ms'])
    flags.append(f"REPEATED: {w['name']} x{w['loops']:,} = {w['ms']:,.0f}ms")
for s in scans[:2]:
    flags.append(f"FULL SCAN: {s['name']} {s['rows']:,.0f} rows")
print(f"  q{n:<4} {total:>8,.0f}ms total   hot: {hot['name']} {hot['ms']:,.0f}ms"
      + ("   | " + " | ".join(flags) if flags else "   (nothing structural)"))
PY
done
