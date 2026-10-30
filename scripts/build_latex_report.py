#!/usr/bin/env python3
"""Build the LaTeX report from checked evidence; never runs Docker or SQL.

Run from any directory: python3 -B scripts/build_latex_report.py --out NEW_DIR
Complete SF1--3 runs are discovered using the group's existing folder names.
Preserved evidence bundles also support builds without live result directories.
"""
import argparse
import csv
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'docker'))
from result_sets import FORMAT, compare_results, fingerprints


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def tex(value):
    replacements = {'\\': r'\textbackslash{}', '&': r'\&', '%': r'\%',
                    '$': r'\$', '#': r'\#', '_': r'\_', '{': r'\{',
                    '}': r'\}', '~': r'\textasciitilde{}', '^': r'\textasciicircum{}'}
    return ''.join(replacements.get(c, c) for c in str(value))


def number(value, places=1):
    return f'{value:,.{places}f}'.replace(',', r'\,')


def read_run(path):
    """Verify complete 99-query records and answers, including archived runs."""
    path = Path(path)
    archive = zipfile.ZipFile(path) if path.is_file() else None
    try:
        if archive:
            if archive.testzip() is not None:
                raise ValueError(f'corrupt evidence archive: {path}')
            manifest = json.loads(archive.read('manifest.json'))
            for name, item in manifest['files'].items():
                raw = archive.read(name)
                if sha(raw) != item['sha256'] or len(raw) != item['bytes']:
                    raise ValueError(f'evidence manifest mismatch: {path}: {name}')
            read = lambda name: archive.read('run/' + name)
        else:
            read = lambda name: (path / name).read_bytes()
        summary_raw = read('_summary.json')
        summary = json.loads(summary_raw)
        if (summary.get('queries') != 99 or summary.get('errors') != 0
                or summary.get('query_ids') != list(range(1, 100))
                or summary.get('result_format') != FORMAT
                or summary.get('queryset') not in ('all', 'all-tuned')):
            raise ValueError(f'not a complete successful structured 99-query run: {path}')
        records, answers = {}, {}
        for n in range(1, 100):
            r = json.loads(read(f'query{n}.json'))
            a = json.loads(read(f'answers/query{n}.json'))
            if (r.get('query') != n or r.get('status') != 'OK'
                    or r.get('queryset') != summary['queryset']
                    or r.get('result_format') != FORMAT
                    or not re.fullmatch(r'[0-9a-f]{64}', r.get('sql_sha256', ''))
                    or not isinstance(r.get('seconds'), (float, int))
                    or not math.isfinite(r['seconds']) or r['seconds'] < 0
                    or fingerprints(a) != {k: r.get(k) for k in ('md5', 'md5_sorted')}
                    or r.get('result_set_rows') != [len(s['rows']) for s in a]
                    or r.get('rows') != sum(len(s['rows']) for s in a)
                    or r.get('result_set_columns') != [s['columns'] if s['rows'] else None for s in a]):
                raise ValueError(f'invalid query{n} evidence in {path}')
            if archive:
                if sha(archive.read(f'sql/query{n}.sql')) != r['sql_sha256']:
                    raise ValueError(f'wrong executed SQL snapshot for query{n} in {path}')
            records[n], answers[n] = r, a
        if abs(sum(r['seconds'] for r in records.values()) - summary['total_seconds']) > 0.11:
            raise ValueError(f'per-query timings do not sum to workload total: {path}')
        return dict(path=path, summary=summary, records=records, answers=answers,
                    summary_sha256=sha(summary_raw))
    finally:
        if archive:
            archive.close()


