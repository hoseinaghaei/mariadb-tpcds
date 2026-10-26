#!/usr/bin/env bash
#
# run-scales.sh [SF ...] [KEY=VALUE ...] -- benchmark the suite at several
# scale factors so the results can be compared as a scaling curve.
#
#   ./run-scales.sh                 # scale factors 1 2 3 4
#   ./run-scales.sh 1 4             # just those two
#   ./run-scales.sh 1 2 3 4 BUFFER_POOL=8G
#
# Each scale factor is a full reproduction: generate, load, index, ANALYZE,
# benchmark.  Results land in results/sf<N>/ and a manifest is written to
# results/manifest.json, which analysis/collect.py reads.
#
# WHY THE BUFFER POOL IS HELD CONSTANT.  It defaults to 8G for every scale
# factor -- the value sql/tpcds-tuned.cnf and the retired macOS instance used,
# so the numbers are comparable with everything already published -- and is
# deliberately NOT scaled up with the data.  A scaling curve
# measured with a pool that grows alongside the dataset conflates two
# variables and mostly measures the pool.  Holding it fixed is what makes the
# curve mean something: at SF=1 the working set fits, and somewhere above it
# stops fitting, which is the interesting part.  Override it if you want the
# other experiment, but then say so when reporting.
#
# TIME AND DISK.  Each scale factor is generated and loaded from scratch the
# first time, and index creation dominates.  Rough budget on a laptop:
#
#     SF=1   ~20 min     ~12 GB
#     SF=2   ~40 min     ~23 GB
#     SF=3   ~1.5 h      ~35 GB
#     SF=4   ~3 h        ~46 GB
#
# Those are MEASURED, not estimated: the SF=1 volume here came to 11.8 GB
# (1.2 GB of .dat files, the rest database plus 188 indexes), and the rest
# scale from it.  The disk that has to hold them is Docker's virtual disk,
# not the host's -- see the preflight check below, which exists because the
# first SF=4 attempt died 14 minutes in with "No space left on device" on a
# host that had 287 GB free.
#
# So the default four-scale sweep is most of a working day and ~115 GB.  Each
# scale keeps its own Docker volume (tpcds-data-sf<N>), so re-running one
# later skips generation and loading entirely.  Reclaim with:
#
#     docker volume rm tpcds-data-sf1 tpcds-data-sf2 tpcds-data-sf3 tpcds-data-sf4
#
# Scale factors other than 1 are not valid for publishable TPC-DS results;
# this is an engineering exercise, and the same caveat in the top-level
# README applies.
set -Eeuo pipefail
cd "$(dirname "$0")"

SFS=(); OVERRIDES=()
for a in "$@"; do
  if [[ "$a" =~ ^[0-9]+$ ]]; then SFS+=("$a")
  elif [[ "$a" == *=* ]]; then OVERRIDES+=("$a")
  else echo "unrecognised argument '$a' (want a scale factor or KEY=VALUE)" >&2; exit 1; fi
