#!/usr/bin/env python3
"""Gather every benchmark run into one tidy table.

Results are written by two different harnesses into two different places:

    results/sf<N>/tuned/query*.json        the container (run-scales.sh)
    pagesize/results/mac-sf<N>/query*.json the macOS host (run-scales-mac.sh)

plus whatever older tagged runs are lying around under pagesize/results/.
This walks all of them and produces one list of records:

    environment  docker | macos
    scale        1, 2, 3, 4, ...
    query        2, 4, 5, ...
    seconds      wall time
    rows         rows returned
    md5_sorted   hash of the result with data rows sorted
    status       OK | ERROR
    tag          the directory it came from, for traceability

Import `collect()` from here, or run it directly to dump analysis/results.csv.

A note on comparing hashes.  Two runs at the SAME scale factor must agree on
md5_sorted -- different answers mean a real defect.  Two runs at DIFFERENT
scale factors must NOT be expected to agree: dsdgen produces a different
database at every scale, so the answers legitimately differ.  Only the
same-scale comparison is a correctness check.
"""
import json, os, re, glob, csv, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# Directories that hold per-query JSON, and how to read an environment and a
# scale factor out of their names.  Anything that does not match is skipped
# rather than guessed at.
def _docker_env(path):
    """Label a container run by its directory, not just 'docker'.

    results/sf1/ and results/sf1-pruned/ are both docker runs at SF=1 -- the
    second with 127 unused indexes dropped -- and labelling both 'docker'
    made one silently overwrite the other.  Anything after the scale number
    becomes part of the environment name instead.
    """
    name = os.path.basename(os.path.dirname(path))  # .../sf1-pruned/tuned -> sf1-pruned
    m = re.match(r'sf(\d+)(.*)$', name)
    suffix = (m.group(2) or "").strip("-_") if m else ""
    return f"docker-{suffix}" if suffix else "docker"


SOURCES = [
    # (glob of result directories, environment, how to get the scale)
    (f"{REPO}/results/sf*/tuned", _docker_env,
     lambda p: int(re.match(r'sf(\d+)', os.path.basename(os.path.dirname(p))).group(1))),
    (f"{REPO}/pagesize/results/mac-sf*", "macos",
     lambda p: int(re.search(r'mac-sf(\d+)$', p).group(1))),
]


def _scale_from_summary(d):
    """Fall back to the run's own record of its scale factor."""
    s = f"{d}/_summary.json"
    if os.path.exists(s):
        j = json.load(open(s))
        for k in ("scale", "scale_factor"):
            if k in j:
                return int(j[k])
    # bench-tuned.py stores it per query instead
    for p in glob.glob(f"{d}/query*.json")[:1]:
        j = json.load(open(p))
        if "scale" in j:
            return int(j["scale"])
    return None


# What the reports show by default.  Five runs were being mixed into one
# document -- macOS at two scales, the container at two, and a container run
# with 127 indexes dropped -- which makes a reader work out which numbers
# belong together before they can read anything.  They mostly do not: the
# macOS SF=4 dataset was generated without -RNGSEED 10, so it is a different
# database, and the pruned run is a side experiment that exists at SF=1 only.
#
# The default is therefore the canonical container runs, which are complete
# at both scales and use the published configuration.  collect(only=None)
# returns everything for our own comparisons.
DEFAULT_ONLY = ("docker",)


def collect(verbose=False, only=DEFAULT_ONLY):
    rows = []
    seen = []
    for pattern, env_spec, scale_of in SOURCES:
        for d in sorted(glob.glob(pattern)):
            if not os.path.isdir(d):
                continue
            env = env_spec(d) if callable(env_spec) else env_spec
            if only is not None and env not in only:
                if verbose:
                    print(f"  excluded ({env}): {os.path.relpath(d, REPO)}")
                continue
            try:
                scale = scale_of(d)
            except Exception:
                scale = _scale_from_summary(d)
            if scale is None:
                if verbose:
                    print(f"  skipped (no scale factor): {d}")
                continue
            files = sorted(glob.glob(f"{d}/query*.json"),
                           key=lambda p: int(re.search(r'query(\d+)', p).group(1)))
            if not files:
                continue
            tag = os.path.relpath(d, REPO)
            for p in files:
                j = json.load(open(p))
                rows.append({
                    "environment": env,
                    "scale": scale,
                    "query": j["query"],
                    "seconds": j.get("seconds"),
                    "rows": j.get("rows"),
                    "md5_sorted": j.get("md5_sorted"),
                    "status": j.get("status", "?"),
                    "tag": tag,
                })
            seen.append((env, scale, tag, len(files)))
    if verbose:
        for env, scale, tag, n in seen:
            print(f"  {env:<7} SF={scale:<3} {n:>3} queries   {tag}")
        if not seen:
            print("  nothing found -- run ./run-scales.sh or "
                  "pagesize/run-scales-mac.sh first")
    return rows


def main():
    everything = "--all" in sys.argv
    rows = collect(verbose=True, only=None if everything else DEFAULT_ONLY)
    if not rows:
        sys.exit(1)
    out = f"{HERE}/results.csv"
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    envs = {(r["environment"], r["scale"]) for r in rows}
    print(f"\n  wrote {out}: {len(rows)} rows, {len(envs)} runs")


if __name__ == "__main__":
    main()
