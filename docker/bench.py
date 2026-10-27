#!/usr/bin/env python3
"""Run the TPC-DS query set against the container's MariaDB and record timings.

usage: bench.py <socket> <outdir> <tag> [all|tier45|tuned|smoke]
       bench.py --check <outdir> <queryset>

Query sets:

  all      the 99 adapted TPC-DS queries, unoptimized
  tier45   the 40 tier-4/5 queries, unoptimized
  tuned    the same 40, but running queries/tuned/ -- the team's optimized
           query where one exists (33 of 40), the adapted original otherwise
  smoke    adapted queries 3, 12, 18 and 76: joins, windows, rollups and NULL
           filters, without the tuned files' session memory overrides

`tuned` is the default, because it is what the project's results are about.
Use `tier45` to measure the server tuning on its own, with the query text
held constant.

HOW `tuned` IS RUN, AND WHY IT DIFFERS.  Files in queries/tuned/ carry their
own `SET SESSION` lines -- sql_mode for every query, split_materialized=off
for six, and three buffer settings that Aysha's q14 sets -- so each file is
fed WHOLE on stdin and executed in one session.  The other sets split on
';' and send each statement separately, which would put every SET in its own
connection and discard it before the query ran.  That is not a stylistic
difference: it is the whole point of those files.

Records per query: wall time, row count, and two hashes of the output --
one verbatim, one with the data rows sorted.  The pair distinguishes a real
answer change from mere row-order instability: several TPC-DS queries have an
ORDER BY that is not a total order (q71 has 2160 of 3948 rows tied at SF=4;
q65 has 7 of 100 tied plus a LIMIT, so even its row set is under-determined),
and those differ in md5 while agreeing in md5_sorted.

PIPES_AS_CONCAT is required: TPC-DS uses ANSI '||' for string concatenation
in q5, q66, q80 and q84.  Without it MariaDB reads '||' as logical OR and
those queries silently return 0/1 in place of the concatenated id, which
collapses q5 and q80 from 100 rows to 7.
"""
import subprocess, sys, os, json, time, hashlib, re, glob
from pathlib import Path

PROJECT = "/project"
QDIR = f"{PROJECT}/queries/mariadb"
TDIR = f"{PROJECT}/queries/tuned"
PRE = ("SET SESSION sql_mode="
       "CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');")
SMOKE_QUERIES = (3, 12, 18, 76)


def tier45():
    """Query numbers in tiers 4 and 5, read from the generated tier files."""
    ns = set()
    for pat in (f"{PROJECT}/queries/tiers/04_*.sql",
                f"{PROJECT}/queries/tiers/05_*.sql"):
        for f in glob.glob(pat):
            ns |= {int(m) for m in re.findall(r'query(\d+)', Path(f).read_text())}
    if not ns:
        sys.exit("could not read the tier files under queries/tiers/")
    return sorted(ns)


def query_items(which):
    """Resolve an exact workload; missing files must not silently reduce it."""
    if which == 'smoke':
        wanted = SMOKE_QUERIES
    elif which == 'all':
        wanted = range(1, 100)
    elif which in ('tier45', 'tuned'):
        wanted = tier45()
    else:
        raise ValueError(f"query set must be all, tier45, tuned or smoke (got {which})")
    directory = TDIR if which == 'tuned' else QDIR
    items = [(n, f"{directory}/query{n}.sql") for n in wanted]
    missing = [path for _, path in items if not os.path.isfile(path)]
    if missing:
        raise ValueError("missing query files: " + ", ".join(missing))
    return items