def compare_pair(original, adopted):
    a, b = original['summary'], adopted['summary']
    for key in ('scale', 'rngseed'):
        if not all(re.fullmatch(r'\d+', str(s.get(key))) for s in (a, b)) or int(a[key]) != int(b[key]):
            raise ValueError(f'cannot compare runs with missing/different {key}')
    if a['queryset'] != 'all' or b['queryset'] != 'all-tuned':
        raise ValueError('original/adopted workloads were interchanged')
    results = {n: compare_results(original['answers'][n], adopted['answers'][n])
               for n in range(1, 100)}
    keys = ('indexes', 'page_kb', 'buffer_pool_bytes', 'sample_pages',
            'server_settings_bytes', 'timing_protocol')
    differences = {key: [a.get(key), b.get(key)] for key in keys if a.get(key) != b.get(key)}
    reviewed = {}
    for n, status in results.items():
        if n == 71 and status == 'ORDER_DIFFERENCE_REQUIRES_REVIEW':
            review = review_q71_ties(original['answers'][n], adopted['answers'][n],
                                     executed_sql(original, n), executed_sql(adopted, n))
            if review:
                reviewed[n] = review
    return dict(results=results, ordered_matches=sum(v == 'MATCH' for v in results.values()),
                reviewed_tie_matches=reviewed,
                accepted_matches=sum(v == 'MATCH' for v in results.values()) + len(reviewed),
                declared_configuration_differences=differences)


def executed_sql(run, n):
    """Read a recorded SQL snapshot without inferring an execution version."""
    path = run['path']
    if path.is_file():
        with zipfile.ZipFile(path) as archive:
            raw = archive.read(f'sql/query{n}.sql')
    else:
        # The working query may evolve after a completed run. Prefer its
        # preserved, hash-matched snapshot when available.
        sf = run['summary'].get('scale')
        name = 'original-run.zip' if run['summary'].get('queryset') == 'all' else 'run.zip'
        preserved = REPO / f'experiments/evidence/docker_sf{sf}_99' / name
        if preserved.is_file():
            with zipfile.ZipFile(preserved) as archive:
                snapshot = archive.read(f'sql/query{n}.sql')
            if sha(snapshot) == run['records'][n]['sql_sha256']:
                return snapshot.decode()
        relative = Path(run['records'][n].get('sql_file', ''))
        if relative.is_absolute() or '..' in relative.parts or relative.suffix != '.sql':
            return None
        source = REPO / relative
        if not source.is_file():
            return None
        raw = source.read_bytes()
    return raw.decode() if sha(raw) == run['records'][n]['sql_sha256'] else None


def review_q71_ties(original, adopted, original_sql, adopted_sql):
    """Review only Q71's exact known ordering, retaining the raw comparator status.

    Require identical executed SELECTs, full duplicate-preserving row equality,
    no LIMIT, correctly sorted keys and permutations exclusively within ties.
    """
    if (not original_sql or not adopted_sql or len(original) != 1 or len(adopted) != 1
            or compare_results(original, adopted) != 'ORDER_DIFFERENCE_REQUIRES_REVIEW'):
        return None
    bodies = []
    for sql in (original_sql, adopted_sql):
        match = re.search(r'(?is)\bselect\s+i_brand_id\s+brand_id\b.*', sql)
        if not match:
            return None
        body = match.group().strip()
        if (re.search(r'\blimit\b', body, re.I)
                or not re.search(r'(?is)order\s+by\s+ext_price\s+desc\s*,\s*i_brand_id\s*;?\s*$', body)):
            return None
        bodies.append(body)
    if bodies[0] != bodies[1]:
        return None
    sequences = []
    for answer in (original[0], adopted[0]):
        if answer['columns'] != ['brand_id', 'brand', 't_hour', 't_minute', 'ext_price']:
            return None
        try:
            # MariaDB orders NULL below non-NULL values: DESC places it last.
            keys = [(row[4] is None, -Decimal(row[4]) if row[4] is not None else Decimal(0),
                     row[0] is not None, int(row[0]) if row[0] is not None else 0)
                    for row in answer['rows']]
            if keys != sorted(keys):
                return None
        except (ValueError, InvalidOperation):
            return None
        sequences.append(keys)
    if sequences[0] != sequences[1]:
        return None
    return {'status': 'EQUAL_VALUES_AND_VALID_ORDER_BY_TIES',
            'rows': len(original[0]['rows']),
            'changed_row_positions': sum(a != b for a, b in zip(original[0]['rows'], adopted[0]['rows'])),
            'order_by': 'ext_price DESC, i_brand_id ASC',
            'identical_executed_select': True, 'limit_absent': True,
            'duplicate_preserving_values_equal': True, 'both_sequences_sorted': True,
            'identical_order_key_sequences': True}


