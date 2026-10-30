#!/usr/bin/env python3
"""Export completed run evidence, or build the course PDF and source ZIP.

No Docker or database commands are executed. Existing output paths are refused.
Build dependencies: pandoc, XeLaTeX, gnuplot and DejaVu fonts. Evidence export
uses only Python's standard library and the repository's answer validator.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'docker'))
from bench import query_items, verify_run
from result_sets import FORMAT


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args, root=REPO):
    return subprocess.run(['git', *args], cwd=root, check=True, capture_output=True).stdout


def execution_sql(path, expected_hash, root=REPO):
    """Find the recorded SQL by hash, without changing the current checkout.

    A matching historical blob identifies its contents, not the execution commit.
    """
    relative = Path(path)
    if relative.is_absolute() or '..' in relative.parts or relative.suffix != '.sql':
        raise ValueError(f'unsafe recorded SQL path: {path}')
    current = root / relative
    if current.is_file() and digest(current.read_bytes()) == expected_hash:
        return current.read_bytes(), 'working-tree content matches recorded hash'
    try:
        commits = git('log', '--all', '--format=%H', '--', path, root=root).decode().splitlines()
        for commit in commits:
            try:
                data = git('show', f'{commit}:{path}', root=root)
            except subprocess.CalledProcessError:
                continue  # A deletion commit need not contain this path.
            if digest(data) == expected_hash:
                return data, f'matching historical blob at {commit}; not an execution-commit claim'
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return None, 'recorded SQL contents unavailable; current file does not match'


def run_payload(directory, root=REPO):
    """Collect a completed run. Legacy hashes are preserved, never requalified."""
    directory = Path(directory)
    summary_path = directory / '_summary.json'
    if not summary_path.is_file():
        raise ValueError('run has no summary; it may still be running or have failed')
    summary_bytes = summary_path.read_bytes()
    summary = json.loads(summary_bytes)
    which = summary.get('queryset')
    which = 'tuned' if which == 'tuned-tier45' else which
    wanted = {n for n, _ in query_items(which)}
    actual = {p.name for p in directory.glob('query*.json')}
    if (summary.get('errors') != 0 or summary.get('queries') != len(wanted)
            or actual != {f'query{n}.json' for n in wanted}
            or ('query_ids' in summary and set(summary['query_ids']) != wanted)):
        raise ValueError('run has errors, missing artifacts or inconsistent workload coverage')
    structured = summary.get('result_format') == FORMAT
    if structured:
        verify_run(directory, which)
    elif summary.get('result_format') is not None:
        raise ValueError('unknown result format; do not silently treat it as legacy')
    payload = {'run/_summary.json': summary_bytes}
    snapshots, unavailable = [], []
    for n in sorted(wanted):
        name = f'query{n}.json'
        record_bytes = (directory / name).read_bytes()
        record = json.loads(record_bytes)
        if record.get('query') != n or record.get('status') != 'OK':
            raise ValueError(f'{name} is not a successful record for its query ID')
        payload[f'run/{name}'] = record_bytes
        if structured:
            payload[f'run/answers/{name}'] = (directory / 'answers' / name).read_bytes()
        if record.get('sql_file') and record.get('sql_sha256'):
            sql, origin = execution_sql(record['sql_file'], record['sql_sha256'], root)
            snapshots.append({'query': n, 'source': record['sql_file'],
                              'sql_sha256': record['sql_sha256'], 'recovery': origin})
            if sql is not None:
                payload[f'sql/query{n}.sql'] = sql
            else:
                unavailable.append(n)
        else:
            unavailable.append(n)
    coverage = directory / '_coverage.csv'
    if coverage.is_file():
        payload['run/_coverage.csv'] = coverage.read_bytes()
    log = directory.parent / f'{summary.get("tag", directory.name)}.log'
    if log.is_file():
        payload['run.log'] = log.read_bytes()
    # The parent owns this per-scale usage file; preserve it without treating
    # read counters as proof that an index is safe to remove.
    usage = directory.parent / f'index-usage-sf{summary.get("scale")}.tsv'
    if usage.is_file():
        payload[usage.name] = usage.read_bytes()
    try:
        head = git('rev-parse', 'HEAD', root=root).decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        head = None
    # Check for a writer replacing the summary during the export.
    if summary_path.read_bytes() != summary_bytes:
        raise ValueError('run summary changed during export; retry after the run finishes')
    manifest = {
        'schema': 'tpcds-run-evidence-v1',
        'exported_at_utc': datetime.now(timezone.utc).isoformat(),
        'repository_head_at_export': head,
        'execution_commit': None,
        'execution_commit_note': 'Export HEAD is not the commit that executed this run.',
        'summary': summary,
        'artifact_integrity': 'VERIFIED' if structured else 'LEGACY_RECORDS_ONLY',
        'reference_answer_correctness': 'NOT_ESTABLISHED_BY_EXPORT',
        'empty_projection_note': 'XML does not preserve column metadata for empty result sets.',
        'missing_sql_snapshots': unavailable,
        'sql_snapshots': snapshots,
        'missing_run_metadata': ['full hardware description', 'image digest',
                                 'complete index definitions and IGNORED flags',
                                 'cache/warm-up protocol and repetition IDs'],
        'files': {name: {'bytes': len(data), 'sha256': digest(data)}
                  for name, data in sorted(payload.items())},
    }
    payload['manifest.json'] = (json.dumps(manifest, indent=2, ensure_ascii=False) + '\n').encode()
    return payload, manifest


def write_zip(path, payload):
    path = Path(path)
    for name in payload:
        if Path(name).is_absolute() or '..' in Path(name).parts:
            raise ValueError(f'unsafe archive member: {name}')
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation prevents accidental replacement of evidence or releases.
    with path.open('xb') as output:
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(payload.items()):
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.external_attr = (0o100755 if name.endswith('.sh') or data.startswith(b'#!') else 0o100644) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data)


def source_payload(root=REPO):
    """Package tracked contents plus this task's new submission sources.

    Unknown untracked files are excluded. Ignored datasets/results and .git
    are never discovered by this source-selection rule.
    """
    try:
        tracked = git('ls-files', '-z', root=root).decode().split('\0')
        extra = git('ls-files', '--others', '--exclude-standard', '-z', root=root).decode().split('\0')
    except (subprocess.CalledProcessError, FileNotFoundError):
        # A lecturer receives a ZIP, not a Git checkout. Rebuild from the
        # explicit packaged inventory rather than walking arbitrary files.
        manifest = root / 'SUBMISSION-MANIFEST.json'
        if not manifest.is_file():
            raise ValueError('source packaging needs a Git checkout or a packaged SUBMISSION-MANIFEST.json')
        packaged = json.loads(manifest.read_text())
        if packaged.get('schema') != 'tpcds-course-submission-v1':
            raise ValueError('unknown packaged source inventory')
        tracked = list(packaged['files'])
        extra = []
    allowed_extra = {'scripts/submission.py', 'scripts/test_submission.py',
                     'scripts/build_latex_report.py', 'scripts/test_latex_report.py',
                     'report/latex/main.tex', 'report/latex/metadata.tex',
                     'report/latex/references.bib', 'report/latex/README.txt',
                     'experiments/evidence/docker_sf1_99/run.zip',
                     'experiments/evidence/docker_sf1_99/original-run.zip',
                     'experiments/evidence/docker_sf2_99/run.zip',
                     'experiments/evidence/docker_sf2_99/original-run.zip',
                     'experiments/evidence/docker_sf3_99/run.zip',
                     'experiments/evidence/docker_sf3_99/original-run.zip',
                     'report/submission_evidence.json',
                     'experiments/evidence/docker_sf4_99/run.zip',
                     'experiments/evidence/docker_sf4_99/original-run.zip',
                     'experiments/evidence/docker_sf4_99/comparison.json',
                     'experiments/evidence/docker_sf4_99/comparison.csv'}
    names = set(filter(None, tracked)) | (set(extra) & allowed_extra)
    payload = {}
    for name in sorted(names):
        path = root / name
        if (Path(name).is_absolute() or '..' in Path(name).parts
                or name.startswith(('results/', '.git/', 'submission/')) or path.is_symlink()):
            raise ValueError(f'unsafe source member: {name}')
        if path.is_file():
            payload[name] = path.read_bytes()
    return payload


def render_figures(evidence, output, environment):
    campaign = evidence['reported_scaling_campaign']
    if campaign.get('use_in_submission_results') is False:
        return
    rows = campaign['measurements']
    points = '\n'.join(f"{r['scale']} {r['seconds']} {rows[0]['seconds'] * r['scale'] / rows[0]['scale']}"
                       for r in rows) + '\ne\n'
    common = """set xlabel 'Generator scale factor (nominal)'
