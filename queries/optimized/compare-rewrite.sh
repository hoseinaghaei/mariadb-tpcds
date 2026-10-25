#!/bin/bash
#
# compare-rewrite.sh <n> <rewrite.sql> [passes] -- time a rewrite against the
# adapted TPC-DS original at SF=4 and prove the answer did not change.
#
# Interleaved, not batched: this host drifts over minutes, so running all the
# "before" passes and then all the "after" passes would charge the drift to
# the rewrite.  Alternating them cancels it.
#
# Both sides are fed the same PIPES_AS_CONCAT preamble -- without it ANSI `||`
# parses as logical OR and queries like q66 silently return wrong rows -- and
# both are fed whole, so a rewrite may contain its own SET statements.
#
# rc is checked per run: a rewrite that errors out produces an empty result
# fast, which would otherwise read as a spectacular speedup.
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"

N=${1:?usage: compare-rewrite.sh <n> <rewrite.sql> [passes] [baseline.sql]}
NEW=${2:?usage: compare-rewrite.sh <n> <rewrite.sql> [passes] [baseline.sql]}
PASSES=${3:-3}
# Baseline defaults to the adapted TPC-DS original, but can be any file --
# useful for A/B-ing two variants of the same query against each other, e.g.
# one tuned file with a contributor's SET SESSION lines and one without.
OLD=${4:-"$REPO/queries/mariadb/query$N.sql"}

[[ -f "$OLD" ]] || { echo "no such original: $OLD" >&2; exit 1; }
[[ -f "$NEW" ]] || { echo "no such rewrite: $NEW" >&2; exit 1; }

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$LAB/my-32k-sf4-t1exact.cnf" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
}

now() { python3 -c 'import time;print(time.time())'; }

# Prints "<elapsed> <rc>" on one line.  It must not set a variable for the
# caller to read: the caller reads it through $( ), which is a subshell, so
# any assignment made in here would be discarded and `set -u` would then kill
# the script on the first read.
run() {   # $1 tag  $2 file
  local t0 t1 rc=0
  t0=$(now)
  { echo "$PRE"; cat "$2"; } | mariadb --socket="$SOCK" --user="$ME" -B tpcds \
    > "/tmp/cmp-$N-$1.out" 2>"/tmp/cmp-$N-$1.err" || rc=$?
  t1=$(now)
  echo "$(python3 -c "print(f'{$t1-$t0:.1f}')") $rc"
}

echo "=== q$N   original vs $(basename "$NEW")   ${PASSES} interleaved passes"
declare -a OT NT
for p in $(seq 1 "$PASSES"); do
  read -r e orc <<<"$(run orig "$OLD")"; OT+=("$e")
  read -r f nrc <<<"$(run new  "$NEW")"; NT+=("$f")
  printf '  pass %s   orig %7ss (rc=%s)   new %7ss (rc=%s)\n' "$p" "$e" "$orc" "$f" "$nrc"
  if [[ "$orc" != 0 || "$nrc" != 0 ]]; then
    echo "  -- stderr --"; head -5 "/tmp/cmp-$N-orig.err" "/tmp/cmp-$N-new.err"
  fi
done

python3 - "$N" "${OT[*]}" "${NT[*]}" <<'PY'
import sys
n, o, t = sys.argv[1], [float(x) for x in sys.argv[2].split()], [float(x) for x in sys.argv[3].split()]
bo, bt = min(o), min(t)
print(f"\n  q{n}  best-of orig {bo:.1f}s   best-of new {bt:.1f}s   "
      f"{'speedup' if bt < bo else 'SLOWDOWN'} {bo/bt:.2f}x" if bt else "")
PY

echo
a="/tmp/cmp-$N-orig.out"; b="/tmp/cmp-$N-new.out"
ao=$(( $(wc -l < "$a") )); bo=$(( $(wc -l < "$b") ))
if cmp -s "$a" "$b"; then
  echo "  OUTPUT: IDENTICAL ($ao lines incl. header)"
elif diff -q <(sort "$a") <(sort "$b") >/dev/null; then
  echo "  OUTPUT: same rows, different order ($ao lines)"
else
  echo "  OUTPUT: ** DIFFERS **  orig $ao lines, new $bo lines"
  diff "$a" "$b" | head -20
fi