done
[[ ${#SFS[@]} -gt 0 ]] || SFS=(1 2 3 4)

# Only set a default if the caller did not; see the note above.
have_pool=0
for o in ${OVERRIDES[@]+"${OVERRIDES[@]}"}; do
  [[ "$o" == BUFFER_POOL=* ]] && have_pool=1
done
(( have_pool )) || OVERRIDES+=("BUFFER_POOL=8G")

command -v docker >/dev/null 2>&1 || { echo "docker is not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "the docker daemon is not running" >&2; exit 1; }

# Disk, before spending an hour finding out.  The space that matters is
# inside Docker's VM, not on the host: on macOS the VM has its own fixed
# virtual disk, and a host with 287 GB free can still fail with
# "No space left on device" partway through generating data.  That is
# exactly how the first SF=4 attempt here died, 14 minutes in.
#
# Observed footprint: SF=1 fills an 11.8 GB volume (1.2 GB of .dat files and
# the rest database plus 188 indexes), and it scales with the data, so budget
# about 11 GB per unit of scale factor and ask for a little headroom.
# df the container's own root filesystem: that lives on the VM's virtual
# disk, which is the thing that runs out.  Do NOT bind-mount the host's /
# and measure that -- on Docker Desktop it is shared through virtiofs and
# reports something unrelated (1G here, against the VM's real 11G free).
free_gb=$(docker run --rm alpine:3 df -BG / 2>/dev/null \
          | awk 'NR==2{gsub("G","",$4); print $4+0}')
if [[ -n "${free_gb:-}" ]]; then
  # Only scale factors whose volume does not already exist need new space;
  # a scale that has been run before reuses its volume and needs headroom
  # only.  Without this, re-running SF=1 would be refused for want of 15G
  # it is not going to ask for.
  need=4
  biggest=0
  for s in "${SFS[@]}"; do
    (( s > biggest )) && biggest=$s
    docker volume inspect "tpcds-data-sf$s" >/dev/null 2>&1 || need=$(( need + s * 11 ))
  done
  echo "==> docker vm disk : ${free_gb}G free, about ${need}G needed for SF=${SFS[*]}"
  if (( free_gb < need )); then
    cat >&2 <<EOF

ERROR: not enough space inside Docker's VM.
       ${free_gb}G free, about ${need}G needed for scale factors ${SFS[*]}.

       This is Docker's virtual disk, not your host disk.  Options:
         * raise the disk size in Docker Desktop > Settings > Resources
         * reclaim space:   docker system df -v        (see what is large)
                            docker volume rm <name>    (named volumes)
         * run fewer or smaller scale factors:  ./run-scales.sh 1 2

       Each scale factor keeps its own volume (tpcds-data-sf<N>), so you can
       also run them one at a time and remove each when you have its results:
         ./run-scales.sh 4  &&  docker volume rm tpcds-data-sf4
EOF
    exit 1
  fi
else
  echo "==> docker vm disk : could not measure; continuing" >&2
fi

echo "==> scale factors : ${SFS[*]}"
echo "==> held constant : ${OVERRIDES[*]}"
echo

START=$(date +%s)
DONE=()
for SF in "${SFS[@]}"; do
  echo "################################################################"
  echo "### scale factor $SF   ($(date '+%H:%M:%S'))"
  echo "################################################################"
  OUT="$PWD/results/sf$SF"
  mkdir -p "$OUT"
  # Each scale gets its own volume so a repeat run of one scale is cheap.
  RESULTS_DIR="$OUT" VOLUME="tpcds-data-sf$SF" \
    ./reproduce.sh quick "SCALE=$SF" ${OVERRIDES[@]+"${OVERRIDES[@]}"} \
    || { echo "!! scale factor $SF failed; continuing with the rest" >&2; continue; }
  DONE+=("$SF")
done

# A manifest so the analysis does not have to guess what was run, and so a
# partial sweep is self-describing rather than silently incomplete.
python3 - "$PWD/results" "${SFS[*]}" "${DONE[*]}" "${OVERRIDES[*]}" <<'PY'
import json, sys, os, glob, datetime
out, asked, done, over = sys.argv[1], sys.argv[2].split(), sys.argv[3].split(), sys.argv[4].split()
runs = []
for sf in done:
    d = f"{out}/sf{sf}/tuned"
    s = f"{d}/_summary.json"
    runs.append({
        "environment": "docker",
        "scale": int(sf),
        "dir": os.path.relpath(d, os.path.dirname(out)),
        "summary": json.load(open(s)) if os.path.exists(s) else None,
        "queries": len(glob.glob(f"{d}/query*.json")),
    })
json.dump({
    "generated": datetime.datetime.now().isoformat(timespec="seconds"),
    "asked_for": [int(x) for x in asked],
    "completed": [int(x) for x in done],
    "held_constant": over,
    "runs": runs,
}, open(f"{out}/manifest.json", "w"), indent=1)
print(f"  manifest: {out}/manifest.json  ({len(runs)} runs)")
PY

echo
echo "==> completed ${#DONE[@]}/${#SFS[@]} scale factors in $(( ($(date +%s)-START)/60 )) min"
[[ ${#DONE[@]} -eq ${#SFS[@]} ]] || echo "==> MISSING: $(comm -13 <(printf '%s\n' "${DONE[@]}" | sort) <(printf '%s\n' "${SFS[@]}" | sort) | tr '\n' ' ')"
echo
echo "Next:  python3 analysis/analyze.py        # tables, charts, anomalies"
