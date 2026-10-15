#!/usr/bin/env python3
"""Prepare isolated SQL and baseline files; never connects to MariaDB."""
import argparse
import json
import re
from pathlib import Path


def repository_root(start, parser):
    start = start.resolve()
    for candidate in [start, *start.parents]:
        if ((candidate / "sql/01_schema.sql").is_file()
                and (candidate / "queries/mariadb/query31.sql").is_file()):
            return candidate
    parser.error(
        f"Cannot find the TPC-DS repository from {start}. "
        "Use --repo with the project directory containing sql/ and queries/."
    )


def write_once(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_text(encoding="utf-8") != content:
            raise SystemExit(f"Refusing to overwrite modified file: {path}")
        return
    path.write_text(content, encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path,
                   help="Project directory or a subdirectory; default: locate it from this script")
    p.add_argument("--database", required=True)
    p.add_argument("--scale", type=int, default=1)
    p.add_argument("--seed", type=int, default=10)
    args = p.parse_args()
    if not re.fullmatch(r"tpcds_[A-Za-z0-9_]+", args.database):
        p.error("Use a dedicated name starting with tpcds_, not the existing tpcds database")
    if args.scale < 1:
        p.error("This generator requires a positive integer scale")
    repo = repository_root(
        args.repo if args.repo is not None else Path(__file__).resolve().parent, p
    )
    required = [
        "sql/01_schema.sql", "sql/04_load_data.sql", "sql/05_indexes.sql",
        *[f"queries/mariadb/query{query}.sql" for query in [4, 5, 31, 39, 51]],
    ]
    missing = [name for name in required if not (repo / name).is_file()]
    if missing:
        p.error(f"Missing project inputs in {repo}: {', '.join(missing)}")
    sources = {
        name: (repo / name).read_text(encoding="utf-8")
        for name in required
    }
    local = repo / "experiments/local"
    data_root = "DSGen-software-code-4.0.0/data/"
    data_relative = f"{data_root}sf{args.scale}_seed{args.seed}"
    data = repo / data_relative
    generated = local / f"{args.database}_sql"
    for directory in [data, generated, local / "runs"]:
        directory.mkdir(parents=True, exist_ok=True)
    write_once(local / ".gitignore", "*\n!.gitignore\n")
    schema = sources["sql/01_schema.sql"]
    assert schema.count("CREATE DATABASE IF NOT EXISTS tpcds") == 1
    assert schema.count("USE tpcds;") == 1
    tables = re.findall(r"(?m)^CREATE TABLE ([a-z_]+) \(", schema)
    assert len(tables) == 25, f"Expected 25 tables, found {len(tables)}"
    schema = schema.replace("CREATE DATABASE IF NOT EXISTS tpcds",
                            f"CREATE DATABASE {args.database}")
    schema = schema.replace("USE tpcds;", f"USE {args.database};")
    schema = re.sub(r"(?m)^DROP TABLE IF EXISTS [a-z_]+;\n", "", schema)
    schema = schema.replace("NOTE: re-running this script DROPS AND RECREATES every table.",
                            "NOTE: this generated script requires a new, empty database.")
    assert not re.search(r"(?im)^\s*DROP\s", schema)
    write_once(generated / "01_schema.sql", schema)
    for name in ["04_load_data.sql", "05_indexes.sql"]:
        sql = sources[f"sql/{name}"]
        assert sql.count("USE tpcds;") == 1
        sql = sql.replace("USE tpcds;", f"USE {args.database};")
        if name == "04_load_data.sql":
            assert sql.count(f"INFILE '{data_root}") == 25
            sql = sql.replace(f"INFILE '{data_root}", f"INFILE '{data_relative}/")
        write_once(generated / name, sql)
    counts = "\nUNION ALL\n".join(
        f"SELECT '{table}' AS table_name, COUNT(*) AS row_count FROM {table}"
        for table in sorted(tables)
    ) + "\nORDER BY table_name;\n"
    write_once(generated / "table_counts.sql", counts)
    for query in [4, 5, 31, 39, 51]:
        sql = sources[f"queries/mariadb/query{query}.sql"]
        directory = repo / f"queries/optimized/q{query}"
        write_once(directory / f"query{query}_v0.sql", sql)
        if query == 39:
            # Only the checked-in Q39 file: two SELECTs with no embedded semicolons.
            statements = [s.strip() for s in sql.split(";") if s.strip()]
            assert len(statements) == 2
            for suffix, statement in zip(["a", "b"], statements):
                write_once(directory / f"query39{suffix}_v0.sql", statement + ";\n")
    manifest = {"database": args.database, "scale": args.scale, "data_seed": args.seed,
                "path_base": "repository",
                "data_directory": data_relative,
                "sql_directory": generated.relative_to(repo).as_posix(),
                "note": "Preparation only; data generation and loading have not been performed."}
    write_once(generated / "setup.json", json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
