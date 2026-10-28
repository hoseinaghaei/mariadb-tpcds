#!/usr/bin/env python3
"""Emit the CREATE INDEX statements for the full set, minus a drop list.

    python3 scripts/emit-index-ddl.py [--exclude sql/drop_unreferenced_indexes.sql]

The index stage used to run every CREATE in sql/05, 11 and 14 with IF NOT
EXISTS and then drop the pruned ones afterwards.  That is correct and very
wasteful: on a pruned SF=4 database it rebuilds 71 indexes for the sole
purpose of deleting them again, which is twenty minutes of nothing.

Statements are split on semicolons rather than lines, because a definition
may span several lines -- the two query66 covering indexes do.
"""
import argparse, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ("sql/05_indexes.sql", "sql/11_optimizer_indexes.sql",
         "sql/14_contributed_indexes.sql")
CREATE = re.compile(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(\w+)\s+ON\s+(\w+)', re.I)


def statements(text):
    """Split on `;`, ignoring ones inside comments or strings."""
    out, cur, i, n = [], [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "'\"":
            q = c; cur.append(c); i += 1
            while i < n:
                cur.append(text[i])
                if text[i] == q:
                    i += 1; break
                i += 1
            continue
        if text.startswith("--", i) or text.startswith("#", i):
            j = text.find("\n", i); i = n if j < 0 else j + 1
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); i = n if j < 0 else j + 2
            continue
        if c == ";":
            out.append("".join(cur).strip()); cur = []; i += 1
            continue
        cur.append(c); i += 1
    if "".join(cur).strip():
        out.append("".join(cur).strip())
    return [s for s in out if s]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exclude", help="a file of DROP INDEX statements to skip")
    ap.add_argument("--root", default=REPO)
    ap.add_argument("--count", action="store_true", help="print the count only")
    ap.add_argument("--list", action="store_true",
                    help="print `table.index` per line instead of DDL, for "
                         "comparing the database against the schema by name")
    a = ap.parse_args()

    skip = set()
    if a.exclude and os.path.exists(a.exclude):
        for line in open(a.exclude):
            m = re.match(r'DROP INDEX IF EXISTS (\w+) ON (\w+);', line.strip())
            if m:
                skip.add((m.group(2).lower(), m.group(1).lower()))

    seen, out, listed = set(), [], []
    for f in FILES:
        p = os.path.join(a.root, f)
        if not os.path.exists(p):
            continue
        for st in statements(open(p).read()):
            m = CREATE.search(st)
            if not m:
                continue
            key = (m.group(2).lower(), m.group(1).lower())
            if key in skip or key in seen:
                continue           # nine indexes are defined twice
            seen.add(key)
            listed.append(f"{key[0]}.{key[1]}")
            out.append(re.sub(r'^CREATE\s+INDEX\s', 'CREATE INDEX IF NOT EXISTS ',
                              st, count=1, flags=re.I) + ";")
    if a.count:
        print(len(out))
    elif a.list:
        print("\n".join(sorted(listed)))
    else:
        print("\n".join(out))


if __name__ == "__main__":
    main()