def campaign_statistics(runs, comparisons):
    """Descriptive metrics of measured passes; never average per-query ratios."""
    rows = []
    for sf in sorted(comparisons):
        a, b = runs[sf, 'original'], runs[sf, 'adopted']
        original, adopted = a['summary']['total_seconds'], b['summary']['total_seconds']
        changes = {n: a['records'][n]['seconds'] - b['records'][n]['seconds'] for n in range(1, 100)}
        core_original = sum(a['records'][n]['seconds'] for n in (14, 23, 59))
        core_adopted = sum(b['records'][n]['seconds'] for n in (14, 23, 59))
        rows.append({'scale': sf, 'original_seconds': original, 'adopted_seconds': adopted,
                     'ratio': original / adopted if adopted else None,
                     'seconds_saved': original - adopted,
                     'reduction_percent': 100 * (original - adopted) / original if original else 0,
                     'faster': sum(v > 0 for v in changes.values()),
                     'slower': sum(v < 0 for v in changes.values()),
                     'same_rounded_time': sum(v == 0 for v in changes.values()),
                     'top_savings_queries': sorted(changes, key=lambda n: (-changes[n], n))[:5],
                     'core_original_seconds': core_original, 'core_adopted_seconds': core_adopted,
                     'core_seconds_saved': core_original - core_adopted,
                     'core_original_share_percent': 100 * core_original / original if original else 0,
                     'core_adopted_share_percent': 100 * core_adopted / adopted if adopted else 0,
                     'ordered_matches': comparisons[sf]['ordered_matches'],
                     'reviewed_tie_matches': len(comparisons[sf].get('reviewed_tie_matches', {})),
                     'accepted_matches': comparisons[sf].get('accepted_matches', comparisons[sf]['ordered_matches'])})
    return rows


def adopted_sources(root=REPO):
    sources = {}
    for path in (root / 'queries/tuned').glob('query*.sql'):
        match = re.search(r'^-- source:\s*(.*)$', path.read_text(), re.M)
        if not match:
            raise ValueError(f'query has no source attribution: {path}')
        n = int(re.search(r'\d+', path.stem)[0])
        sources[n] = match[1]
    if len(sources) != 40:
        raise ValueError('expected the 40 selected adopted workload files')
    return sources


def collect(root=REPO):
    runs, comparisons = {}, {}
    for sf in range(1, 5):
        for mode in ('original', 'adopted'):
            name = f'check-original-sf{sf}' if mode == 'original' else f'sf{sf}-all-tuned-v1'
            path = root / 'results' / name / 'tuned'
            legacy = root / 'results/check-original/tuned'
            if sf == 4 and mode == 'original' and not (path / '_summary.json').is_file() and (legacy / '_summary.json').is_file():
                path = legacy
            if not (path / '_summary.json').is_file():
                archive_name = 'original-run.zip' if mode == 'original' else 'run.zip'
                archived = root / f'experiments/evidence/docker_sf{sf}_99' / archive_name
                if archived.is_file():
                    path = archived
            if path.is_file() or (path / '_summary.json').is_file():
                run = read_run(path)
                expected = 'all' if mode == 'original' else 'all-tuned'
                if int(run['summary']['scale']) != sf or run['summary']['queryset'] != expected:
                    raise ValueError(f'wrong scale or workload in {path}')
                runs[sf, mode] = run
        if (sf, 'original') in runs and (sf, 'adopted') in runs:
            comparisons[sf] = compare_pair(runs[sf, 'original'], runs[sf, 'adopted'])
    if 4 not in comparisons:
        raise ValueError('the preserved complete SF4 evidence bundles are required')
    return runs, comparisons


def table(path, columns, rows, header):
    path.write_text('\\begin{tabular}{' + columns + '}\n\\toprule\n' + header
                    + r' \\ \midrule' + '\n' + '\n'.join(' & '.join(row) + r' \\' for row in rows)
                    + '\n\\bottomrule\n\\end{tabular}\n')


