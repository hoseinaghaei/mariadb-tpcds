#!/bin/bash
#
# verify-tuned.sh [query ...] — check each tuned file returns what the
# adapted TPC-DS original returns, at SF=4.
#
# Substituting the team's optimized queries is only safe if the answers are
# unchanged, and several of those files had defects when last checked: a typo
# that stopped one running at all, a transposed select list, temp tables that
# only work when the file is fed whole.  This runs both and compares.
#
# Reports: IDENTICAL, row-order only (the ORDER BY is not a total order), or
# DIFFERS with the row counts.
#
# THE TIMES PRINTED HERE ARE NOT SPEEDUPS.  Each pair runs the original first
# and the tuned file second, so the second one inherits a warm buffer pool.
# q66 is the control: `queries/tuned/query66.sql` IS the original, unchanged,
# and it still prints 17.30s against 7.37s -- a 2.3x "gain" from cache alone.
# For a real before/after use queries/optimized/compare-rewrite.sh, which
# interleaves the passes and takes best-of-N.
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
CNF="$LAB/my-32k-sf4-t1exact.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$CNF" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
}
CLI="mariadb --socket=$SOCK --user=$ME"

if [[ $# -gt 0 ]]; then QS=("$@"); else
  QS=($(ls "$REPO"/queries/tuned/query*.sql | sed 's/.*query//;s/\.sql//' | sort -n))
fi

ok=0; order=0; diff=0; err=0
for n in "${QS[@]}"; do
  src=$(grep -m1 '^-- source:' "$REPO/queries/tuned/query$n.sql" | sed 's|-- source: ||;s| .*||')
  case "$src" in */mariadb/*) tag="original" ;; *) tag="optimized" ;; esac

  # the adapted original, statements fed together
  osql=$(grep -v '^[[:space:]]*--' "$REPO/queries/mariadb/query$n.sql" | tr '\n' ' ')
  to=$( { /usr/bin/time -p $CLI -B tpcds -e "$PRE $osql" > "/tmp/v-$n-orig.out"; } 2>&1 | awk '/real/{print $2}' ) || true
  # the tuned file, fed whole so its SET and temp tables work
  tt=$( { /usr/bin/time -p $CLI -B tpcds < "$REPO/queries/tuned/query$n.sql" > "/tmp/v-$n-tuned.out"; } 2>&1 | awk '/real/{print $2}' ) || true

  a=$(( $(wc -l < "/tmp/v-$n-orig.out") - 1 )); b=$(( $(wc -l < "/tmp/v-$n-tuned.out") - 1 ))
  # Compare BEFORE testing for emptiness: with -B, MariaDB prints no header
  # for a zero-row result, so an empty file is indistinguishable from a
  # failure by size.  q54 returns no rows at all at SF=4 in BOTH versions,
  # and checking emptiness first reported that identical pair as an error.
  if cmp -s "/tmp/v-$n-orig.out" "/tmp/v-$n-tuned.out"; then
    if [[ "$b" -lt 0 ]]; then verdict="both empty - nothing to compare"; err=$((err+1))
    else verdict="IDENTICAL"; ok=$((ok+1)); fi
  elif [[ "$b" -lt 0 ]]; then verdict="** TUNED EMPTY/ERROR **"; err=$((err+1))
  elif diff -q <(sort "/tmp/v-$n-orig.out") <(sort "/tmp/v-$n-tuned.out") >/dev/null; then
    verdict="row order only"; order=$((order+1))
  else verdict="** DIFFERS ** ($a vs $b rows)"; diff=$((diff+1)); fi

  printf '  q%-4s %-10s orig %7ss  tuned %7ss   %s\n' "$n" "$tag" "${to:-?}" "${tt:-?}" "$verdict"
done
echo
echo "  identical $ok   row-order-only $order   DIFFERS $diff   errors $err"
