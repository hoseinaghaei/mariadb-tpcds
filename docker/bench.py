#!/usr/bin/env python3
"""Run the TPC-DS query set against the container's MariaDB and record timings.

usage: bench.py <socket> <outdir> <tag> [all|tier45]

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
    which = sys.argv[4] if len(sys.argv) > 4 else 'tier45'
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

    wanted = list(range(1, 100)) if which == 'all' else tier45()
    print(f"=== {tag}: {page}K pages, {pool/2**30:.0f}G pool, sample={sample}, "
          f"{nidx} indexes, {len(wanted)} queries ({which})", flush=True)

    total, errors = 0.0, 0
    for n in wanted:
        path = f"{QDIR}/query{n}.sql"
        if not os.path.exists(path):
            continue
        stmts = [s.strip() for s in open(path).read().split(';') if s.strip()]
        out, err, t0 = [], None, time.time()
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

        r = {'query': n, 'tag': tag, 'page_kb': page, 'sample_pages': sample,
             'indexes': nidx, 'seconds': secs}
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
          f"{len(wanted)} queries, {errors} errors", flush=True)
    json.dump({'tag': tag, 'total_seconds': round(total, 1),
               'queries': len(wanted), 'errors': errors,
               'page_kb': page, 'sample_pages': sample, 'indexes': nidx,
               'buffer_pool_bytes': pool, 'queryset': which},
              open(f"{outdir}/_summary.json", 'w'), indent=1)


main()
