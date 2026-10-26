#!/usr/bin/env python3
"""Load SF=4/seed=10 once, then time and check two SQL files. Python stdlib only."""
import argparse
import csv
import datetime
import hashlib
import json
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

from query_trial import results, statement_count


ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "DSGen-software-code-4.0.0/tools"
DATA = ROOT / "DSGen-software-code-4.0.0/data/sf4_seed10"
LOCAL = ROOT / "experiments/local"
FIELDS = ["timestamp", "database", "baseline", "optimized", "baseline_sha256",
          "optimized_sha256", "repeat", "first", "baseline_seconds",
          "optimized_seconds", "baseline_rows", "optimized_rows", "match", "speedup", "status"]


def client(database=None, *, xml=False, local_infile=False):
    command = ["mariadb", "--connect-timeout=5", "--skip-reconnect",
               "--default-character-set=utf8mb4"]
    command += ["--xml", "--comments"] if xml else ["--batch", "--raw", "--skip-column-names"]
    if local_infile:
        command.append("--local-infile=1")
    if database:
        command.append(database)
    return command


def sql(sql_text, database=None, *, log=None, local_infile=False):
    completed = subprocess.run(client(database, local_infile=local_infile),
                               input=sql_text.encode(), capture_output=True, cwd=ROOT)
    if log is not None:
        log.write(completed.stdout + completed.stderr)
        log.flush()
    if completed.returncode:
        raise RuntimeError(completed.stderr.decode(errors="replace").strip())
    return completed.stdout.decode()


def correct_generation(command):
    return all(re.search(rf"(?:^|[\s|])-{option}\s+{value}(?=[\s|]|$)", command, re.I)
               for option, value in [("SCALE", 4), ("RNGSEED", 10)])


def check_database(database):
    command = sql("SELECT dv_cmdline_args FROM dbgen_version;", database).strip()
    if len(command.splitlines()) != 1 or not correct_generation(command):
        raise RuntimeError(f"{database} does not identify itself as SF=4, seed=10")


def space_available():
    if shutil.disk_usage(DATA).free < 2 * 1024**3:
        raise RuntimeError("Less than 2 GiB free: stopping before the next load operation")


