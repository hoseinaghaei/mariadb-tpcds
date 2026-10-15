#!/usr/bin/env python3
"""Execute an explicit JSON list of query trials serially, stopping on failure."""
import argparse
import json
import subprocess
import sys
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--database", required=True)
    p.add_argument("--jobs", required=True, type=Path,
                   help="JSON list; path_base=manifest resolves paths beside this file; default: repository")
    p.add_argument("--out", required=True, type=Path)
    args = p.parse_args()
    repo = Path(__file__).resolve().parent.parent
    manifest_directory = args.jobs.resolve().parent
    jobs = json.loads(args.jobs.read_text(encoding="utf-8"))
    allowed = {"file", "label", "profile", "mode", "expect", "scale", "data_seed",
               "timeout", "client_timeout", "path_base"}
    if not isinstance(jobs, list) or not jobs:
        p.error("Jobs must be a nonempty JSON list")
    for job in jobs:
        if not isinstance(job, dict) or not {"file", "label", "profile"} <= job.keys():
            p.error("Each job requires file, label and profile")
        if job.keys() - allowed:
            p.error(f"Unknown job options: {sorted(job.keys() - allowed)}")
        if job.get("path_base", "repository") not in ("repository", "manifest"):
            p.error("Job path_base must be repository or manifest")
    for i, job in enumerate(jobs, 1):
        cmd = [sys.executable, "-u", str(repo / "scripts/query_trial.py"),
               "--database", args.database, "--out", str(args.out.resolve())]
        for key, value in job.items():
            if key == "path_base":
                continue
            if key in ("file", "expect"):
                base = manifest_directory if job.get("path_base") == "manifest" else repo
                value = (base / value).resolve()
            cmd.extend(["--" + key.replace("_", "-"), str(value)])
        print(f"START {i}/{len(jobs)}: {job['label']}", flush=True)
        result = subprocess.run(cmd, cwd=repo)
        if result.returncode:
            print(f"STOP: {job['label']} failed; inspect its run.json and stderr.txt", flush=True)
            return result.returncode
    print(f"Completed {len(jobs)} serial trials.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
