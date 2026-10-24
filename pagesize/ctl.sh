#!/bin/bash
#
# ctl.sh start|stop|status <PAGE_KB>
#
# Only one lab instance should run at a time: each reserves an 8 GB buffer
# pool and this machine has 16 GB.
set -Eeuo pipefail

ACTION="${1:?usage: ctl.sh start|stop|status [PAGE_KB]}"
LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)

running() {  # $1 = page kb
  mariadb-admin --socket="$LAB/s$1.sock" --user="$ME" ping >/dev/null 2>&1
}

case "$ACTION" in
  start)
    P="${2:?need page size}"
    running "$P" && { echo "${P}K already running"; exit 0; }
    mariadbd --defaults-file="$LAB/my-${P}k.cnf" >> "$LAB/${P}k.err" 2>&1 &
    for i in $(seq 1 180); do running "$P" && break; sleep 1; done
    running "$P" || { echo "${P}K failed to start, see $LAB/${P}k.err" >&2; exit 1; }
    echo "${P}K up on $LAB/s$P.sock"
    ;;
  stop)
    P="${2:?need page size}"
    running "$P" || { echo "${P}K not running"; exit 0; }
    mariadb-admin --socket="$LAB/s$P.sock" --user="$ME" shutdown
    for i in $(seq 1 120); do running "$P" || break; sleep 1; done
    running "$P" && { echo "${P}K would not shut down" >&2; exit 1; }
    echo "${P}K stopped"
    ;;
  stop-all)
    for P in 4 8 16 32 64; do
      [[ -S "$LAB/s$P.sock" ]] || continue
      running "$P" || continue
      mariadb-admin --socket="$LAB/s$P.sock" --user="$ME" shutdown || true
      echo "${P}K stopped"
    done
    ;;
  status)
    for P in 4 8 16 32 64; do
      [[ -e "$LAB/my-${P}k.cnf" ]] || continue
      if running "$P"; then
        sz=$(mariadb --socket="$LAB/s$P.sock" --user="$ME" -N -B -e \
             "select concat(round(sum(data_length)/1048576),' MB data, ',
                            round(sum(index_length)/1048576),' MB index')
              from information_schema.tables where table_schema='tpcds'" 2>/dev/null)
        echo "${P}K  RUNNING   $sz"
      else
        echo "${P}K  stopped"
      fi
    done
    ;;
  *) echo "usage: ctl.sh start|stop|stop-all|status [PAGE_KB]" >&2; exit 1 ;;
esac
