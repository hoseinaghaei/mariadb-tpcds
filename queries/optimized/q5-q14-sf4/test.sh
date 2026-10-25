#!/bin/bash
#
# test.sh [variant.sql ...] — time q5 / q14 variants at SF=4 against the
# original, and check the output is unchanged.
#
# Runs on the 32K SF=4 instance under the standing configuration
# (sql/tpcds-tuned.cnf).  Baselines there: q14 ~153s, q5 32-60s.
#
# Comment lines are stripped BEFORE newlines are collapsed: a leading --
# comment would otherwise swallow the whole query once it is on one line.
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

run() {   # $1 label, $2 sql file, $3 output file
  local sql t
  sql=$(grep -v '^[[:space:]]*--' "$2" | tr '\n' ' ' | sed 's/;[[:space:]]*$//')
  t=$( { /usr/bin/time -p $CLI -B tpcds -e "$PRE $sql" > "$3"; } 2>&1 | awk '/real/{print $2}' )
  printf '  %-36s %8.1fs  rows=%-6s md5=%s\n' "$1" "$t" \
    "$(( $(wc -l < "$3") - 1 ))" "$(md5 -q "$3" | cut -c1-12)"
}

for q in "${@:-5 14}"; do
  echo "--- query$q"
  run "original" "$REPO/queries/mariadb/query$q.sql" "/tmp/q$q-orig.out"
done
