#!/usr/bin/env bash
#
# reproduce.sh — one command to reproduce the TPC-DS benchmark in Docker.
#
#   ./reproduce.sh                 quick profile  (SF=1, 32K pages, ~20 min)
#   ./reproduce.sh smoke           low-memory SF=1 setup + four-query check
#   ./reproduce.sh full            SF=4, 32K pages, 8G pool (~3 h, needs 12G RAM)
#   ./reproduce.sh quick SCALE=2 PAGE_SIZE=32
#
# Everything runs inside a Linux container.  The repository is mounted
# read-only. Results land in ./results/ (smoke: ./results/smoke/).
# Smoke still generates and loads the full SF=1 dataset on its first run.
# quick/full retain the reference memory settings; smoke uses a 1G pool.
#
# By default a run measures BOTH of the project's contributions together:
# the tuned server settings AND the team's optimized queries
# (queries/tuned/, 33 of the 40 rewritten).  To separate them, hold one
# fixed -- QUERYSET picks the SQL, TUNED picks the server settings:
#
#   ./reproduce.sh quick QUERYSET=tier45 TUNED=both   # server tuning alone
#   ./reproduce.sh quick QUERYSET=tuned  TUNED=tuned  # + the query rewrites
set -Eeuo pipefail

cd "$(dirname "$0")"
PROFILE=quick
if [[ $# -gt 0 && "$1" != *=* ]]; then PROFILE="$1"; shift; fi

case "$PROFILE" in
  quick|full|smoke) ;;
  -h|--help|help)
    awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
  *) echo "unknown profile '$PROFILE' (use quick, full or smoke, or --help)" >&2; exit 1 ;;
esac

# Resolve once: explicit arguments > shell environment > profile defaults.
# Never eval user input or allow arbitrary shell variables to be overwritten.
. "$PWD/docker/profiles.sh"
for kv in "$@"; do
  [[ "$kv" == *=* ]] || { echo "expected KEY=VALUE, got '$kv'" >&2; exit 1; }
  key="${kv%%=*}"; value="${kv#*=}"
  case " $TPCDS_CONFIG_KEYS RESULTS_DIR VOLUME " in
    *" $key "*) ;;
    *) echo "unknown option '$key' (options are case-sensitive, e.g. BUFFER_POOL=4G)" >&2; exit 1 ;;
  esac
  [[ -n "$key" && -n "$value" ]] || { echo "expected a nonempty KEY=VALUE, got '$kv'" >&2; exit 1; }
  printf -v "$key" '%s' "$value"
done
tpcds_profile_defaults
tpcds_validate_config
ENVARGS=()
for key in $TPCDS_CONFIG_KEYS; do ENVARGS+=(-e "$key=${!key}"); done

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but not installed: https://docs.docker.com/get-docker/" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running — start Docker Desktop or dockerd." >&2
  exit 1
fi

# Check before building images or creating output directories. Docker reports
# daemon/VM capacity, not currently free RAM; this estimate is not a peak cap.
AVAIL=$(docker info --format '{{.MemTotal}}' 2>/dev/null) || {
  echo "ERROR: could not read Docker's memory capacity" >&2; exit 1; }
if [[ ! "$AVAIL" =~ ^[0-9]+$ ]] || (( AVAIL == 0 )); then
  echo "ERROR: Docker returned an invalid memory capacity: '$AVAIL'" >&2
  exit 1
fi
NEED=$(tpcds_memory_budget)
echo "==> profile $PROFILE: buffer pool $BUFFER_POOL; Docker capacity $((AVAIL/1048576)) MiB; estimated budget $((NEED/1048576)) MiB"
if (( AVAIL < NEED )); then
  cat >&2 <<EOF

ERROR: Docker reports $((AVAIL/1048576)) MiB; the requested $PROFILE settings need an estimated $((NEED/1048576)) MiB.
  BUFFER_POOL=$BUFFER_POOL, Aria=$ARIA_PAGECACHE_BUFFER_SIZE, temporary-table limit=$TMP_TABLE_SIZE.
  This includes execution buffers and headroom, not just the InnoDB pool.
  Allow more memory for other workloads and concurrent temporary tables.

  For a low-memory functional check: ./reproduce.sh smoke
  To change a run explicitly: ./reproduce.sh $PROFILE BUFFER_POOL=1G
  quick/full also retain large Aria/temp buffers; smoke lowers all of these.
  Docker Desktop users can increase VM memory in Settings > Resources.
EOF
  exit 1
fi

IMAGE=tpcds-mariadb
# Where per-query JSON lands.  run-scales.sh points this at a per-scale
# directory so one scale factor's results do not overwrite another's.
RESULTS="${RESULTS_DIR:-$PWD/results}"
if [[ "$PROFILE" == smoke ]]; then RESULTS="$RESULTS/smoke"; fi
mkdir -p "$RESULTS"
RESULTS=$(cd "$RESULTS" && pwd)

# A named volume holds the generated data and the database between runs, so a
# second run skips generation and loading.  Remove it with:
#   docker volume rm tpcds-data
#
# run-scales.sh overrides this per scale factor (tpcds-data-sf1, -sf2, ...)
# so that re-running one scale does not force every other to be regenerated.
# Each retained volume includes generated files and the loaded database;
# allow substantial disk space (see docker/README.md).
if [[ "$PROFILE" == smoke ]]; then
  VOLUME="${VOLUME:-tpcds-smoke-data}"
else
  VOLUME="${VOLUME:-tpcds-data}"
fi

echo "==> building image (first run compiles the toolchain layer; later runs are cached)"
docker build -q -t "$IMAGE" \
  --build-arg "MARIADB_TAG=${MARIADB_TAG:-13.0.2}" \
  docker/ >/dev/null

# -t only when stdout is a terminal: with it, the script cannot be piped,
# redirected, or run from CI ("cannot attach stdin to a TTY-enabled container").
TTYARGS=()
[[ -t 0 && -t 1 ]] && TTYARGS=(-it)

echo "==> running profile '$PROFILE' (results -> $RESULTS; volume $VOLUME)"
exec docker run --rm "${TTYARGS[@]+"${TTYARGS[@]}"}" \
  -e "PROFILE=$PROFILE" "${ENVARGS[@]+"${ENVARGS[@]}"}" \
  -v "$PWD:/project:ro" \
  -v "$RESULTS:/results" \
  -v "$VOLUME:/data" \
  --name "tpcds-run-$$" \
  "$IMAGE"
