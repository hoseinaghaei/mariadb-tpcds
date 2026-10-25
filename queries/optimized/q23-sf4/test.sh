#!/bin/bash
# test.sh — time q23 variants against the original at SF=4 and diff the output.
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

OSQL=$(grep -v '^[[:space:]]*--' "$REPO/queries/mariadb/query23.sql" | tr '\n' ' ')
printf '  %-28s ' "original"
T=$( { /usr/bin/time -p $CLI -B tpcds -e "$PRE $OSQL" > /tmp/q23-orig.out; } 2>&1 | awk '/real/{print $2}' )
printf '%8ss  rows=%s\n' "$T" "$(( $(wc -l < /tmp/q23-orig.out) - 1 ))"

for f in "$@"; do
  printf '  %-28s ' "$(basename "$f" .sql)"
  T=$( { /usr/bin/time -p $CLI -B tpcds < "$f" > "/tmp/q23-$(basename "$f" .sql).out"; } 2>&1 | awk '/real/{print $2}' )
  O="/tmp/q23-$(basename "$f" .sql).out"
  printf '%8ss  rows=%-6s ' "$T" "$(( $(wc -l < "$O") - 1 ))"
  if cmp -s /tmp/q23-orig.out "$O"; then echo "IDENTICAL"
  elif diff -q <(sort /tmp/q23-orig.out) <(sort "$O") >/dev/null; then echo "row order only"
  else echo "** DIFFERS **"; diff /tmp/q23-orig.out "$O" | head -3 | sed 's/^/      /'; fi
done
