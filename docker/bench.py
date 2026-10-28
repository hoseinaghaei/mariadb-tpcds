#!/usr/bin/env python3
"""Run selected TPC-DS files in MariaDB and preserve complete result sets.

usage: bench.py <socket> <outdir> <tag> [all|all-tuned|tier45|tuned|smoke]
       bench.py --list <queryset>
       bench.py --check <outdir> <queryset>
       bench.py --compare <reference-outdir> <candidate-outdir>
       bench.py --prepare-output <outdir> <logfile>

all: all 99 adapted originals. all-tuned: the same 99 IDs, using the 40
adopted files and the remaining 59 adapted originals. tuned/tier45 retain
those 40 IDs; smoke uses adapted 3, 12, 18, 76. Missing files fail early.

Every file runs whole in one connection, so session settings and multiple
SELECTs survive. XML answers retain result-set boundaries, duplicate columns,
NULLs and exact numeric text. Hashes use versioned JSON, not legacy TSV.
Row sorting is confined to each result set. Order differences require review:
bag equality alone does not verify ORDER BY or LIMIT semantics.

Execution success is distinct from answer validation. --compare requires the
same declared scale/seed and complete coverage; its baseline still needs an
independent correctness justification. Empty XML result sets omit column
metadata, so their output projection cannot be checked through this client.
"""
import subprocess, sys, os, json, time, hashlib, re, glob, csv, tempfile
from datetime import datetime, timezone
from pathlib import Path
from result_sets import FORMAT, parse_results, fingerprints, compare_results

PROJECT = "/project" if Path("/project/queries").is_dir() else str(Path(__file__).resolve().parent.parent)
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
        raise ValueError("could not read the tier files under queries/tiers/")
    return sorted(ns)


def query_items(which):
    """Resolve an exact workload; missing files must not silently reduce it."""
    if which == 'smoke':
        wanted = SMOKE_QUERIES
    elif which in ('all', 'all-tuned'):
        wanted = range(1, 100)
    elif which in ('tier45', 'tuned'):
        wanted = tier45()
    else:
        raise ValueError(f"query set must be all, all-tuned, tier45, tuned or smoke (got {which})")
    directory = TDIR if which == 'tuned' else QDIR
    adopted = set(tier45()) if which == 'all-tuned' else set()
    items = [(n, f"{TDIR if n in adopted else directory}/query{n}.sql") for n in wanted]
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
    if summary.get('result_format') != FORMAT:
        raise ValueError("legacy/unknown result format: rerun before comparing answers")
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
                or result.get('queryset') != which or result.get('result_format') != FORMAT
                or not all(isinstance(result.get(key), str)
                           and re.fullmatch(r'[0-9a-f]{32}', result[key])
                           for key in ('md5', 'md5_sorted'))):
            raise ValueError(f"query{n} failed or lacks valid result hashes")
        answer = json.loads((directory / 'answers' / f'query{n}.json').read_text())
        if fingerprints(answer) != {k: result[k] for k in ('md5', 'md5_sorted')}:
            raise ValueError(f"query{n} answer does not match its recorded hashes")
        if (result.get('result_set_rows') != [len(s['rows']) for s in answer]
                or result.get('rows') != sum(len(s['rows']) for s in answer)
                or result.get('result_set_columns') != [s['columns'] if s['rows'] else None for s in answer]):
            raise ValueError(f"query{n} result-set row counts do not match its answer")
    return len(wanted)


