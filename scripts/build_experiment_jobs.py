#!/usr/bin/env python3
"""Build warm-ups and three alternating baseline/candidate timing rounds."""
import argparse
import json
import os
import re
from pathlib import Path

CANDIDATES = {
    4: ("v2", "query4_v2_customerpivot.sql"),
    5: ("v1", "query5_v1_branchfilters.sql"),
    31: ("v2", "query31_v2_pivot.sql"),
    39: ("v6", "query39_v6_sourcefirst.sql"),
    51: ("v1", "query51_v1_unifieddaily.sql"),
}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runs", type=Path, required=True, help="Directory passed to run_query_batch --out")
    p.add_argument("--output", type=Path, required=True, help="New JSON job list")
    p.add_argument("--profile", required=True, help="Label only; does not create or ignore indexes")
    p.add_argument("--queries", default="4,5,31,39,51")
    p.add_argument("--repeats", type=int, default=3)
    p.add_argument("--scale", type=int, default=1)
    p.add_argument("--data-seed", type=int, default=10)
    p.add_argument("--timeout", type=int, default=600)
    args = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.profile):
        p.error("Profile must contain letters, numbers, underscores or hyphens")
    try:
        queries = [int(q.strip()) for q in args.queries.split(",")]
    except ValueError:
        p.error("Queries must be comma-separated numbers")
    if len(set(queries)) != len(queries) or not queries or set(queries) - CANDIDATES.keys():
        p.error("Choose distinct query numbers from 4,5,31,39,51")
    if min(args.repeats, args.scale, args.timeout) < 1:
        p.error("Repeats, scale and timeout must be positive")
    repo = Path(__file__).resolve().parent.parent
    manifest_directory = args.output.resolve().parent
    jobs = []
    for q in queries:
        variant, filename = CANDIDATES[q]
        versions = [("v0", f"query{q}_v0.sql"), (variant, filename)]
        expected = args.runs.resolve() / f"q{q}_v0_{args.profile}_warmup/result.json"
        def job(v, name, suffix, check=True):
            source = repo / f"queries/optimized/q{q}" / name
            if not source.is_file():
                p.error(f"Missing SQL: {source}")
            trial = {"file": Path(os.path.relpath(source, manifest_directory)).as_posix(),
                     "path_base": "manifest", "label": f"q{q}_{v}_{args.profile}_{suffix}",
                     "profile": args.profile, "scale": args.scale,
                     "data_seed": args.data_seed, "timeout": args.timeout}
            if check:
                trial["expect"] = Path(os.path.relpath(expected, manifest_directory)).as_posix()
            return trial
        jobs.extend([job(*versions[0], "warmup", check=False),
                     job(*versions[1], "warmup")])
        for rep in range(1, args.repeats + 1):
            ordered = versions if rep % 2 else list(reversed(versions))
            jobs.extend(job(v, name, f"r{rep}") for v, name in ordered)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as output:
        output.write(json.dumps(jobs, indent=2) + "\n")
    print(f"Wrote {len(jobs)} serial jobs to {args.output}")


if __name__ == "__main__":
    main()
