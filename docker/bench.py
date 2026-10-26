#!/usr/bin/env python3
"""Run the TPC-DS query set against the container's MariaDB and record timings.

usage: bench.py <socket> <outdir> <tag> [all|tier45|tuned]

Three query sets:

  all      the 99 adapted TPC-DS queries, unoptimized
  tier45   the 40 tier-4/5 queries, unoptimized
  tuned    the same 40, but running queries/tuned/ -- the team's optimized
           query where one exists (33 of 40), the adapted original otherwise

`tuned` is the default, because it is what the project's results are about.
Use `tier45` to measure the server tuning on its own, with the query text
held constant.

HOW `tuned` IS RUN, AND WHY IT DIFFERS.  Files in queries/tuned/ carry their
own `SET SESSION` lines -- sql_mode for every query, split_materialized=off
for six, and three buffer settings that Aysha's q14 sets -- so each file is
fed WHOLE on stdin and executed in one session.  The other two sets split on
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

PROJECT = "/project"
QDIR = f"{PROJECT}/queries/mariadb"
TDIR = f"{PROJECT}/queries/tuned"
PRE = ("SET SESSION sql_mode="
       "CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');")


def tier45():
    """Query numbers in tiers 4 and 5, read from the generated tier files."""
    ns = set()
    for pat in (f"{PROJECT}/queries/tiers/04_*.sql",
                f"{PROJECT}/queries/tiers/05_*.sql"):
        for f in glob.glob(pat):
            ns |= {int(m) for m in re.findall(r'query(\d+)', open(f).read())}
    if not ns:
        sys.exit("could not read the tier files under queries/tiers/")
    return sorted(ns)


def main():
    sock, outdir, tag = sys.argv[1], sys.argv[2], sys.argv[3]
    which = sys.argv[4] if len(sys.argv) > 4 else 'tuned'
    if which not in ('all', 'tier45', 'tuned'):
        sys.exit(f"query set must be all, tier45 or tuned (got {which})")
    os.makedirs(outdir, exist_ok=True)

    base = ['mariadb', f'--socket={sock}', '-u', 'root', '-B',
            '--default-character-set=utf8mb4', 'tpcds']

    def ask(sql):
        p = subprocess.run(base + ['-N', '-e', sql], capture_output=True, text=True)
        return p.stdout.strip()

    page = int(ask('select @@innodb_page_size') or 0) // 1024
    sample = int(ask('select @@innodb_stats_persistent_sample_pages') or 0)
    pool = int(ask('select @@innodb_buffer_pool_size') or 0)
    nidx = int(ask("select count(distinct table_name,index_name) "
                   "from information_schema.statistics "
                   "where table_schema='tpcds'") or 0)

    if which == 'tuned':
        items = sorted(
            ((int(re.search(r'query(\d+)', p).group(1)), p)
             for p in glob.glob(f"{TDIR}/query*.sql")))
        if not items:
            sys.exit(f"no tuned queries under {TDIR}; run queries/build-tuned.py")
    else:
        wanted = list(range(1, 100)) if which == 'all' else tier45()
        items = [(n, f"{QDIR}/query{n}.sql") for n in wanted
                 if os.path.exists(f"{QDIR}/query{n}.sql")]

    print(f"=== {tag}: {page}K pages, {pool/2**30:.0f}G pool, sample={sample}, "
          f"{nidx} indexes, {len(items)} queries ({which})", flush=True)

    total, errors = 0.0, 0
    for n, path in items:
        out, err, t0 = [], None, time.time()
        if which == 'tuned':
            # Whole file, one session: its SET SESSION lines must reach the
            # query.  It may also hold more than one statement (q14, q23).
            with open(path) as fh:
                p = subprocess.run(base, stdin=fh, capture_output=True,
                                   text=True, timeout=7200)
            if p.returncode:
                e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
                err = (e[0] if e else p.stderr.strip())[:200]
            else:
                out.append(p.stdout)
        else:
            stmts = [s.strip() for s in open(path).read().split(';') if s.strip()]
            for st in stmts:
                p = subprocess.run(base + ['-e', PRE + st],
                                   capture_output=True, text=True, timeout=7200)
                if p.returncode:
                    e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
                    err = (e[0] if e else p.stderr.strip())[:200]
                    break
                out.append(p.stdout)
        secs = round(time.time() - t0, 1)
        total += secs

        r = {'query': n, 'tag': tag, 'queryset': which, 'page_kb': page,
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
        json.dump(r, open(f"{outdir}/query{n}.json", 'w'), indent=1)
        print(f"  query{n:<4} {r['status']:<6} {secs:>8.1f}s "
              f"rows={r.get('rows','-')} {r.get('detail','')}", flush=True)

    print(f"=== {tag} TOTAL {total:.1f}s ({total/60:.1f} min) over "
          f"{len(items)} queries, {errors} errors", flush=True)
    # Record what database this was: a scale factor alone does not identify
    # one.  dsdgen with a different -RNGSEED builds different data at the same
    # scale, and then answers differ legitimately.  Comparing two runs without
    # knowing both seeds produced 37 bogus "answer mismatches" once.
    json.dump({'tag': tag, 'total_seconds': round(total, 1),
               'scale': int(os.environ.get('SCALE', 0)) or None,
               'rngseed': os.environ.get('RNGSEED'),
               'queries': len(items), 'errors': errors,
               'page_kb': page, 'sample_pages': sample, 'indexes': nidx,
               'buffer_pool_bytes': pool, 'queryset': which},
              open(f"{outdir}/_summary.json", 'w'), indent=1)


main()
