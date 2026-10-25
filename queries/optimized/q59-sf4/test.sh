#!/bin/bash
#
# test.sh [variant.sql ...] — time q59 variants against the original and check
# their output is identical.
#
# Runs on the 32K / SF=4 instance under the exact T1 configuration, where the
# original currently takes about 155-170s.
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
DIR=$REPO/queries/optimized/q59-sf4
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

run() {   # $1 = label, $2 = sql file
  local sql t out
  # strip -- comment lines BEFORE collapsing newlines: otherwise a leading
  # comment swallows the whole query once it is all on one line
  sql=$(grep -v '^[[:space:]]*--' "$2" | tr '\n' ' ' | sed 's/;[[:space:]]*$//')
  out=/tmp/q59-$(basename "$2" .sql).out
  t=$( { /usr/bin/time -p $CLI -B tpcds -e "$PRE $sql" > "$out"; } 2>&1 | awk '/real/{print $2}' )
  printf '  %-34s %8.1fs  rows=%-5s md5=%s\n' "$1" "$t" \
    "$(( $(wc -l < "$out") - 1 ))" "$(md5 -q "$out" | cut -c1-12)"
}

echo "q59 at SF=4 / 32K / T1 config"
run "original" "$REPO/queries/mariadb/query59.sql"
for f in "${@:-$DIR/query59_v1_weekfilter.sql}"; do
  run "$(basename "$f" .sql)" "$f"
done

echo
echo "output comparison against the original:"
ORIG=/tmp/q59-query59.out
for f in "${@:-$DIR/query59_v1_weekfilter.sql}"; do
  o=/tmp/q59-$(basename "$f" .sql).out
  if cmp -s "$ORIG" "$o"; then
    echo "  $(basename "$f" .sql): IDENTICAL"
  elif diff <(sort "$ORIG") <(sort "$o") >/dev/null; then
    echo "  $(basename "$f" .sql): same rows, different order"
  else
    echo "  $(basename "$f" .sql): ** DIFFERS **"
    diff "$ORIG" "$o" | head -4 | sed 's/^/      /'
  fi
done