def compare_runs(expected_dir, actual_dir):
    """Compare complete successful workloads on the same declared dataset.

    A baseline is a reference for regression testing, not proof of TPC-DS
    correctness. Order differences require review; bag equality alone is not
    accepted as proof that ORDER BY/LIMIT semantics were preserved.
    """
    expected_dir, actual_dir = Path(expected_dir), Path(actual_dir)
    expected = json.loads((expected_dir / '_summary.json').read_text())
    actual = json.loads((actual_dir / '_summary.json').read_text())
    for path, summary in [(expected_dir, expected), (actual_dir, actual)]:
        verify_run(path, summary.get('queryset'))
    for key in ('scale', 'rngseed'):
        values = [summary.get(key) for summary in (expected, actual)]
        if (any(not re.fullmatch(r'\d+', str(v)) for v in values)
                or (key == 'scale' and any(int(v) < 1 for v in values))
                or int(values[0]) != int(values[1])):
            raise ValueError(f"cannot compare runs with unknown/different {key}")
    if expected['query_ids'] != actual['query_ids']:
        raise ValueError("cannot compare different query coverage")
    rows = []
    for n in expected['query_ids']:
        a = json.loads((expected_dir / 'answers' / f'query{n}.json').read_text())
        b = json.loads((actual_dir / 'answers' / f'query{n}.json').read_text())
        rows.append({'query': n, 'status': compare_results(a, b),
                     'column_names_available': all(bool(s['rows']) for s in a + b)})
    return {'comparison': 'adopted/reference answers; not official qualification',
            'queries': len(rows), 'all_ordered_results_match': all(r['status'] == 'MATCH' for r in rows),
            'empty_result_note': 'XML omits column metadata for empty result sets; their projection is not verified.',
            'results': rows}


def write_coverage(outdir, items, records):
    with Path(outdir, '_coverage.csv').open('w', newline='', encoding='utf-8') as out:
        writer = csv.DictWriter(out, fieldnames=['query', 'sql_file', 'sql_sha256',
                                                'execution_status', 'rows', 'result_set_rows', 'correctness'])
        writer.writeheader()
        for (n, path), record in zip(items, records):
            writer.writerow({'query': n, 'sql_file': os.path.relpath(path, PROJECT),
                             'sql_sha256': record['sql_sha256'], 'execution_status': record['status'],
                             'rows': record.get('rows'), 'result_set_rows': record.get('result_set_rows'),
                             'correctness': 'NOT_COMPARED'})


