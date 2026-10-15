#!/usr/bin/env python3
"""Summarize repeated trials, keeping SQL and physical configurations separate."""
import argparse
import csv
import hashlib
import json
import re
import statistics
from collections import defaultdict
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runs", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()
    groups = defaultdict(list)
    failures = []
    for path in sorted(args.runs.glob("*/run.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        match = re.fullmatch(r"q(\d+)_(v\d+)_(.+)_r(\d+)", record["label"])
        if not match or record["mode"] != "run":
            continue  # Probes, warm-ups, fixtures and diagnostics are not timings.
        if record["status"] != "OK":
            failures.append({"label": record["label"], "status": record["status"]})
            continue
        configuration = hashlib.sha256(json.dumps(record["context"],
                                                   sort_keys=True).encode()).hexdigest()
        key = (int(match[1]), record["profile_label"], record["database"],
               record["scale_label"], record["data_seed_label"], configuration,
               match[2], record["sql_sha256"])
        groups[key].append(record)
    rows = []
    baseline = {}
    for key, records in sorted(groups.items()):
        q, profile, database, scale, seed, configuration, variant, sql_hash = key
        seconds = [r["seconds"] for r in records]
        row = {"query": q, "profile": profile, "database": database, "scale": scale,
               "data_seed": seed, "configuration_sha256": configuration,
               "variant": variant, "sql_sha256": sql_hash, "n": len(records),
               "median_seconds": statistics.median(seconds), "min_seconds": min(seconds),
               "max_seconds": max(seconds), "result_set_rows": records[0]["result_set_rows"],
               "all_strict_matches": all(r.get("strict_result_match") is True for r in records),
               "trial_labels": [r["label"] for r in records]}
        rows.append(row)
        if variant == "v0":
            baseline.setdefault(key[:6], []).append(row)
    for row in rows:
        key = (row["query"], row["profile"], row["database"], row["scale"],
               row["data_seed"], row["configuration_sha256"])
        candidates = baseline.get(key, [])
        row["speedup_vs_same_profile_v0"] = (
            candidates[0]["median_seconds"] / row["median_seconds"]
            if len(candidates) == 1 else None
        )
    args.out.mkdir(parents=True, exist_ok=True)
    summary = {"protocol": "Only ordinary trials ending in _rN; no probes or diagnostics. "
               "Compare median times only within identical recorded configurations.",
               "groups": rows, "failed_repetitions": failures}
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    fields = ["query", "profile", "database", "scale", "data_seed", "variant", "n",
              "median_seconds", "min_seconds", "max_seconds", "speedup_vs_same_profile_v0",
              "all_strict_matches", "result_set_rows", "sql_sha256", "configuration_sha256"]
    with (args.out / "measurements.csv").open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"groups": len(rows), "failed_repetitions": failures,
                      "output": str(args.out)}, indent=2))


if __name__ == "__main__":
    main()
