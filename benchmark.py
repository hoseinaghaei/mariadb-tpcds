#!/usr/bin/env python3
"""Run the TPC-DS benchmark at one scale factor. Windows, macOS or Linux.

    python benchmark.py --scale 4

That is the whole thing. It generates the data, loads it, builds the
indexes, runs the 40 queries and writes a report with every query's time
and the total.

The first run at a given scale factor does the generating and loading and
takes a while; later runs at the same scale reuse it and only re-run the
queries.

    python benchmark.py --scale 1          smallest, quickest
    python benchmark.py --scale 4          the reference size
    python benchmark.py --scale 8          largest measured
    python benchmark.py --scale 4 --keep   keep the data for a re-run (default)
    python benchmark.py --scale 4 --fresh  rebuild from scratch

Requires Docker. Nothing else -- MariaDB, the TPC-DS toolkit and every
dependency live inside the container, so the host needs no database, no
compiler and no Python packages.

Why Python and not a shell script: the professor may be on Windows, where
bash is not a given. This drives Docker through subprocess and does nothing
platform-specific, so one file serves all three systems.
"""
import argparse, json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE = "tpcds-mariadb"

# Keep these in step with docker/profiles.sh.  They are the configuration
# every published figure was measured on.
SETTINGS = {
    "PAGE_SIZE": "32", "BUFFER_POOL": "8G", "SAMPLE_PAGES": "160",
    "QUERYSET": "tuned", "TUNED": "tuned", "RNGSEED": "10",
    "PRUNE_INDEXES": "1", "TMP_TABLE_SIZE": "1536M",
    "MAX_HEAP_TABLE_SIZE": "1536M", "ARIA_PAGECACHE_BUFFER_SIZE": "1G",
    "SORT_BUFFER_SIZE": "64M", "JOIN_BUFFER_SIZE": "64M",
    "JOIN_BUFFER_SPACE_LIMIT": "256M", "STATEMENT_TIMEOUT": "3600",
}
# Disk the volume needs, measured: SF=4 is 40 GB, SF=8 is 69 GB.
DISK_GB = {1: 15, 2: 25, 4: 45, 8: 75}
MIN_MEMORY_GB = 11


def die(msg, *hint):
    print(f"\nERROR: {msg}", file=sys.stderr)
    for h in hint:
        print(f"       {h}", file=sys.stderr)
    sys.exit(1)


def docker(*args, capture=True, check=True, **kw):
    return subprocess.run(["docker", *args], capture_output=capture,
                          text=True, check=check, **kw)


def preflight(scale):
    if shutil.which("docker") is None:
        die("Docker is not installed, or is not on PATH.",
            "Install Docker Desktop: https://docs.docker.com/get-docker/")
    try:
        info = docker("info", "--format", "{{.MemTotal}}|{{.NCPU}}").stdout.strip()
    except subprocess.CalledProcessError:
        die("Docker is installed but not running.",
            "Start Docker Desktop (or dockerd) and try again.")
    mem, cpus = info.split("|")
    mem_gb = int(mem) / (1024 ** 3)
    print(f"  Docker: {cpus} CPUs, {mem_gb:.1f} GiB memory")
    if mem_gb < MIN_MEMORY_GB:
        die(f"Docker has {mem_gb:.1f} GiB of memory; this needs about {MIN_MEMORY_GB} GiB.",
            "Docker Desktop > Settings > Resources > Memory.",
            "Or run a smaller scale factor, e.g. --scale 1.")
    try:
        out = docker("run", "--rm", "alpine:3", "df", "-BG", "/").stdout
        free = int(out.strip().split("\n")[-1].split()[3].rstrip("G"))
        need = DISK_GB.get(scale, 15 * scale)
        print(f"  Disk:   {free} GiB free, scale factor {scale} needs about {need} GiB")
        if free < need:
            die(f"Docker has {free} GiB free; scale factor {scale} needs about {need} GiB.",
                "Docker Desktop > Settings > Resources > Virtual disk limit.")
    except (subprocess.CalledProcessError, ValueError, IndexError):
        print("  Disk:   could not be checked; continuing")


def main():
    ap = argparse.ArgumentParser(
        description="Run the TPC-DS benchmark at one scale factor.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Requires Docker. Everything else runs inside the container.")
    ap.add_argument("--scale", type=int, default=4, metavar="N",
                    help="scale factor: 1, 2, 4 or 8 (default 4)")
    ap.add_argument("--fresh", action="store_true",
                    help="discard any existing data and rebuild from scratch")
    ap.add_argument("--keep", action="store_true", default=True,
                    help="reuse existing data if present (the default)")
    ap.add_argument("--results", metavar="DIR",
                    help="where to write results (default: results/sf<N>)")
    a = ap.parse_args()
    if a.scale < 1:
        die("--scale must be 1 or more.")

    results = os.path.abspath(a.results or os.path.join(HERE, "results", f"sf{a.scale}"))
    volume = f"tpcds-data-sf{a.scale}"
    os.makedirs(results, exist_ok=True)

    print(f"\nTPC-DS on MariaDB — scale factor {a.scale}")
    print(f"  Results will be written to {results}\n")
    preflight(a.scale)

    if a.fresh:
        print(f"  --fresh: removing the existing data volume {volume}")
        docker("volume", "rm", "-f", volume, check=False)

    print("\n  Building the container image (cached after the first time)...")
    b = docker("build", "-q", "-t", IMAGE, "--build-arg", "MARIADB_TAG=13.0.2",
               os.path.join(HERE, "docker"), check=False)
    if b.returncode != 0:
        die("could not build the image.", (b.stderr or "").strip()[:400])

    env = []
    for k, v in {**SETTINGS, "SCALE": str(a.scale), "PROFILE": "full"}.items():
        env += ["-e", f"{k}={v}"]

    print("  Starting the run. The first run at this scale generates and loads")
    print("  the data, so it takes a while; later runs reuse it.\n")
    t0 = time.time()
    r = subprocess.run(
        ["docker", "run", "--rm", *env,
         "-v", f"{HERE}:/project:ro", "-v", f"{results}:/results",
         "-v", f"{volume}:/data", IMAGE],
        check=False)
    elapsed = time.time() - t0

    report = os.path.join(results, "REPORT.md")
    if r.returncode != 0 or not os.path.exists(report):
        die(f"the run did not finish (exit code {r.returncode}).",
            f"Whatever was produced is in {results}.",
            "The output above shows which stage failed.")

    print(f"\n{'=' * 64}")
    print(f"Done in {elapsed / 60:.1f} minutes.\n")
    summary = os.path.join(results, "tuned", "_summary.json")
    if os.path.exists(summary):
        s = json.load(open(summary))
        print(f"  {s.get('queries', '?')} queries, {s.get('total_seconds', 0):.1f}s total,"
              f" {s.get('errors', 0)} errors")
    print(f"\n  Report:     {report}")
    print(f"  Spreadsheet:{os.path.join(results, 'report.csv')}")
    print(f"  Raw results:{os.path.join(results, 'tuned')}")
    print(f"{'=' * 64}\n")


if __name__ == "__main__":
    main()