def setup(args):
    LOCAL.mkdir(parents=True, exist_ok=True)
    complete = LOCAL / f"{args.database}_complete.json"
    exists = sql("SELECT COUNT(*) FROM information_schema.SCHEMATA "
                 f"WHERE SCHEMA_NAME='{args.database}';").strip() == "1"
    if exists:
        if complete.is_file():
            check_database(args.database)
            print(f"{args.database} is already loaded. Use the compare command.")
            return 0
        raise RuntimeError(f"{args.database} already exists; refusing to reload it. "
                           "Choose another --database name if the earlier load was interrupted.")
    if sql("SELECT @@global.local_infile;").strip() != "1":
        raise RuntimeError("MariaDB local_infile must be enabled before loading")
    if not (TOOLS / "dsdgen").is_file() or not (TOOLS / "tpcds.idx").is_file():
        target = "MACOS" if sys.platform == "darwin" else "LINUX"
        raise RuntimeError(f"Build the toolkit first: make -C DSGen-software-code-4.0.0/tools OS={target}")

    schema = (ROOT / "sql/01_schema.sql").read_text()
    tables = re.findall(r"(?m)^CREATE TABLE ([a-z_]+) \(", schema)
    loader = (ROOT / "sql/04_load_data.sql").read_text()
    loader = loader.replace("USE tpcds;", f"USE {args.database};")
    loader = loader.replace("DSGen-software-code-4.0.0/data/",
                            DATA.relative_to(ROOT).as_posix() + "/")
    loads = re.findall(r"(LOAD DATA LOCAL INFILE .*?INTO TABLE ([a-z_]+).*?;)", loader, re.S)
    if len(tables) != 25 or len(loads) != 25 or {t for _, t in loads} != set(tables):
        raise RuntimeError("Expected the repository's 25-table schema and loader")
    schema = schema.replace("CREATE DATABASE IF NOT EXISTS tpcds", f"CREATE DATABASE {args.database}")
    schema = schema.replace("USE tpcds;", f"USE {args.database};")
    schema = re.sub(r"(?m)^DROP TABLE IF EXISTS [a-z_]+;\n", "", schema)
    prefix = loader[:loader.index("LOAD DATA LOCAL INFILE")] + "SET SESSION max_statement_time=0;\n"
    DATA.mkdir(parents=True, exist_ok=True)
    marker = DATA / "generation.json"
    log_path = LOCAL / f"{args.database}_setup.log"
    with log_path.open("ab") as log:
        if marker.is_file():
            generated = json.loads(marker.read_text())
            if generated.get("scale") != 4 or generated.get("seed") != 10:
                raise RuntimeError("Generated dataset has the wrong scale or seed")
            for table in tables:
                path = DATA / f"{table}.dat"
                if not path.is_file() or path.stat().st_size != generated["bytes"][table]:
                    raise RuntimeError(f"Generated data changed or is incomplete: {path}")
            print("Reusing the completed SF=4, seed=10 dataset.", flush=True)
        else:
            version = DATA / "dbgen_version.dat"
            if any(DATA.glob("*.dat")) and (not version.is_file()
                                                  or not correct_generation(version.read_text())):
                raise RuntimeError("Existing data files have unverified generation arguments")
            space_available()
            print("Generating SF=4, seed=10...", flush=True)
            command = [str(TOOLS / "dsdgen"), "-SCALE", "4", "-RNGSEED", "10",
                       "-DIR", "../data/sf4_seed10", "-FORCE"]
            subprocess.run(command, cwd=TOOLS, stdout=log, stderr=log, check=True)
            if not correct_generation(version.read_text()):
                raise RuntimeError("Generator metadata does not match SF=4, seed=10")
            generated = {"scale": 4, "seed": 10, "rows": {}, "bytes": {}}
            for table in tables:
                path = DATA / f"{table}.dat"
                count = 0
                with path.open("rb") as source:
                    for block in iter(lambda: source.read(8 * 1024**2), b""):
                        count += block.count(b"\n")
                if not count:
                    raise RuntimeError(f"Generated table is empty: {table}")
                generated["rows"][table] = count
                generated["bytes"][table] = path.stat().st_size
            marker.write_text(json.dumps(generated, indent=2) + "\n")

        space_available()
        print(f"Creating {args.database} (primary keys only)...", flush=True)
        sql(schema, log=log)
        for statement, table in loads:
            space_available()
            print(f"Loading {table}...", flush=True)
            output = sql(prefix + statement + "\nSELECT ROW_COUNT(), @@warning_count;",
                         args.database, log=log, local_infile=True)
            loaded, warnings = map(int, output.strip().split("\t"))
            if warnings or loaded != generated["rows"][table]:
                raise RuntimeError(f"{table}: loaded {loaded}, expected {generated['rows'][table]}, "
                                   f"warnings={warnings}. See {log_path}")
        print("Updating table statistics...", flush=True)
        analyzed = sql("SET SESSION max_statement_time=0; ANALYZE TABLE " + ",".join(tables) + ";",
                       args.database, log=log)
        if any(line.split("\t")[-2:] != ["status", "OK"] for line in analyzed.splitlines()):
            raise RuntimeError(f"ANALYZE TABLE did not succeed; see {log_path}")
        check_database(args.database)
    complete.write_text(json.dumps({"database": args.database, "scale": 4, "seed": 10,
                                    "secondary_indexes": 0, "rows": generated["rows"]}, indent=2) + "\n")
    print(f"Ready: {args.database}. SF=4, seed=10, primary keys only.")
    return 0


def measure(query, database, timeout):
    preamble = ("SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');\n"
                "SET SESSION query_cache_type=OFF;\n"
                "SET SESSION TRANSACTION READ ONLY;\n"
                f"SET SESSION max_statement_time={timeout};\n")
    payload = (preamble + query).encode()
    wall_timeout = timeout * max(1, statement_count(query)) + 30
    started = time.perf_counter()
    try:
        completed = subprocess.run(client(database, xml=True), input=payload,
                                   capture_output=True, cwd=ROOT, timeout=wall_timeout)
        elapsed = time.perf_counter() - started
        raw = completed.stdout
        if completed.returncode:
            return elapsed, None, raw, completed.stderr.decode(errors="replace").strip()
        parsed = results(raw)
        if not parsed:
            return elapsed, None, raw, "SQL returned no result set"
        return elapsed, parsed, raw, ""
    except subprocess.TimeoutExpired as exc:
        return time.perf_counter() - started, None, exc.stdout or b"", "Client timeout"
    except Exception as exc:
        return time.perf_counter() - started, None, b"", str(exc)


def query_only(query):
    if not statement_count(query):
        raise ValueError("SQL is empty")
    # Hide quoted text and comments before checking statement starts.
    tokens = re.sub(r"'(?:[^'\\]|\\.|'')*'|\"(?:[^\"\\]|\\.|\"\")*\"|"
                    r"`(?:[^`]|``)*`|--(?=\s|$)[^\n]*|#[^\n]*|/\*.*?\*/",
                    " ", query, flags=re.S)
    for statement in tokens.split(";"):
        if statement.strip() and not re.match(r"\s*(SELECT|WITH)\b", statement, re.I):
            raise ValueError("Use SELECT/WITH query files only; run setup and diagnostics separately")