def plot(data, destination, title, ylabel, environment):
    quote = lambda path: json.dumps(str(path))
    script = f'''set terminal pdfcairo enhanced font "Latin Modern Roman,11" size 6.5in,3.1in
set output {quote(destination)}
set title {json.dumps(title)}
set ylabel {json.dumps(ylabel)}
set style data histograms
set style histogram clustered gap 1
set style fill solid 0.85 border -1
set boxwidth 0.85
set grid ytics
set yrange [0:*]
set key top right
plot {quote(data)} using 2:xtic(1) title 'Original' lc rgb '#354c63', '' using 3 title 'Adopted' lc rgb '#339388'
'''
    subprocess.run(['gnuplot'], input=script, text=True, env=environment,
                   check=True, capture_output=True)


def render_trends(assets, runs, statistics, environment):
    if len(statistics) < 2:
        return
    first = statistics[0]
    normalized = assets / 'normalized-growth.dat'
    normalized.write_text('\n'.join(
        f"{r['scale']} {r['original_seconds']/first['original_seconds']:.10g} "
        f"{r['adopted_seconds']/first['adopted_seconds']:.10g} {r['scale']/first['scale']:.10g}"
        for r in statistics) + '\n')
    ratios = assets / 'runtime-ratios.dat'
    ratios.write_text('\n'.join(f"SF{r['scale']} {r['ratio']:.10g}" for r in statistics) + '\n')
    selected = (4, 39, 59, 27)
    cases = assets / 'query-scaling.dat'
    cases.write_text('\n'.join(' '.join([str(r['scale'])] + [
        str(runs[r['scale'], mode]['records'][n]['seconds'])
        for n in selected for mode in ('original', 'adopted')]) for r in statistics) + '\n')
    common = '''set grid ytics
set yrange [0:*]
set xtics (1,2,3,4)
set xrange [0.85:4.15]
set xlabel 'Nominal generator scale factor'
set key top left
'''
    scripts = [
        ('normalized-growth.pdf', 3.1, common + f'''
set ylabel 'Runtime relative to each workload at SF{first['scale']}'
plot {json.dumps(str(normalized))} using 1:2 with linespoints lw 2 pt 5 lc rgb '#354c63' title 'Original', '' using 1:3 with linespoints lw 2 pt 7 lc rgb '#339388' title 'Adopted', '' using 1:4 with lines dt 2 lc rgb '#999999' title 'Proportional to nominal scale'
'''),
        ('runtime-ratios.pdf', 3.1, f'''
set style fill solid 0.85 border -1
set boxwidth 0.6
set grid ytics
set yrange [0:*]
set ylabel 'Original / adopted total runtime'
set xlabel 'Nominal generator scale factor'
set key off
plot {json.dumps(str(ratios))} using 0:2:xtic(1) with boxes lc rgb '#339388', 1 with lines dt 2 lc rgb '#777777'
'''),
    ]
    cases_script = 'set multiplot layout 2,2 margins 0.08,0.98,0.09,0.95 spacing 0.10,0.17\n' + common
    for i, (n, title) in enumerate(zip(selected, ['Q4: customer/year aggregation', 'Q39: inventory aggregation',
                                                'Q59: store-sales comparison', 'Q27: demographic rollup'])):
        cases_script += (f"set title '{title}'\nset ylabel 'Elapsed seconds'\n"
                         f"plot {json.dumps(str(cases))} using 1:{2+2*i} with linespoints lw 2 pt 5 lc rgb '#354c63' title 'Original', '' using 1:{3+2*i} with linespoints lw 2 pt 7 lc rgb '#339388' title 'Adopted'\n")
    cases_script += 'unset multiplot\n'
    scripts.append(('query-scaling.pdf', 5.3, cases_script))
    for filename, height, body in scripts:
        script = (f'set terminal pdfcairo enhanced font "Latin Modern Roman,11" size 6.5in,{height}in\n'
                  f'set output {json.dumps(str(assets / filename))}\n' + body)
        subprocess.run(['gnuplot'], input=script, text=True, env=environment,
                       check=True, capture_output=True)