set ylabel 'Selected 40-query runtime (seconds)'
set xtics (1,2,4,8)
set xrange [0.5:8.5]
set yrange [0:*]
set grid ytics
set key top left
set title 'Reported single-run scaling; raw campaign files pending'
"""
    for terminal, name in [('pdfcairo enhanced font "DejaVu Sans,10" size 6.8in,3.5in', 'scaling.pdf'),
                           ('svg enhanced font "DejaVu Sans,12" size 900,460', 'scaling.svg')]:
        destination = json.dumps((output / name).as_posix())
        script = (f"set terminal {terminal}\nset output {destination}\n" + common
                  + "plot '-' using 1:2 with linespoints lw 2 pt 7 lc rgb '#1f5a85' title 'Reported runtime', "
                    "'-' using 1:3 with lines dt 2 lc rgb '#666666' title 'Linear reference from SF1'\n"
                  + points + points)
        subprocess.run(['gnuplot'], input=script, text=True, env=environment,
                       check=True, capture_output=True)


def build(output):
    for command in ('pandoc', 'xelatex', 'gnuplot'):
        if not shutil.which(command):
            raise ValueError(f'{command} is required to build the PDF; no packages were installed')
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    assets = output / 'assets'
    assets.mkdir()
    evidence_path = REPO / 'report/submission_evidence.json'
    evidence = json.loads(evidence_path.read_text())
    with tempfile.TemporaryDirectory(prefix='tpcds-report-') as temporary:
        scratch = Path(temporary)
        environment = {**os.environ, 'TEXMFVAR': str(scratch / 'tex-var'),
                       'TEXMFCONFIG': str(scratch / 'tex-config'),
                       'TEXMFOUTPUT': str(scratch), 'XDG_CACHE_HOME': str(scratch / 'cache')}
        render_figures(evidence, assets, environment)
        markdown = (REPO / 'submission_report.md').read_text()
        markdown = markdown.replace('report/assets/scaling.svg', str(assets / 'scaling.pdf'))
        parsed = subprocess.run(['pandoc', '--from=gfm', '--to=json'], input=markdown,
                                text=True, check=True, capture_output=True)
        document = json.loads(parsed.stdout)
        # GFM's automatic table widths become unwrapped LaTeX l/r columns.
        # Explicit widths make prose wrap inside the printable page.
        for block in document['blocks']:
            if block['t'] == 'Table':
                columns = block['c'][2]
                for column in columns:
                    column[1] = {'t': 'ColWidth', 'c': 1 / len(columns)}
        source = scratch / 'report.json'
        source.write_text(json.dumps(document))
        pdf = output / 'TPCDS-Part-I-report.pdf'
        command = ['pandoc', str(source), '--from=json', '--standalone', '--pdf-engine=xelatex',
                   '--resource-path', str(REPO), '-V', 'geometry:margin=20mm', '-V', 'papersize=a4', '-V', 'fontsize=10pt',
                   '-V', 'mainfont=DejaVu Serif', '-V', 'sansfont=DejaVu Sans',
                   '-V', 'monofont=DejaVu Sans Mono', '-V', 'colorlinks=true', '-o', str(pdf)]
        result = subprocess.run(command, cwd=scratch, env=environment, capture_output=True, text=True)
        (output / 'render.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise ValueError(f'PDF rendering failed; inspect {output / "render.log"}')
        subprocess.run(['pandoc', str(REPO / 'submission_report.md'), '--from=gfm', '--standalone',
                        '--metadata', 'title=TPC-DS on MariaDB — Part I',
                        '-o', str(output / 'report.html')], check=True, capture_output=True)
    # A source SVG makes the Markdown readable on GitHub. The PDF build uses
    # the vector PDF counterpart, so no browser/image converter is required.
    source_figure = REPO / 'report/assets/scaling.svg'
    source_figure.parent.mkdir(parents=True, exist_ok=True)
    if (assets / 'scaling.svg').exists():
        if not source_figure.exists() or source_figure.read_bytes() != (assets / 'scaling.svg').read_bytes():
            source_figure.write_bytes((assets / 'scaling.svg').read_bytes())
    payload = source_payload()
    if (assets / 'scaling.pdf').exists():
        payload['report/assets/scaling.pdf'] = (assets / 'scaling.pdf').read_bytes()
        payload['report/assets/scaling.svg'] = (assets / 'scaling.svg').read_bytes()
    payload['TPCDS-Part-I-report.pdf'] = pdf.read_bytes()
    # HTML must resolve its image offline, alongside the PDF and source ZIP.
    html = (output / 'report.html').read_text().replace('report/assets/scaling.svg', 'assets/scaling.svg')
    (output / 'report.html').write_text(html)
    try:
        head = git('rev-parse', 'HEAD').decode().strip()
        changes = git('status', '--porcelain').decode().splitlines()
    except (subprocess.CalledProcessError, FileNotFoundError):
        head = None
        changes = ['Source ZIP build: no Git metadata; files selected from packaged inventory.']
    release = {
        'schema': 'tpcds-course-submission-v1',
        'built_at_utc': datetime.now(timezone.utc).isoformat(),
        'repository_head_at_build': head,
        'working_tree_changes_at_build': changes,
        'readiness': 'REVIEW_DRAFT',
        'blocking_items': evidence['open_items'],
        'files': {name: {'bytes': len(data), 'sha256': digest(data)}
                  for name, data in sorted(payload.items())},
    }
    payload['SUBMISSION-MANIFEST.json'] = (json.dumps(release, indent=2) + '\n').encode()
    payload = {'mariadb-tpcds/' + name: data for name, data in payload.items()}
    archive = output / 'TPCDS-Part-I-code.zip'
    write_zip(archive, payload)
    (output / 'SUBMISSION-MANIFEST.json').write_text(json.dumps(release, indent=2) + '\n')
    checksums = '\n'.join(f'{digest(p.read_bytes())}  {p.name}' for p in (pdf, archive)) + '\n'
    (output / 'SHA256SUMS').write_text(checksums)
    print(f'Built review PDF and source ZIP in {output}')
    print('Open items:', '; '.join(evidence['open_items']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    export = commands.add_parser('export-run', help='export one completed run; never executes SQL')
    export.add_argument('--run', type=Path, required=True)
    export.add_argument('--out', type=Path, required=True)
    package = commands.add_parser('build', help='build a review PDF, HTML and source ZIP')
    package.add_argument('--out', type=Path, required=True, help='new output directory')
    args = parser.parse_args()
    if args.command == 'export-run':
        payload, manifest = run_payload(args.run)
        write_zip(args.out, payload)
        print(f'Exported {manifest["summary"]["queries"]} queries: {manifest["artifact_integrity"]}')
        if manifest['missing_sql_snapshots']:
            print('SQL snapshots unavailable for:', manifest['missing_sql_snapshots'])
    else:
        build(args.out)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        sys.exit(f'ERROR: {exc}')
