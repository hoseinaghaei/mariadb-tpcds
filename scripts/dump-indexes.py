#!/usr/bin/env python3
"""Write every secondary index in the database to one restorable file.

    python3 scripts/dump-indexes.py [socket] [out.sql]

Default output is sql/all_indexes.sql, and the point of it is that dropping
an index stops being a one-way door:

    mariadb tpcds < sql/all_indexes.sql        # put them all back

This exists because "unused" is not a property of an index, it is a property
of an index AND a workload AND a configuration.  report/17 and report/22 in
this repository are both about indexes that looked dead in one configuration
and were read millions of times in another -- the same index set measured at
16K and at 32K pages disagreed about which members were idle.  So the right
move is to drop from a position where restoring costs one command, and to
prefer ALTER INDEX ... IGNORED (metadata-only, ~0.15s, reversible) whenever
the question is "is this one earning its keep" rather than "I need the disk
back".

The file is generated from the live schema rather than hand-maintained, so
it cannot drift from what is actually there.  PRIMARY keys are excluded:
they are part of the table definition in sql/01_schema.sql, not something
this file should try to recreate.

Indexes currently marked IGNORED are emitted as CREATE plus a matching
ALTER ... IGNORED, so restoring reproduces the state exactly rather than
silently re-enabling something that was switched off on purpose.
"""
import subprocess, sys, os, getpass, collections, datetime

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCK = sys.argv[1] if len(sys.argv) > 1 else f"{REPO}/pagesize/s32-sf4.sock"
OUT = sys.argv[2] if len(sys.argv) > 2 else f"{REPO}/sql/all_indexes.sql"

Q = """
SELECT s.TABLE_NAME, s.INDEX_NAME, s.SEQ_IN_INDEX, s.COLUMN_NAME,
       s.NON_UNIQUE, IFNULL(s.SUB_PART,0), IFNULL(s.IGNORED,'NO')
FROM information_schema.STATISTICS s
WHERE s.TABLE_SCHEMA = 'tpcds' AND s.INDEX_NAME <> 'PRIMARY'
ORDER BY s.TABLE_NAME, s.INDEX_NAME, s.SEQ_IN_INDEX
"""


def main():
    p = subprocess.run(
        ["mariadb", f"--socket={SOCK}", f"--user={getpass.getuser()}",
         "-B", "-N", "tpcds", "-e", " ".join(Q.split())],
        capture_output=True, text=True)
    if p.returncode:
        sys.exit(f"could not read the schema: {p.stderr.strip()[:200]}")

    idx = collections.OrderedDict()
    for line in p.stdout.strip().splitlines():
        tbl, name, seq, col, non_uniq, sub, ignored = line.split("\t")
        k = (tbl, name)
        e = idx.setdefault(k, {"cols": [], "unique": non_uniq == "0",
                               "ignored": ignored.upper() == "YES"})
        e["cols"].append(f"{col}({sub})" if sub != "0" else col)

    by_table = collections.OrderedDict()
    for (tbl, name), e in idx.items():
        by_table.setdefault(tbl, []).append((name, e))

    n_ign = sum(1 for e in idx.values() if e["ignored"])
    L = [
        "-- " + "=" * 72,
        "--  Every secondary index in tpcds, in one file.",
        "--",
        f"--  Generated {datetime.datetime.now():%Y-%m-%d %H:%M} by "
        "scripts/dump-indexes.py from the live schema.",
        f"--  {len(idx)} indexes across {len(by_table)} tables"
        + (f", {n_ign} of them currently IGNORED." if n_ign else "."),
        "--",
        "--  RESTORE EVERYTHING:",
        "--      mariadb tpcds < sql/all_indexes.sql",
        "--",
        "--  This is what makes dropping an index safe to try.  'Unused' is",
        "--  not a property of an index: it is a property of an index AND a",
        "--  workload AND a configuration.  The same index set measured at",
        "--  16K and 32K pages disagreed about which members were idle",
        "--  (report/17, report/22), so an index that looks dead today may",
        "--  be read millions of times after a settings change.",
        "--",
        "--  Prefer ALTER TABLE <t> ALTER INDEX <i> IGNORED when the question",
        "--  is whether an index earns its keep: it is metadata-only, takes",
        "--  about 0.15s, reverses instantly, and leaves the index on disk.",
        "--  Drop only when you actually need the space back.",
        "-- " + "=" * 72,
        "",
        "SET SESSION alter_algorithm='INPLACE';",
        "",
    ]
    for tbl, items in by_table.items():
        L.append(f"-- {tbl}  ({len(items)} indexes)")
        for name, e in items:
            uniq = "UNIQUE " if e["unique"] else ""
            L.append(f"CREATE {uniq}INDEX IF NOT EXISTS {name} ON {tbl} "
                     f"({', '.join(e['cols'])});")
        L.append("")

    ign = [(t, n) for (t, n), e in idx.items() if e["ignored"]]
    if ign:
        L += ["-- Indexes that were IGNORED when this file was generated.",
              "-- Restoring reproduces that state rather than silently",
              "-- re-enabling something switched off deliberately.", ""]
        for t, n in ign:
            L.append(f"ALTER TABLE {t} ALTER INDEX {n} IGNORED;")
        L.append("")

    L += ["ANALYZE TABLE " + ", ".join(by_table) + ";", ""]
    open(OUT, "w").write("\n".join(L))
    print(f"  wrote {OUT}")
    print(f"  {len(idx)} indexes, {len(by_table)} tables"
          + (f", {n_ign} IGNORED" if n_ign else ""))


if __name__ == "__main__":
    main()