def generate(latex, runs, comparisons, sources, environment):
    generated, assets = latex / 'generated', latex / 'assets'
    generated.mkdir(); assets.mkdir()
    originals = runs[4, 'original']['records']; adopted = runs[4, 'adopted']['records']
    optimized = sorted(n for n, p in sources.items() if '/optimized/' in p)
    statistics = campaign_statistics(runs, comparisons)
    by_scale = {r['scale']: r for r in statistics}
    macros = {'AdoptedCount': str(len(optimized)), 'SelectedCount': str(len(sources)),
              'SFfourOriginalSeconds': number(runs[4, 'original']['summary']['total_seconds']),
              'SFfourAdoptedSeconds': number(runs[4, 'adopted']['summary']['total_seconds']),
              'SFfourMatches': str(comparisons[4]['ordered_matches']),
              'CompletedPairs': str(len(comparisons)),
              'TotalQueryExecutions': str(99 * len(runs)),
              'TotalAnswerComparisons': str(99 * len(comparisons)),
              'TotalMatchedAnswers': str(sum(r['accepted_matches'] for r in statistics)),
              'TotalOrderedMatches': str(sum(r['ordered_matches'] for r in statistics)),
              'ReviewedTieMatches': str(sum(r['reviewed_tie_matches'] for r in statistics)),
              'MinRuntimeReduction': number(min(r['reduction_percent'] for r in statistics)),
              'MaxRuntimeReduction': number(max(r['reduction_percent'] for r in statistics)),
              'MinRuntimeRatio': number(min(r['ratio'] for r in statistics if r['ratio'] is not None), 2),
              'MaxRuntimeRatio': number(max(r['ratio'] for r in statistics if r['ratio'] is not None), 2),
              'MeasuredScales': ', '.join(str(sf) for sf in sorted(comparisons)),
              'ReportSnapshotDate': datetime.now(timezone.utc).strftime('%d %B %Y'),
              'OptimizedQueryIDs': ', '.join(f'Q{n}' for n in optimized)}
    (generated / 'metrics.tex').write_text('\n'.join('\\newcommand{\\' + key + '}{' + value + '}'
                                                    for key, value in macros.items()) + '\n')
    rows = []
    for sf in sorted(comparisons):
        cells = [str(sf)]
        for mode in ('original', 'adopted'):
            r = runs[sf, mode]
            cells.append(number(r['summary']['total_seconds']))
        c = comparisons[sf]
        stat = by_scale[sf]
        cells.extend([f"{stat['ratio']:.2f}" if stat['ratio'] is not None else '--',
                      f"{stat['reduction_percent']:.1f}"])
        marker = r'$^{*}$' if stat['reviewed_tie_matches'] else ''
        cells.append(f"{stat['accepted_matches']}/99" + marker)
        cells.append(f"{runs[sf, 'original']['summary'].get('indexes')}/{runs[sf, 'adopted']['summary'].get('indexes')}")
        rows.append(cells)
    table(generated / 'scales.tex', 'lrrrrrr', rows,
          r'Scale & Original (s) & Adopted (s) & Ratio & Saved (\%) & Answers & Indexes (O/A)')
    scaling_figure = generated / 'scaling-figure.tex'
    if len(comparisons) < 2:
        scaling_figure.write_text('% No scaling curve is drawn from one completed scale pair.\n')
    else:
        data = assets / 'scaling.dat'
        data.write_text('\n'.join(f'{sf} {runs[sf, "original"]["summary"]["total_seconds"]} '
                                  f'{runs[sf, "adopted"]["summary"]["total_seconds"]}'
                                  for sf in sorted(comparisons)) + '\n')
        script = f'''set terminal pdfcairo enhanced font "Latin Modern Roman,11" size 6.5in,3.1in
set output {json.dumps(str(assets / 'scaling.pdf'))}
set xlabel 'Nominal generator scale factor'
set ylabel 'Complete 99-query runtime (seconds)'
set xtics (1,2,3,4)
set grid ytics
set key top left
set yrange [0:*]
plot {json.dumps(str(data))} using 1:2 with linespoints lw 2 pt 5 lc rgb '#354c63' title 'Original', '' using 1:3 with linespoints lw 2 pt 7 lc rgb '#339388' title 'Adopted'
'''
        subprocess.run(['gnuplot'], input=script, text=True, env=environment,
                       check=True, capture_output=True)
        scaling_figure.write_text(r'''\begin{figure}[htbp]\centering
\includegraphics[width=\linewidth]{assets/scaling.pdf}
\caption{Total execution time of all 99 query files for the original and adopted
workloads. Markers identify the measured scale factors.}
\end{figure}
''')
    additional = []
    for sf in sorted(comparisons):
        if sf == 4:
            continue
        a, b = runs[sf, 'original']['summary'], runs[sf, 'adopted']['summary']
        c = comparisons[sf]
        additional.append(f"At SF{sf}, the original workload takes {number(a['total_seconds'])} seconds "
                          f"and the adopted workload {number(b['total_seconds'])} seconds. "
                          f"Their observed total-time ratio is {a['total_seconds']/b['total_seconds']:.2f}. "
                          f"{c.get('accepted_matches', c['ordered_matches'])} of 99 saved answers match. "
                          f"The recorded index counts are {a.get('indexes')} and {b.get('indexes')}. ")
        if c['declared_configuration_differences']:
            additional.append('The summaries differ in ' + tex(', '.join(c['declared_configuration_differences']))
                              + '. Per-run settings are retained with the execution records. ')
        else:
            additional.append('Both runs use the same recorded standing server settings. ')
        additional.append('\n\n')
    (generated / 'additional-workloads.tex').write_text(''.join(additional) or
                                                      '')
    discussion = []
    if 1 in comparisons:
        for mode, label in [('original', 'original'), ('adopted', 'adopted')]:
            a, b = runs[1, mode], runs[4, mode]
            ratio = b['summary']['total_seconds'] / a['summary']['total_seconds']
            changed = [n for n in range(1, 100)
                       if a['records'][n]['sql_sha256'] != b['records'][n]['sql_sha256']]
            discussion.append(f'From SF1 to SF4 the observed {label} total grows by '
                              f'{ratio:.2f} times for a fourfold increase in nominal generator scale. ')
            if changed:
                discussion.append('Executed SQL hashes differ for ' + ', '.join(f'Q{n}' for n in changed)
                                  + '; the corresponding executed versions are preserved in the evidence bundles. ')
            else:
                discussion.append('The executed query-file hashes agree across these two scales. ')
            discussion.append('\n\n')
    (generated / 'scaling-discussion.tex').write_text(''.join(discussion))
    # Data-driven descriptions and tables are regenerated with every campaign.
    table(generated / 'runtime-distribution.tex', 'lrrrr',
          [[str(r['scale']), str(r['faster']), str(r['slower']), str(r['same_rounded_time']),
            number(r['seconds_saved'])] for r in statistics],
          r'Scale & Lower time & Higher time & Same rounded time & Net saved (s)')
    table(generated / 'contributions.tex', 'lrrrrr',
          [[str(r['scale']), number(r['core_original_seconds']), number(r['core_adopted_seconds']),
            number(r['core_seconds_saved']), f"{r['core_original_share_percent']:.1f}",
            f"{r['core_adopted_share_percent']:.1f}"] for r in statistics],
          r'Scale & Original (s) & Adopted (s) & Saved (s) & Original (\%) & Adopted (\%)')
    table(generated / 'case-ratios.tex', 'l' + 'r' * len(statistics),
          [[f'Q{n}'] + [f"{runs[r['scale'], 'original']['records'][n]['seconds']/runs[r['scale'], 'adopted']['records'][n]['seconds']:.2f}"
                         if runs[r['scale'], 'adopted']['records'][n]['seconds'] else '--'
                         for r in statistics] for n in (4, 5, 14, 23, 27, 31, 39, 51, 59, 67, 74)],
          'Query & ' + ' & '.join(f"SF{r['scale']}" for r in statistics))
    table(generated / 'step-growth.tex', 'lrrr',
          [[f"SF{previous['scale']}--SF{current['scale']}", f"{current['scale']/previous['scale']:.2f}",
            f"{current['original_seconds']/previous['original_seconds']:.2f}",
            f"{current['adopted_seconds']/previous['adopted_seconds']:.2f}"]
           for previous, current in zip(statistics, statistics[1:])],
          r'Scale step & Nominal multiplier & Original time multiplier & Adopted time multiplier')
    render_trends(assets, runs, statistics, environment)
    rows = []
    for n in [14, 23, 59, 4, 5, 39, 51, 27, 66, 74]:
        a, b = originals[n]['seconds'], adopted[n]['seconds']
        rows.append([f'Q{n}', number(a), number(b), f'{a/b:.2f}' if b else '--'])
    table(generated / 'selected-results.tex', 'lrrr', rows,
          r'Query & Original (s) & Adopted (s) & Observed $t_o/t_a$')
    scale_ids = sorted(comparisons)
    group_header = 'Query & ' + ' & '.join(r'\multicolumn{2}{c}{SF' + str(sf) + '}' for sf in scale_ids) + r' \\'
    column_header = ' & ' + ' & '.join(['Original & Adopted'] * len(scale_ids)) + r' \\'
    full = [r'\begin{longtable}{r' + 'rr' * len(scale_ids) + '}',
            r'\caption{Complete per-query runtimes in seconds at every measured scale.}\\',
            r'\toprule ' + group_header, column_header + r'\midrule\endfirsthead',
            r'\toprule ' + group_header, column_header + r'\midrule\endhead',
            r'\bottomrule\endfoot']
    for n in range(1, 100):
        full.append(' & '.join([f'Q{n}'] + [number(runs[sf, mode]['records'][n]['seconds'])
                                          for sf in scale_ids for mode in ('original', 'adopted')]) + r' \\')
    full.append(r'\midrule ' + ' & '.join([r'\textbf{Total}'] + [
        number(runs[sf, mode]['summary']['total_seconds']) for sf in scale_ids for mode in ('original', 'adopted')]) + r' \\')
    full.append(r'\end{longtable}')
    (generated / 'all-queries.tex').write_text('\n'.join(full) + '\n')
    selected = [14, 23, 59, 4, 5, 51, 27, 66, 74]
    data = assets / 'sf4-selected.dat'
    data.write_text('\n'.join(f'Q{n} {originals[n]["seconds"]} {adopted[n]["seconds"]}' for n in selected) + '\n')
    plot(data, assets / 'sf4-selected.pdf', 'SF4 query execution times',
         'Whole query-file elapsed time (seconds)', environment)
    # Controlled local medians remain separate from the Docker observations.
    local_path = REPO / 'experiments/evidence/riccio_sf1_20261014/measurements.csv'
    with local_path.open(newline='') as stream:
        local = list(csv.DictReader(stream))
    local_rows = []
    for n, variant in [(4, 'v2'), (5, 'v1'), (31, 'v2'), (39, 'v6'), (51, 'v1')]:
        profile = 'reference_q39_final' if n == 39 else 'reference'
        matches = [r for r in local if int(r['query']) == n and r['profile'] == profile]
        a = next(r for r in matches if r['variant'] == 'v0')
        b = next(r for r in matches if r['variant'] == variant)
        if any(r['n'] != '3' or r['all_strict_matches'] != 'True' for r in (a, b)):
            raise ValueError('local case-study repetitions or answer checks changed')
        local_rows.append([f'Q{n}', variant, number(float(a['median_seconds']), 3),
                           number(float(b['median_seconds']), 3),
                           f"{float(a['median_seconds'])/float(b['median_seconds']):.2f}"])
    table(generated / 'local-medians.tex', 'llrrr', local_rows,
          r'Query & Variant & Original median (s) & Candidate median (s) & Ratio')
    shutil.copyfile(local_path, generated / 'local-measurements.csv')
    # Derive every runtime CSV from the verified inputs, not a possibly stale
    # previous report/export. Keep answer status and per-run index counts.
    for sf in sorted(comparisons):
        with (generated / f'sf{sf}-comparison.csv').open('w', newline='') as stream:
            writer = csv.writer(stream, lineterminator='\n')
            writer.writerow(['query', 'original_seconds', 'adopted_seconds', 'answer_status', 'reviewed_status',
                             'original_indexes', 'adopted_indexes',
                             'original_sql_sha256', 'adopted_sql_sha256'])
            for n in range(1, 100):
                a, b = runs[sf, 'original']['records'][n], runs[sf, 'adopted']['records'][n]
                review = comparisons[sf].get('reviewed_tie_matches', {}).get(n, {})
                writer.writerow([n, a['seconds'], b['seconds'], comparisons[sf]['results'][n], review.get('status', ''),
                                 runs[sf, 'original']['summary'].get('indexes'),
                                 runs[sf, 'adopted']['summary'].get('indexes'),
                                 a['sql_sha256'], b['sql_sha256']])
    inventory = {'generated_at_utc': datetime.now(timezone.utc).isoformat(),
                 'adopted_optimization_ids': optimized,
                 'unsupported_legacy_scaling_table_used': False,
                 'statistics': statistics,
                 'runs': [{'scale': sf, 'mode': mode, 'source': str(r['path'].relative_to(REPO)),
                           'summary_sha256': r['summary_sha256'], 'summary': r['summary']}
                          for (sf, mode), r in sorted(runs.items())],
                 'comparisons': comparisons}
    (generated / 'evidence.json').write_text(json.dumps(inventory, indent=2) + '\n')
    (generated / 'campaign-statistics.json').write_text(json.dumps(statistics, indent=2) + '\n')


