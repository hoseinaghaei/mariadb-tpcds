#!/usr/bin/env python3
"""Run queries/tuned/ (the 40 tier-4/5 files) against one instance.

usage: bench-tuned.py <socket> <tag> [--timeout SEC]

Each file is fed WHOLE on stdin, so the `SET SESSION` lines it carries --
sql_mode and, for six queries, split_materialized=off -- take effect in the
same session as the query.  Passing the statements separately would lose
them, which is the whole point of these files.
"""
import subprocess, sys, os, json, time, hashlib, glob, re, getpass

REPO = "/Users/hosseinaghaei/Desktop/projects/dw"
TUNED = f"{REPO}/queries/tuned"
LAB = f"{REPO}/pagesize"


def main():
    argv = sys.argv[1:]
    timeout = 5400
    if '--timeout' in argv:
        i = argv.index('--timeout')
        timeout = int(argv[i + 1]); del argv[i:i + 2]
    sock, tag = argv[0], argv[1]
    me = getpass.getuser()
    rdir = f"{LAB}/results/{tag}"
    os.makedirs(rdir, exist_ok=True)

    base = ['mariadb', f'--socket={sock}', f'--user={me}', '-B',
            '--default-character-set=utf8mb4', 'tpcds']

    def ask(sql):
        return subprocess.run(base + ['-N', '-e', sql],
                              capture_output=True, text=True).stdout.strip()

    page = int(ask('select @@innodb_page_size') or 0) // 1024
    pool = int(ask('select @@innodb_buffer_pool_size') or 0)
    smpl = int(ask('select @@innodb_stats_persistent_sample_pages') or 0)
    tmp = int(ask('select @@tmp_table_size') or 0)
    jcl = ask('select @@join_cache_level')
    rows = int(ask("select table_rows from information_schema.tables "
                   "where table_schema='tpcds' and table_name='store_sales'") or 0)
    sf = 4 if rows > 8_000_000 else 1

    files = sorted(glob.glob(f"{TUNED}/query*.sql"),
                   key=lambda p: int(re.search(r'query(\d+)', p).group(1)))
    print(f"=== {tag}: SF~{sf}, {page}K pages, {pool/2**30:.0f}G pool, "
          f"sample={smpl}, tmp={tmp//2**20}M, join_cache_level={jcl}, "
          f"{len(files)} tuned queries", flush=True)

    total, errs = 0.0, 0
    for path in files:
        n = int(re.search(r'query(\d+)', path).group(1))
        t0 = time.time()
        with open(path) as fh:
            p = subprocess.run(base, stdin=fh, capture_output=True,
                               text=True, timeout=timeout)
        secs = round(time.time() - t0, 1)
        total += secs
        r = {'query': n, 'tag': tag, 'scale': sf, 'page_kb': page,
             'sample_pages': smpl, 'seconds': secs,
             'buffer_pool_bytes': pool, 'tmp_table_size': tmp}
        if p.returncode:
            e = [l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
            r.update(status='ERROR', detail=(e[0] if e else p.stderr.strip())[:200])
            errs += 1
        else:
            lines = p.stdout.strip().splitlines()
            r['rows'] = max(0, len(lines) - 1)
            r['md5'] = hashlib.md5(p.stdout.encode()).hexdigest()
            r['md5_sorted'] = hashlib.md5(
                ("\n".join(lines[:1] + sorted(lines[1:]))).encode()).hexdigest()
            r['status'] = 'OK'
        json.dump(r, open(f"{rdir}/query{n}.json", 'w'), indent=1)
        print(f"  query{n:<4} {r['status']:<6} {secs:>8.1f}s "
              f"rows={r.get('rows','-')} {r.get('detail','')}", flush=True)

    print(f"=== {tag} TOTAL {total:.1f}s ({total/60:.1f} min), {errs} errors",
          flush=True)
    json.dump({'tag': tag, 'total_seconds': round(total, 1), 'errors': errs,
               'scale': sf, 'page_kb': page, 'sample_pages': smpl,
               'buffer_pool_bytes': pool, 'tmp_table_size': tmp,
               'queries': len(files), 'queryset': 'tuned-tier45'},
              open(f"{rdir}/_summary.json", 'w'), indent=1)


main()