def verify_run(outdir, which):
    """Check coverage, SQL success and hashes, including sub-five-second runs.

    These checks establish execution completeness, not reference-answer equality.
    """
    wanted = {n for n, _ in query_items(which)}
    directory = Path(outdir)
    summary = json.loads((directory / '_summary.json').read_text())
    if (summary.get('errors') != 0 or summary.get('queries') != len(wanted)
            or summary.get('queryset') != which
            or sorted(summary.get('query_ids', [])) != sorted(wanted)):
        raise ValueError("run summary reports errors or an incomplete/different workload")
    expected_files = {f'query{n}.json' for n in wanted}
    if {p.name for p in directory.glob('query*.json')} != expected_files:
        raise ValueError("missing or unexpected per-query artifacts; use a separate results directory")
    for n in sorted(wanted):
        result = json.loads((directory / f'query{n}.json').read_text())
        if (result.get('query') != n or result.get('status') != 'OK'
                or result.get('queryset') != which
                or not all(isinstance(result.get(key), str)
                           and re.fullmatch(r'[0-9a-f]{32}', result[key])
                           for key in ('md5', 'md5_sorted'))):
            raise ValueError(f"query{n} failed or lacks valid result hashes")
    return len(wanted)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--check':
        if len(sys.argv) != 4:
            raise ValueError("usage: bench.py --check <outdir> <queryset>")
        count = verify_run(sys.argv[2], sys.argv[3])
        print(f"Validated {count}/{count} successful query artifacts", flush=True)
        return 0
    sock, outdir, tag = sys.argv[1], sys.argv[2], sys.argv[3]
    which = sys.argv[4] if len(sys.argv) > 4 else 'tuned'
    items = query_items(which)
    profile = os.environ.get('PROFILE', 'unspecified')
    timeout_seconds = int(os.environ.get('STATEMENT_TIMEOUT', '3600'))
    if timeout_seconds < 1:
        raise ValueError("STATEMENT_TIMEOUT must be positive")
    pre = PRE + f"SET SESSION max_statement_time={timeout_seconds};"
    os.makedirs(outdir, exist_ok=True)

    base = ['mariadb', f'--socket={sock}', '-u', 'root', '-B',
            '--default-character-set=utf8mb4', 'tpcds']

    def ask(sql):
        p = subprocess.run(base + ['-N', '-e', sql], capture_output=True, text=True)
        if p.returncode:
            raise ValueError("could not read server configuration: " + p.stderr.strip())
        return p.stdout.strip()

    page = int(ask('select @@innodb_page_size') or 0) // 1024
    sample = int(ask('select @@innodb_stats_persistent_sample_pages') or 0)
    pool = int(ask('select @@innodb_buffer_pool_size') or 0)
    nidx = int(ask("select count(distinct table_name,index_name) "
                   "from information_schema.statistics "
                   "where table_schema='tpcds'") or 0)

    settings = {key: int(ask(f'select @@{key}')) for key in (
        'tmp_table_size', 'max_heap_table_size', 'aria_pagecache_buffer_size',
        'sort_buffer_size', 'join_buffer_size', 'join_buffer_space_limit')}

    print(f"=== {tag}: {page}K pages, {pool/2**30:.0f}G pool, sample={sample}, "
          f"{nidx} indexes, {len(items)} queries ({which})", flush=True)

    total, errors = 0.0, 0
    for n, path in items:
        out, err, t0 = [], None, time.perf_counter()
        if which == 'tuned':
            # Whole file, one session: its SET SESSION lines must reach the
            # query.  It may also hold more than one statement (q14, q23).
            with open(path) as fh:
                try:
                    p = subprocess.run(base, stdin=fh, capture_output=True,
                                       text=True, timeout=2 * timeout_seconds + 30)
                except subprocess.TimeoutExpired:
                    p = None
                    err = 'client timeout'
            if p is not None and p.returncode:
                e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
                err = (e[0] if e else p.stderr.strip())[:200]
            elif p is not None:
                out.append(p.stdout)
        else:
            stmts = [s.strip() for s in Path(path).read_text().split(';') if s.strip()]
            for st in stmts:
                try:
                    p = subprocess.run(base + ['-e', pre + st],
                                       capture_output=True, text=True, timeout=timeout_seconds + 30)
                except subprocess.TimeoutExpired:
                    err = 'client timeout'
                    break
                if p.returncode:
                    e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
                    err = (e[0] if e else p.stderr.strip())[:200]
                    break
                out.append(p.stdout)
        secs = round(time.perf_counter() - t0, 1)
        total += secs

        r = {'query': n, 'tag': tag, 'profile': profile, 'queryset': which, 'page_kb': page,
             'sql_sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(),
             'sample_pages': sample, 'indexes': nidx, 'seconds': secs}
        if err:
            r.update(status='ERROR', detail=err)
            errors += 1
        else:
            text = "\n===\n".join(out)
            lines = text.strip().splitlines()
            r['rows'] = max(0, len(lines) - 1)
            r['md5'] = hashlib.md5(text.encode()).hexdigest()
            r['md5_sorted'] = hashlib.md5(
                ("\n".join(lines[:1] + sorted(lines[1:]))).encode()).hexdigest()
            r['status'] = 'OK'
        Path(outdir, f'query{n}.json').write_text(json.dumps(r, indent=1) + '\n')
        print(f"  query{n:<4} {r['status']:<6} {secs:>8.1f}s "
              f"rows={r.get('rows','-')} {r.get('detail','')}", flush=True)

    print(f"=== {tag} TOTAL {total:.1f}s ({total/60:.1f} min) over "
          f"{len(items)} queries, {errors} errors", flush=True)
    # Record what database this was: a scale factor alone does not identify
    # one.  dsdgen with a different -RNGSEED builds different data at the same
    # scale, and then answers differ legitimately.  Comparing two runs without
    # knowing both seeds produced 37 bogus "answer mismatches" once.
    summary = {'tag': tag, 'total_seconds': round(total, 1),
               'profile': profile,
               'purpose': 'functional-check' if which == 'smoke' else 'performance-experiment',
               'scale': int(os.environ.get('SCALE', 0)) or None,
               'rngseed': os.environ.get('RNGSEED'),
               'queries': len(items), 'errors': errors,
               'query_ids': [n for n, _ in items],
               'statement_timeout_seconds': timeout_seconds,
               'server_settings_bytes': settings,
               'page_kb': page, 'sample_pages': sample, 'indexes': nidx,
               'buffer_pool_bytes': pool, 'queryset': which}
    Path(outdir, '_summary.json').write_text(json.dumps(summary, indent=1) + '\n')
    verify_run(outdir, which)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as exc:
        sys.exit(f"ERROR: {exc}")