def build(output):
    for executable in ('xelatex', 'bibtex', 'gnuplot'):
        if not shutil.which(executable):
            raise ValueError(f'{executable} is required; no dependencies were installed')
    runs, comparisons = collect()
    sources = adopted_sources()
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    latex = output / 'latex'; latex.mkdir()
    builddir = output / 'build'; builddir.mkdir()
    env = {**os.environ, 'TEXMFVAR': str(builddir / 'tex-var'),
           'TEXMFCONFIG': str(builddir / 'tex-config'), 'XDG_CACHE_HOME': str(builddir / 'cache'),
           'BIBINPUTS': str(latex) + os.pathsep}
    for name in ('main.tex', 'metadata.tex', 'references.bib', 'README.txt'):
        shutil.copyfile(REPO / 'report/latex' / name, latex / name)
    shutil.copyfile(REPO / 'DSGen-software-code-4.0.0/EULA.txt', latex / 'TPC-EULA.txt')
    generate(latex, runs, comparisons, sources, env)
    preserved = latex / 'evidence'; preserved.mkdir()
    # Preserve completed inputs in the shareable source package. Exporting
    # live directories is offline and never executes queries or changes data.
    from submission import run_payload, write_zip
    for (sf, mode), run in sorted(runs.items()):
        destination = preserved / f'sf{sf}-{mode}.zip'
        if run['path'].is_file():
            shutil.copyfile(run['path'], destination)
        else:
            payload, _ = run_payload(run['path'])
            write_zip(destination, payload)
    command = ['xelatex', '-no-shell-escape', '-interaction=nonstopmode', '-halt-on-error',
               '-file-line-error', '-output-directory=' + str(builddir), 'main.tex']
    log = output / 'latex-build.log'
    with log.open('w') as stream:
        for step, cwd in [(command, latex), (['bibtex', 'main'], builddir),
                          (command, latex), (command, latex)]:
            result = subprocess.run(step, cwd=cwd, env=env, text=True,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=120)
            if result.returncode:
                raise ValueError(f'LaTeX build failed; inspect {log}')
    shutil.copyfile(builddir / 'main.pdf', output / 'TPCDS-Part-I-report.pdf')
    # Include the resolved bibliography for LaTeX-only services as well.
    shutil.copyfile(builddir / 'main.bbl', latex / 'main.bbl')
    members = {p.relative_to(latex).as_posix(): p.read_bytes()
               for p in sorted(latex.rglob('*')) if p.is_file()}
    manifest = {name: {'bytes': len(raw), 'sha256': sha(raw)} for name, raw in members.items()}
    members['SOURCE-MANIFEST.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    write_zip(output / 'TPCDS-Part-I-latex.zip', members)
    print(f'PDF: {output / "TPCDS-Part-I-report.pdf"}')
    print(f'Editable LaTeX/Overleaf ZIP: {output / "TPCDS-Part-I-latex.zip"}')
    print('Complete original/adopted scale pairs:', ', '.join(str(sf) for sf in sorted(comparisons)))
    print('The report contains completed measurements. No Docker or SQL was executed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='new output directory')
    args = parser.parse_args()
    build(args.out)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as exc:
        sys.exit(f'ERROR: {exc}')
