#!/usr/bin/env bash
#
# reproduce.sh — one command to reproduce the TPC-DS benchmark in Docker.
#
#   ./reproduce.sh                 quick profile  (SF=1, 32K pages, ~20 min)
#   ./reproduce.sh smoke           smallest run (~10 min)
#   ./reproduce.sh full            SF=4, 32K pages, 8G pool (~3 h, needs 12G RAM)
#   ./reproduce.sh quick SCALE=2 PAGE_SIZE=32
#
# Everything runs inside a Linux container.  The repository is mounted
# read-only, so a run cannot modify it; results land in ./results/.
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
PROFILE="${1:-quick}"
shift || true

case "$PROFILE" in
  quick|full|smoke) ;;
  -h|--help|help)
    awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
  *) echo "unknown profile '$PROFILE' (use quick, full or smoke, or --help)" >&2; exit 1 ;;
esac

# Any remaining KEY=VALUE arguments become container environment overrides.
ENVARGS=()
for kv in "$@"; do
  [[ "$kv" == *=* ]] || { echo "expected KEY=VALUE, got '$kv'" >&2; exit 1; }
  ENVARGS+=(-e "$kv")
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but not installed: https://docs.docker.com/get-docker/" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running — start Docker Desktop or dockerd." >&2
  exit 1
fi

IMAGE=tpcds-mariadb
# Where per-query JSON lands.  run-scales.sh points this at a per-scale
# directory so one scale factor's results do not overwrite another's.
RESULTS="${RESULTS_DIR:-$PWD/results}"
mkdir -p "$RESULTS"

# A named volume holds the generated data and the database between runs, so a
# second run skips generation and loading.  Remove it with:
#   docker volume rm tpcds-data
#
# run-scales.sh overrides this per scale factor (tpcds-data-sf1, -sf2, ...)
# so that re-running one scale does not force every other to be regenerated.
# One volume per scale costs disk -- roughly 3 GB at SF=1 and 35 GB at SF=4 --
# and buys back hours of reload and index time on any repeat run.
VOLUME="${VOLUME:-tpcds-data}"

echo "==> building image (first run compiles the toolchain layer; later runs are cached)"
docker build -q -t "$IMAGE" \
  --build-arg "MARIADB_TAG=${MARIADB_TAG:-13.0.2}" \
  docker/ >/dev/null

# Memory.  EVERY profile now asks for an 8G buffer pool, because that is what
# pagesize/my-32k-sf4-t1exact.cnf used and every published figure was measured
# with.  A smaller pool is a different experiment, not a smaller one -- the
# whole point of several findings in report/ is the working set outgrowing the
# pool, and halving it moves that boundary.
#
# So this is checked for all profiles, not just `full`, and it fails rather
# than warns: an 8G pool on a VM with less simply will not start, and a
# 300-second "server did not start" says nothing useful.
POOL_G=$(printf '%s' "${BUFFER_POOL:-8G}" | sed 's/[Gg]$//')
AVAIL=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
if [[ "$POOL_G" =~ ^[0-9]+$ ]] && (( AVAIL > 0 )); then
  NEED=$(( (POOL_G + 2) * 1000000000 ))        # pool plus room for the server
  if (( AVAIL < NEED )); then
    cat >&2 <<EOF

ERROR: Docker has $((AVAIL/1000000000))G of memory; a ${POOL_G}G buffer pool needs about $((NEED/1000000000))G.

  The buffer pool is ${POOL_G}G on every profile because that is the
  configuration every published figure was measured with
  (sql/tpcds-tuned.cnf, pagesize/my-32k-sf4-t1exact.cnf).  Running a
  smaller one is a different experiment, not a smaller one.

  Either raise Docker Desktop > Settings > Resources > Memory,
  or accept a different configuration explicitly and say so when
  reporting the numbers:

      ./reproduce.sh $PROFILE BUFFER_POOL=4G

EOF
    exit 1
  fi
fi

# -t only when stdout is a terminal: with it, the script cannot be piped,
# redirected, or run from CI ("cannot attach stdin to a TTY-enabled container").
TTYARGS=()
[[ -t 0 && -t 1 ]] && TTYARGS=(-it)

echo "==> running profile '$PROFILE' (results -> ./results)"
exec docker run --rm "${TTYARGS[@]+"${TTYARGS[@]}"}" \
  -e "PROFILE=$PROFILE" "${ENVARGS[@]+"${ENVARGS[@]}"}" \
  -v "$PWD:/project:ro" \
  -v "$RESULTS:/results" \
  -v "$VOLUME:/data" \
  --name "tpcds-run-$$" \
  "$IMAGE"