def prepare_output(outdir, logfile=None):
    """Keep the usual latest-run path while preserving earlier evidence.

    The entrypoint calls this before tee opens the log. Standalone bench runs
    also archive their output directory, but must not move a currently open
    log. Archives are outside the collector's results/sf*/tuned glob.
    """
    directory = Path(outdir)
    log = Path(logfile) if logfile is not None else None
    comparison = directory.parent / '_answer_comparison.json' if log is not None else None
    if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
        raise ValueError(f"results path must be a directory, not a file or symlink: {directory}")
    for path in (log, comparison):
        if path is not None and (path.is_symlink() or (path.exists() and not path.is_file())):
            raise ValueError(f"result artifact must be a regular file: {path}")
    has_output = directory.exists() and any(directory.iterdir())
    previous_files = [p for p in (log, comparison) if p is not None and p.exists()]
    archived = None
    if has_output or previous_files:
        history = directory.parent / '.history' / directory.name
        history.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ-')
        archived = Path(tempfile.mkdtemp(prefix=stamp, dir=history))
        # mkdtemp defaults to 0700. Docker runs as root, so use the same
        # readable directory permissions as the ordinary result outputs.
        archived.chmod(0o755)
        if has_output:
            directory.rename(archived / 'run')
        for path in previous_files:
            path.rename(archived / path.name)
        print(f"Archived previous {directory.name} artifacts to {archived}", flush=True)
    directory.mkdir(parents=True, exist_ok=True)
    return archived


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--list':
        if len(sys.argv) != 3:
            raise ValueError("usage: bench.py --list <queryset>")
        print(json.dumps([{'query': n, 'sql_file': os.path.relpath(path, PROJECT)}
                          for n, path in query_items(sys.argv[2])], indent=2))
        return 0
    if len(sys.argv) > 1 and sys.argv[1] == '--compare':
        if len(sys.argv) != 4:
            raise ValueError("usage: bench.py --compare <reference-outdir> <candidate-outdir>")
        comparison = compare_runs(sys.argv[2], sys.argv[3])
        print(json.dumps(comparison, indent=2))
        return 0 if comparison['all_ordered_results_match'] else 1
    if len(sys.argv) > 1 and sys.argv[1] == '--check':
        if len(sys.argv) != 4:
            raise ValueError("usage: bench.py --check <outdir> <queryset>")
        count = verify_run(sys.argv[2], sys.argv[3])
        print(f"Validated {count}/{count} successful query artifacts", flush=True)
        return 0
    if len(sys.argv) > 1 and sys.argv[1] == '--prepare-output':
        if len(sys.argv) != 4:
            raise ValueError("usage: bench.py --prepare-output <outdir> <logfile>")
        prepare_output(sys.argv[2], sys.argv[3])
        return 0
    if len(sys.argv) not in (4, 5):
        raise ValueError("usage: bench.py <socket> <outdir> <tag> [all|all-tuned|tier45|tuned|smoke]")
    sock, outdir, tag = sys.argv[1], sys.argv[2], sys.argv[3]
    which = sys.argv[4] if len(sys.argv) > 4 else 'tuned'
    items = query_items(which)
    profile = os.environ.get('PROFILE', 'unspecified')
    timeout_seconds = int(os.environ.get('STATEMENT_TIMEOUT', '3600'))
    if timeout_seconds < 1:
        raise ValueError("STATEMENT_TIMEOUT must be positive")
    pre = PRE + f"SET SESSION max_statement_time={timeout_seconds};"
    prepare_output(outdir)
    Path(outdir, 'answers').mkdir(exist_ok=True)

    base = ['mariadb', '--connect-timeout=5', '--skip-reconnect', '--comments',
            f'--socket={sock}', '-u', 'root',
            '--default-character-set=utf8mb4', 'tpcds']

    def ask(sql):
        p = subprocess.run(base + ['-N', '-B', '-e', sql], capture_output=True, text=True, timeout=30)
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

    total, errors, records = 0.0, 0, []
    for n, path in items:
        sql = Path(path).read_text(encoding='utf-8-sig')
        err, answer, t0 = None, None, time.perf_counter()
        # Every file stays in one connection, including SETs and multiple
        # SELECTs. Never split SQL on semicolons in comments or literals.
        try:
            p = subprocess.run(base + ['--xml'], input=(pre + sql).encode('utf-8'),
                               capture_output=True, timeout=2 * timeout_seconds + 30)
            if p.returncode:
                detail = p.stderr.decode('utf-8', errors='replace')
                e = [line for line in detail.splitlines() if 'ERROR' in line]
                err = (e[0] if e else detail.strip() or f'client exited with code {p.returncode}')[:200]
        except subprocess.TimeoutExpired:
            err = 'client timeout'
        secs = round(time.perf_counter() - t0, 1)
        total += secs

        if err is None:
            try:
                answer = parse_results(p.stdout)
                hashes = fingerprints(answer)
            except ValueError as exc:
                err = str(exc)

        r = {'query': n, 'tag': tag, 'profile': profile, 'queryset': which, 'page_kb': page,
             'sql_sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(),
             'sql_file': os.path.relpath(path, PROJECT), 'result_format': FORMAT,
             'correctness': 'NOT_COMPARED',
             'sample_pages': sample, 'indexes': nidx, 'seconds': secs}
        if err is not None:
            r.update(status='ERROR', detail=err)
            errors += 1
        else:
            r['result_set_rows'] = [len(s['rows']) for s in answer]
            r['rows'] = sum(r['result_set_rows'])
            r['result_set_columns'] = [s['columns'] if s['rows'] else None for s in answer]
            r.update(hashes)
            Path(outdir, 'answers', f'query{n}.json').write_text(
                json.dumps(answer, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
            r['status'] = 'OK'
        records.append(r)
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
               'result_format': FORMAT, 'timing_protocol': 'whole-file-xml-v1',
               'correctness': 'NOT_COMPARED',
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
    write_coverage(outdir, items, records)
    verify_run(outdir, which)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        sys.exit(f"ERROR: {exc}")
