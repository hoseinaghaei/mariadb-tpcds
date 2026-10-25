#!/bin/bash
#
# run-suggestions.sh — test the five follow-up suggestions one at a time on
# top of T1, in the recommended order (#1, #5, #2, #3, #4).
#
# Each is a separate run against the 32K / SF=4 datadir so its effect is
# attributable.  Settings that live in the config go into a derived .cnf;
# #1 and #2 are globals applied after start, with a reconnect, because
# engine-specific costs are not settable from my.cnf.
#
# Baseline for all of them: T1 = 829.8s (tier 4+5).
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
BASE="$LAB/my-32k-sf4-tuned.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
DISK_RATIO="${DISK_RATIO:-0.2}"

stop_it() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" --user="$ME" shutdown
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
    sleep 1
  done
}
start_it() {   # $1 = cnf
  mariadbd --defaults-file="$1" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "server did not start" >&2; exit 1
}

# $1 tag   $2 extra cnf lines   $3 post-start SQL
run() {
  local tag="$1" extra="$2" sql="$3"
  local cnf="$LAB/my-32k-sf4-$tag.cnf"
  grep -v 'innodb_buffer_pool_dump_pct' "$BASE" > "$cnf"
  printf '\n# --- %s ---\n%s\n' "$tag" "$extra" >> "$cnf"

  stop_it; start_it "$cnf"
  if [[ -n "$sql" ]]; then
    mariadb --socket="$SOCK" --user="$ME" -e "$sql"
  fi
  echo "=== $tag"
  # engine costs do not appear in global_variables; read them where they live
  mariadb --socket="$SOCK" --user="$ME" -N -B -e "
    select concat('    innodb optimizer_disk_read_ratio = ', OPTIMIZER_DISK_READ_RATIO)
    from information_schema.OPTIMIZER_COSTS where ENGINE='InnoDB'" 2>/dev/null || true
  mariadb --socket="$SOCK" --user="$ME" -N -B -e "
    select concat('    use_stat_tables=', @@use_stat_tables,
                  '  mrr_cost_based=', substring_index(substring_index(@@optimizer_switch,'mrr_cost_based=',-1),',',1),
                  '  sort_buffer=', @@sort_buffer_size,
                  '  aria=', @@aria_pagecache_buffer_size,
                  '  join_buf=', @@join_buffer_size)"

  python3 "$LAB/run-bench.py" 32 "$tag" --socket "$SOCK" --timeout 5400 | tail -6
  stop_it
}

SERVICE=$(brew services list 2>/dev/null | awk 'NR>1 && $1 ~ /^mariadb(@|$)/ && $2=="started" {print $1; exit}')
restore() { [[ -n "${SERVICE:-}" ]] && brew services start "$SERVICE" >/dev/null 2>&1 || true; }
trap restore EXIT INT TERM
[[ -n "$SERVICE" ]] && { echo "--- stopping live server for the duration"; brew services stop "$SERVICE" >/dev/null 2>&1; sleep 3; }

# 0  T1 itself, re-measured in this same pass.  The baseline has to come from
#    the same conditions as the five, not from a run made hours earlier under
#    a different OS cache state.
run s0-t1baseline "" ""

# 1  tell the optimizer the data does not fit in memory
run s1-diskratio "" "SET GLOBAL innodb.optimizer_disk_read_ratio = $DISK_RATIO;"

# 5  let MRR be cost-based again (after #1)
run s5-mrrcost "optimizer_switch = 'mrr=on,mrr_cost_based=on'" \
    "SET GLOBAL innodb.optimizer_disk_read_ratio = $DISK_RATIO;"

# 2  re-enable the already-collected histograms (with #1 in place)
run s2-histograms "" \
    "SET GLOBAL innodb.optimizer_disk_read_ratio = $DISK_RATIO;
     SET GLOBAL use_stat_tables = 'PREFERABLY_FOR_QUERIES';"

# 3  move the Aria cache into join buffers
run s3-joinbuffers "aria_pagecache_buffer_size = 256M
join_buffer_size           = 256M
join_buffer_space_limit    = 1G" \
    "SET GLOBAL innodb.optimizer_disk_read_ratio = $DISK_RATIO;"

# 4  bigger sort buffer
run s4-sortbuffer "sort_buffer_size = 256M" \
    "SET GLOBAL innodb.optimizer_disk_read_ratio = $DISK_RATIO;"

echo "=== all five done"
