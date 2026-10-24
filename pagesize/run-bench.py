#!/usr/bin/env python3
"""Run all 99 TPC-DS queries against one page-size lab instance.

usage: run-bench.py <PAGE_KB> [RUN_TAG]

RUN_TAG suffixes the output directory, so a repeat pass can be compared
against the first to tell a real page-size effect from plan noise.

Records, per query: wall time, row count, and an md5 of the output.  The md5
lets us prove afterwards that all four page sizes return identical results —
page size must not change an answer, only how fast it arrives.

Results go to pagesize/results/<PAGE_KB>k/query<N>.json.
"""
import subprocess, sys, os, json, time, hashlib, getpass

REPO = "/Users/hosseinaghaei/Desktop/projects/dw"
LAB = f"{REPO}/pagesize"
QDIR = f"{REPO}/queries/mariadb"
PRE = ("SET SESSION sql_mode="
       "CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');")


def main():
    page = sys.argv[1]
    tag = sys.argv[2] if len(sys.argv) > 2 else ""
    sock = f"{LAB}/s{page}.sock"
    me = getpass.getuser()
    rdir = f"{LAB}/results/{page}k{('-' + tag) if tag else ''}"
    os.makedirs(rdir, exist_ok=True)

    base = ['mariadb', f'--socket={sock}', f'--user={me}', '-B',
            '--default-character-set=utf8mb4', 'tpcds']

    got = subprocess.run(base + ['-N', '-e', 'select @@innodb_page_size/1024'],
                         capture_output=True, text=True)
    actual = got.stdout.strip().split('.')[0]
    if actual != page:
        sys.exit(f"instance on {sock} reports {actual}K, expected {page}K")
    print(f"=== {page}K pages, socket {sock}", flush=True)

    total = 0.0
    for n in range(1, 100):
        path = f"{QDIR}/query{n}.sql"
        if not os.path.exists(path):
            continue
        stmts = [s.strip() for s in open(path).read().split(';') if s.strip()]
        out, err, t0 = [], None, time.time()
        for st in stmts:
            p = subprocess.run(base + ['-e', PRE + st],
                               capture_output=True, text=True, timeout=1800)
            if p.returncode:
                e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
                err = (e[0] if e else p.stderr.strip())[:200]
                break
            out.append(p.stdout)
        secs = round(time.time() - t0, 1)
        total += secs

        r = {'query': n, 'page_kb': int(page), 'seconds': secs}
        if err:
            r['status'] = 'ERROR'
            r['detail'] = err
        else:
            text = "\n===\n".join(out)
            r['rows'] = max(0, len(text.strip().splitlines()) - 1)
            r['md5'] = hashlib.md5(text.encode()).hexdigest()
            r['status'] = 'OK'
        json.dump(r, open(f"{rdir}/query{n}.json", 'w'), indent=1)
        print(f"query{n:<3} {r['status']:<6} {secs:>7.1f}s "
              f"rows={r.get('rows','-')} {r.get('detail','')}", flush=True)

    print(f"=== {page}K total {total:.1f}s ({total/60:.1f} min)", flush=True)

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