def compare(args):
    baseline = args.baseline.resolve()
    optimized = args.optimized.resolve()
    queries = {"baseline": baseline.read_text(), "optimized": optimized.read_text()}
    for name, query in queries.items():
        try:
            query_only(query)
        except ValueError as exc:
            raise RuntimeError(f"{name}: {exc}") from exc
    # check_database(args.database)
    if queries["baseline"] == queries["optimized"]:
        print("Note: the two SQL files are identical.", flush=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.out.exists() and args.out.stat().st_size:
        with args.out.open(newline="") as source:
            if next(csv.reader(source), []) != FIELDS:
                raise RuntimeError(f"Existing CSV has a different format: {args.out}")
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    times = {"baseline": [], "optimized": []}
    with args.out.open("a", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=FIELDS)
        if output.tell() == 0:
            writer.writeheader()
            output.flush()
        for repetition in range(1, args.repeats + 1):
            order = ["baseline", "optimized"] if repetition % 2 else ["optimized", "baseline"]
            measured = {}
            for name in order:
                print(f"Run {repetition}/{args.repeats}: {name}...", flush=True)
                measured[name] = measure(queries[name], args.database, args.timeout)
            before, after = measured["baseline"], measured["optimized"]
            error = "; ".join(f"{name}: {measured[name][3]}" for name in order if measured[name][3])
            match = not error and before[1] == after[1]
            status = "ERROR" if error else "MATCH" if match else "RESULT_DIFF"
            writer.writerow({"timestamp": timestamp, "database": args.database,
                             "baseline": str(baseline.relative_to(ROOT)) if baseline.is_relative_to(ROOT) else str(baseline),
                             "optimized": str(optimized.relative_to(ROOT)) if optimized.is_relative_to(ROOT) else str(optimized),
                             "baseline_sha256": hashlib.sha256(queries["baseline"].encode()).hexdigest(),
                             "optimized_sha256": hashlib.sha256(queries["optimized"].encode()).hexdigest(),
                             "repeat": repetition, "first": order[0],
                             "baseline_seconds": f"{before[0]:.6f}",
                             "optimized_seconds": f"{after[0]:.6f}",
                             "baseline_rows": json.dumps([len(s["rows"]) for s in before[1]]) if before[1] is not None else "",
                             "optimized_rows": json.dumps([len(s["rows"]) for s in after[1]]) if after[1] is not None else "",
                             "match": match,
                             "speedup": f"{before[0] / after[0]:.4f}" if match else "",
                             "status": error or status})
            output.flush()
            print(f"  baseline={before[0]:.3f}s optimized={after[0]:.3f}s {status}", flush=True)
            if not match:
                failure = args.out.parent / f"sf4_failure_{timestamp}_r{repetition}"
                failure.mkdir()
                for name in order:
                    (failure / f"{name}.sql").write_text(queries[name])
                    (failure / f"{name}.xml").write_bytes(measured[name][2])
                print(f"{error or 'Results differ.'}\nSaved SQL/output: {failure}", file=sys.stderr)
                return 1
            times["baseline"].append(before[0])
            times["optimized"].append(after[0])
    before = statistics.median(times["baseline"])
    after = statistics.median(times["optimized"])
    print(f"Median: baseline={before:.3f}s optimized={after:.3f}s speedup={before / after:.2f}x")
    print(f"CSV: {args.out}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup_parser = commands.add_parser("setup", help="Generate and load SF=4, seed=10; no secondary indexes")
    compare_parser = commands.add_parser("compare", help="Time two SQL files and compare their full ordered results")
    for subparser in [setup_parser, compare_parser]:
        subparser.add_argument("--database", default="tpcds_sf4_seed10")
    compare_parser.add_argument("--baseline", type=Path, required=True)
    compare_parser.add_argument("--optimized", type=Path, required=True)
    compare_parser.add_argument("--repeats", type=int, default=1)
    compare_parser.add_argument("--timeout", type=int, default=1800, help="Seconds per SQL statement")
    compare_parser.add_argument("--out", type=Path, default=LOCAL / "sf4_times.csv")
    args = parser.parse_args()
    if not re.fullmatch(r"tpcds_[A-Za-z0-9_]+", args.database):
        parser.error("Use a dedicated database name starting with tpcds_")
    if args.command == "compare" and min(args.repeats, args.timeout) < 1:
        parser.error("Repeats and timeout must be positive")
    try:
        return setup(args) if args.command == "setup" else compare(args)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
