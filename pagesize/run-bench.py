#!/usr/bin/env python3
"""Run all 99 TPC-DS queries against one page-size lab instance.

usage: run-bench.py <PAGE_KB> [RUN_TAG] [--socket PATH] [--timeout SEC]
                    [--queries all|tier45]

--queries tier45 (the default) runs only the 40 tier-4 and tier-5 queries.
Tiers 1-3 are sub-second queries whose timings are dominated by connection and
parse overhead, so including them pads totals with noise.  The lists are read
from queries/tiers/04_*.sql and 05_*.sql, which are generated from measured
timings, rather than hardcoded.

RUN_TAG suffixes the output directory, so a repeat pass can be compared
against the first to tell a real page-size effect from plan noise.

Records, per query: wall time, row count, and two hashes of the output.

  md5        the output verbatim, order included
  md5_sorted the header plus the data rows sorted

Comparing both tells a real answer change from mere row-order instability:
queries whose ORDER BY is not a total order (q71 has 2160 of 3948 rows tied;
q65 has 7 of 100 and a LIMIT, so even the row *set* is under-determined) will
differ in md5 but agree in md5_sorted.

Results go to pagesize/results/<PAGE_KB>k/query<N>.json.
"""
import subprocess, sys, os, json, time, hashlib, getpass, re, glob

REPO = "/Users/hosseinaghaei/Desktop/projects/dw"
LAB = f"{REPO}/pagesize"
QDIR = f"{REPO}/queries/mariadb"
PRE = ("SET SESSION sql_mode="
       "CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');")


def tier45():
    """Query numbers in tier 4 and tier 5, read from the generated tier files."""
    ns = set()
    for pat in (f"{REPO}/queries/tiers/04_*.sql", f"{REPO}/queries/tiers/05_*.sql"):
        for f in glob.glob(pat):
            ns |= {int(m) for m in re.findall(r'query(\d+)', open(f).read())}
    if not ns:
        sys.exit("could not read the tier files")
    return sorted(ns)


def main():
    argv = sys.argv[1:]
    sock_override, timeout, which = None, 1800, 'tier45'
    if '--queries' in argv:
        i = argv.index('--queries')
        which = argv[i + 1]
        del argv[i:i + 2]
    for flag, conv in (('--socket', str), ('--timeout', int)):
        if flag in argv:
            i = argv.index(flag)
            val = conv(argv[i + 1])
            del argv[i:i + 2]
            if flag == '--socket':
                sock_override = val
            else:
                timeout = val

    page = argv[0]
    tag = argv[1] if len(argv) > 1 else ""
    sock = sock_override or f"{LAB}/s{page}.sock"
    me = getpass.getuser()
    rdir = f"{LAB}/results/{page}k{('-' + tag) if tag else ''}"
    os.makedirs(rdir, exist_ok=True)

    # derive the scale factor from the socket: the SF=4 instances use
    # s<page>-sf4.sock.  Recorded per query so consolidation never has to
    # guess it from a directory name.
    scale = 4 if 'sf4' in os.path.basename(sock) else 1

    # Record the sampling depth and index count the run actually saw, rather
    # than leaving consolidation to infer them from the directory name.  The
    # tuning runs are a case in point: tagged t1-config etc., they carry no
    # hint of sf4/sample160/188 indexes in their name.
    def ask(sql):
        return subprocess.run(['mariadb', f'--socket={sock}', f'--user={me}',
                               '-N', '-B', 'tpcds', '-e', sql],
                              capture_output=True, text=True).stdout.strip()
    sample = int(ask('select @@innodb_stats_persistent_sample_pages') or 0)
    nidx = int(ask("select count(distinct table_name,index_name) "
                   "from information_schema.statistics "
                   "where table_schema='tpcds'") or 0)

    base = ['mariadb', f'--socket={sock}', f'--user={me}', '-B',
            '--default-character-set=utf8mb4', 'tpcds']

    got = subprocess.run(base + ['-N', '-e', 'select @@innodb_page_size/1024'],
                         capture_output=True, text=True)
    actual = got.stdout.strip().split('.')[0]
    if actual != page:
        sys.exit(f"instance on {sock} reports {actual}K, expected {page}K")
    wanted = list(range(1, 100)) if which == 'all' else tier45()
    print(f"=== {page}K pages, SF={scale}, sample={sample}, {nidx} indexes, "
          f"{len(wanted)} queries ({which}), timeout {timeout}s", flush=True)

    total = 0.0
    for n in wanted:
        path = f"{QDIR}/query{n}.sql"
        if not os.path.exists(path):
            continue
        stmts = [s.strip() for s in open(path).read().split(';') if s.strip()]
        out, err, t0 = [], None, time.time()
        for st in stmts:
            p = subprocess.run(base + ['-e', PRE + st],
                               capture_output=True, text=True, timeout=timeout)
            if p.returncode:
                e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
                err = (e[0] if e else p.stderr.strip())[:200]
                break
            out.append(p.stdout)
        secs = round(time.time() - t0, 1)
        total += secs

        r = {'query': n, 'page_kb': int(page), 'scale': scale,
             'sample_pages': sample, 'indexes': nidx, 'seconds': secs}
        if err:
            r['status'] = 'ERROR'
            r['detail'] = err
        else:
            text = "\n===\n".join(out)
            lines = text.strip().splitlines()
            r['rows'] = max(0, len(lines) - 1)
            r['md5'] = hashlib.md5(text.encode()).hexdigest()
            ordered = ("\n".join(lines[:1] + sorted(lines[1:]))).encode()
            r['md5_sorted'] = hashlib.md5(ordered).hexdigest()
            r['status'] = 'OK'
        json.dump(r, open(f"{rdir}/query{n}.json", 'w'), indent=1)
        print(f"query{n:<3} {r['status']:<6} {secs:>7.1f}s "
              f"rows={r.get('rows','-')} {r.get('detail','')}", flush=True)

    print(f"=== {page}K total {total:.1f}s ({total/60:.1f} min) "
          f"over {len(wanted)} {which} queries", flush=True)

    # storage footprint, per table
    sizes = subprocess.run(base + ['-N', '-e', """
        select table_name, table_rows, data_length, index_length
        from information_schema.tables where table_schema='tpcds'
        order by table_name"""], capture_output=True, text=True).stdout
    rows = [l.split('\t') for l in sizes.strip().splitlines()]
    json.dump({'page_kb': int(page), 'total_seconds': round(total, 1),
               'tables': [{'name': r[0], 'rows': int(r[1]),
                           'data': int(r[2]), 'index': int(r[3])} for r in rows]},
              open(f"{rdir}/_storage.json", 'w'), indent=1)


main()
