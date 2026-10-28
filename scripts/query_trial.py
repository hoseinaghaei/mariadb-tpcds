#!/usr/bin/env python3
"""Record one MariaDB query trial, or one EXPLAIN/ANALYZE diagnostic."""
import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "docker"))
from result_sets import parse_results as results


def split_statements(sql):
    """Split diagnostics without treating quoted/commented semicolons as SQL."""
    statements = []
    start = 0
    has_code = False
    i = 0
    while i < len(sql):
        char = sql[i]
        if char.isspace():
            i += 1
        elif char == "#" or (sql.startswith("--", i) and
                              (i + 2 == len(sql) or sql[i + 2].isspace())):
            end = sql.find("\n", i)
            i = len(sql) if end == -1 else end + 1
        elif sql.startswith("/*", i):
            if sql.startswith(("/*!", "/*M!"), i):
                raise ValueError("Executable SQL comments are not supported in diagnostics")
            end = sql.find("*/", i + 2)
            if end == -1:
                raise ValueError("Unterminated SQL comment")
            i = end + 2
        elif char in "'\"`":
            has_code = True
            quote = char
            i += 1
            while i < len(sql):
                if sql[i] == "\\" and quote != "`":
                    i += 2
                elif sql[i] == quote:
                    if i + 1 < len(sql) and sql[i + 1] == quote:
                        i += 2
                    else:
                        i += 1
                        break
                else:
                    i += 1
            else:
                raise ValueError("Unterminated SQL quote")
        elif char == ";":
            if has_code:
                statements.append(sql[start:i + 1])
            start = i + 1
            has_code = False
            i += 1
        else:
            has_code = True
            i += 1
    if has_code:
        statements.append(sql[start:])
    return statements


def statement_count(sql):
    return len(split_statements(sql))


def main():
    repo = Path(__file__).resolve().parent.parent
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--database", required=True)
    p.add_argument("--file", required=True, type=Path)
    p.add_argument("--label", required=True)
    p.add_argument("--out", type=Path, default=repo / "experiments/local/runs")
    p.add_argument("--profile", required=True)
    p.add_argument("--scale", type=int, default=1)
    p.add_argument("--data-seed", type=int, default=10)
    p.add_argument("--timeout", type=int, default=600,
                   help="Server execution cap in seconds per statement")
    p.add_argument("--client-timeout", type=int, default=3600)
    p.add_argument("--mode", choices=["run", "explain", "analyze"], default="run")
    p.add_argument("--expect", type=Path, help="Baseline result.json for a strict comparison")
    args = p.parse_args()
    if not re.fullmatch(r"tpcds_[A-Za-z0-9_]+", args.database):
        p.error("Use your dedicated tpcds_ experiment database")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.label):
        p.error("Use letters, digits, underscores, dots or hyphens for the label")
    if args.timeout < 1 or args.client_timeout < 1:
        p.error("Timeouts must be positive")
    sql_path = args.file.resolve()
    sql_bytes = sql_path.read_bytes()
    sql = sql_bytes.decode("utf-8")
    if args.mode != "run":
        # Avoid prefixing only the first statement and executing the second.
        try:
            count = statement_count(sql)
        except ValueError as exc:
            p.error(str(exc))
        if count != 1:
            p.error("Diagnostics require one statement; use the Q39 a/b files")
        sql = ("EXPLAIN FORMAT=JSON " if args.mode == "explain"
               else "ANALYZE FORMAT=JSON ") + sql
    directory = args.out.resolve() / args.label
    directory.mkdir(parents=True, exist_ok=False)
    (directory / "input.sql").write_bytes(sql_bytes)
    pre = ("SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');\n"
           "SET SESSION query_cache_type=OFF;\n"
           f"SET SESSION max_statement_time={args.timeout};\n")
    client = ["mariadb", "--connect-timeout=5", "--skip-reconnect", "--comments",
              "--xml", "--default-character-set=utf8mb4", args.database]
    context_sql = """
SELECT VERSION() AS server_version, DATABASE() AS database_name,
 @@session.sql_mode AS sql_mode, @@session.query_cache_type AS query_cache_type,
 @@session.max_statement_time AS max_statement_time,
 @@global.innodb_buffer_pool_size AS buffer_pool_bytes,
 @@session.tmp_table_size AS tmp_table_size,
 @@session.max_heap_table_size AS max_heap_table_size,
 @@session.optimizer_switch AS optimizer_switch;
SELECT TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX, COLUMN_NAME, NON_UNIQUE, IGNORED
 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE()
 ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
"""
    record = {"label": args.label, "database": args.database, "mode": args.mode,
              "client_host": platform.node(), "client_platform": platform.platform(),
              "profile_label": args.profile, "scale_label": args.scale,
              "data_seed_label": args.data_seed,
              "sql_file": Path(os.path.relpath(sql_path, repo)).as_posix(),
              "sql_file_base": "repository",
              "sql_sha256": hashlib.sha256(sql_bytes).hexdigest(),
              "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "session_preamble": pre,
              "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "server_timeout_seconds": args.timeout,
              "client_timeout_seconds": args.client_timeout}
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo,
                            capture_output=True, text=True)
    record["commit"] = commit.stdout.strip() if commit.returncode == 0 else None
    try:
        context = subprocess.run(client, input=(pre + context_sql).encode("utf-8"),
                                 capture_output=True, timeout=30)
        if context.returncode:
            raise RuntimeError(context.stderr.decode("utf-8", errors="replace"))
        record["context"] = results(context.stdout)
        started = time.perf_counter()
        with (directory / "output.xml").open("wb") as out, (directory / "stderr.txt").open("wb") as err:
            try:
                run = subprocess.run(client, input=(pre + sql).encode("utf-8"),
                                     stdout=out, stderr=err, timeout=args.client_timeout)
                code = run.returncode
            except subprocess.TimeoutExpired:
                code = None
        record["seconds"] = time.perf_counter() - started
        error = (directory / "stderr.txt").read_text(encoding="utf-8", errors="replace")
        record["status"] = ("CLIENT_TIMEOUT" if code is None else
                            "STATEMENT_TIMEOUT" if "ERROR 1969" in error else
                            "SQL_ERROR" if code else "OK")
        record["return_code"] = code
        if code == 0:
            result = results((directory / "output.xml").read_bytes())
            if not result:
                raise RuntimeError("No SELECT result set; verify the SQL file")
            record["result_set_rows"] = [len(s["rows"]) for s in result]
            (directory / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                                                  encoding="utf-8")
            if args.mode != "run":
                for i, resultset in enumerate(result, 1):
                    plan = json.loads(resultset["rows"][0][0])
                    (directory / f"plan_{i}.json").write_text(json.dumps(plan, indent=2) + "\n",
                                                            encoding="utf-8")
            if args.expect is not None:
                expected = json.loads(args.expect.read_text(encoding="utf-8"))
                record["strict_result_match"] = result == expected
                if not record["strict_result_match"]:
                    record["status"] = "RESULT_DIFF"
    except Exception as exc:
        record["status"] = "TOOL_ERROR"
        record["detail"] = str(exc)
    (directory / "run.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n",
                                       encoding="utf-8")
    print(json.dumps({k: record[k] for k in ["label", "status", "seconds", "result_set_rows"]
                      if k in record}, ensure_ascii=False))
    print(f"Artifacts: {directory}")
    return 0 if record["status"] == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
