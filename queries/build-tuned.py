#!/usr/bin/env python3
"""Generate queries/tuned/ — one self-contained .sql per query, carrying any
per-query optimizer setting that was measured to help.

At present the only such setting is split_materialized.  q59 referenced its
CTE twice and MariaDB re-materialised one reference 7,665 times, once per
outer row; turning the strategy off for that query takes it from 151.8s to
13.7s.  Nine other queries also improve, four get worse, and 26 are
unaffected, so the setting is applied per query rather than globally:

    split off everywhere   867.5s
    split on everywhere    971.4s
    per query              777.7s   <- what these files produce

Measured on 32K pages / SF=4 / 8G pool / sample 160 under the T1 tuning.
Re-generate with:  python3 queries/build-tuned.py
"""
import os, re, glob, json

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = f"{REPO}/queries/mariadb"
DST = f"{REPO}/queries/tuned"

NOSPLIT = "SET SESSION optimizer_switch = 'split_materialized=off';"

# Every file gets this so it is correct when run on its own.  TPC-DS uses the
# ANSI '||' for string concatenation in q5, q66, q80 and q84; without
# PIPES_AS_CONCAT MariaDB reads it as logical OR, which silently returns 0/1
# in place of the concatenated id -- q5 and q80 then give 7 rows instead of
# 100.  IGNORE_SPACE allows the function-name spacing the generated SQL uses.
SQLMODE = ("SET SESSION sql_mode = "
           "CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');")
PIPES = (5, 66, 80, 84)

# Measured delta in seconds when split materialisation is turned OFF
# (negative = turning it off is faster).  From 32k-s0-t1baseline vs
# 32k-t6-nosplit, tier 4+5, SF=4.
DELTA = {59: -138.1, 14: -17.0, 2: -9.5, 5: -8.9, 11: -5.6, 27: -3.7,
         68: -1.9, 72: -1.6, 46: -1.6, 22: -1.3,
         57: +3.2, 78: +13.9, 4: +14.6, 23: +54.0}

# Only act where the measurement is larger than this host's run-to-run noise.
# The 1-2s cases (q68, q72, q46, q22) are inside it and are left alone: a
# single run cannot tell a 1.6s gain from a 1.6s fluctuation.
THRESHOLD = 3.0
APPLY = sorted(q for q, d in DELTA.items() if d <= -THRESHOLD)
MARGINAL = sorted(q for q, d in DELTA.items() if -THRESHOLD < d < 0)
WORSE = sorted(q for q, d in DELTA.items() if d > 0)


def header(n):
    pre = ""
    if n in PIPES:
        pre += (f"-- query{n} concatenates with the ANSI '||' operator, so it needs\n"
                f"-- PIPES_AS_CONCAT: without it MariaDB reads '||' as logical OR and\n"
                f"-- this query returns the wrong number of rows, silently.\n")
    pre += f"{SQLMODE}\n\n"

    if n in APPLY:
        return (f"-- query{n}: split materialisation disabled for this query.\n"
                f"-- Measured {DELTA[n]:+.1f}s at SF=4 / 32K / tier 4+5 "
                f"(see queries/tuned/README.md).\n"
                f"-- The setting is session-scoped, so it affects only this query.\n\n"
                f"{pre}{NOSPLIT}\n\n")
    note = ""
    if n in WORSE:
        note = (f"-- query{n}: split materialisation left ON deliberately -- "
                f"disabling it measured {DELTA[n]:+.1f}s (slower).\n\n")
    elif n in MARGINAL:
        note = (f"-- query{n}: disabling split materialisation measured "
                f"{DELTA[n]:+.1f}s, inside this host's run-to-run noise,\n"
                f"-- so it is left at the default.\n\n")
    return note + pre


def main():
    os.makedirs(DST, exist_ok=True)
    for old in glob.glob(f"{DST}/query*.sql"):
        os.remove(old)

    written = 0
    for path in sorted(glob.glob(f"{SRC}/query*.sql"),
                       key=lambda p: int(re.search(r'query(\d+)', p).group(1))):
        n = int(re.search(r'query(\d+)', path).group(1))
        body = open(path).read()
        open(f"{DST}/query{n}.sql", 'w').write(header(n) + body)
        written += 1

    print(f"wrote {written} files to queries/tuned/")
    print(f"  split_materialized=off applied to {len(APPLY)}: {APPLY}")
    print(f"  left default, measured worse ({len(WORSE)}): {WORSE}")
    print(f"  left default, inside noise ({len(MARGINAL)}): {MARGINAL}")
    print(f"  untouched (no measurement or no effect): "
          f"{written - len(APPLY) - len(WORSE) - len(MARGINAL)}")


main()
