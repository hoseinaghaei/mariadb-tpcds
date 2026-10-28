"""Coverage and result-integrity regression tests; no Docker/database needed."""
import csv
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'docker'))
from result_sets import canonical, compare_results, fingerprints, parse_results

spec = importlib.util.spec_from_file_location('correctness_bench', REPO / 'docker/bench.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)
bench.PROJECT = str(REPO)
bench.QDIR = str(REPO / 'queries/mariadb')
bench.TDIR = str(REPO / 'queries/tuned')


class ResultIntegrity(unittest.TestCase):
    def test_rows_cannot_move_between_result_sets(self):
        a = [{'columns': ['x'], 'rows': [['1']]}, {'columns': ['x'], 'rows': [['2']]}]
        b = [{'columns': ['x'], 'rows': [['2']]}, {'columns': ['x'], 'rows': [['1']]}]
        self.assertEqual(compare_results(a, b), 'MISMATCH')

    def test_only_rows_within_each_set_can_be_unordered(self):
        a = [{'columns': ['x'], 'rows': [['1'], ['2']]}]
        b = [{'columns': ['x'], 'rows': [['2'], ['1']]}]
        self.assertEqual(compare_results(a, b), 'ORDER_DIFFERENCE_REQUIRES_REVIEW')

    def test_duplicates_null_strings_and_numeric_text_are_distinct(self):
        base = [{'columns': ['x'], 'rows': [[None], ['NULL'], [''], ['1.00'], ['1.00']]}]
        variants = [base[0]['rows'][:-1], [['NULL'], ['NULL'], [''], ['1.00'], ['1.00']],
                    [[None], ['NULL'], [''], ['1.0'], ['1.00']]]
        for rows in variants:
            self.assertEqual(compare_results(base, [{'columns': ['x'], 'rows': rows}]), 'MISMATCH')

    def test_column_order_and_duplicate_names_are_preserved(self):
        a = [{'columns': ['x', 'x', 'y'], 'rows': [['1', '2', '3']]}]
        b = [{'columns': ['x', 'y', 'x'], 'rows': [['1', '2', '3']]}]
        self.assertNotEqual(fingerprints(a), fingerprints(b))

    def test_empty_set_and_no_result_are_different(self):
        empty = parse_results(b'<resultset/>')
        self.assertEqual(empty, [{'columns': [], 'rows': []}])
        canonical(empty)
        with self.assertRaisesRegex(ValueError, 'no SELECT'):
            canonical(parse_results(b''))

    def test_xml_preserves_embedded_delimiters_unicode_and_null(self):
        raw = ('<resultset xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
               '<row><field name="x">é;\t\r\n&#10;&amp;</field><field name="x" xsi:nil="true"/>'
               '</row></resultset>').encode()
        self.assertEqual(parse_results(raw)[0]['rows'], [['é;\t\r\n\n&', None]])

    def test_invalid_xml_and_inconsistent_projection_are_rejected(self):
        for raw in [b'not XML', b'<resultset><row><field name="x">1</field></row>'
                    b'<row><field name="y">2</field></row></resultset>']:
            with self.assertRaises(ValueError):
                parse_results(raw)


class CompleteWorkload(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_workload(self, which='all-tuned', failure=None, directory=None):
        directory = directory or self.root / which
        calls = []

        def client(command, **kwargs):
            if '-e' in command:
                sql = command[-1]
                value = ('32768' if sql == 'select @@innodb_page_size' else
                         '2147483648' if sql == 'select @@innodb_buffer_pool_size' else '160')
                return subprocess.CompletedProcess(command, 0, value, '')
            calls.append(kwargs['input'])
            n = len(calls)
            if n == 14 and failure:
                if failure == 'timeout':
                    raise subprocess.TimeoutExpired(command, kwargs['timeout'])
                if failure == 'malformed':
                    return subprocess.CompletedProcess(command, 0, b'broken XML', b'')
                return subprocess.CompletedProcess(command, 1, b'', b'ERROR test failure')
            one = b'<resultset><row><field name="value">1</field></row></resultset>'
            return subprocess.CompletedProcess(command, 0, one * (2 if n == 14 else 1), b'')

        argv = ['bench.py', '/unused', str(directory), 'tuned', which]
        with patch.object(sys, 'argv', argv), patch.object(bench.subprocess, 'run', side_effect=client), \
                patch.dict(os.environ, PROFILE='full', SCALE='4', RNGSEED='10', STATEMENT_TIMEOUT='10'), \
                redirect_stdout(io.StringIO()):
            code = bench.main()
        return directory, calls, code

    def test_99_files_include_adopted_queries_and_59_originals(self):
        items = bench.query_items('all-tuned')
        self.assertEqual([n for n, _ in items], list(range(1, 100)))
        self.assertEqual(sum('/tuned/' in p for _, p in items), 40)
        self.assertEqual(sum('/mariadb/' in p for _, p in items), 59)

    def test_missing_adopted_file_cannot_silently_fall_back(self):
        with patch.object(bench, 'TDIR', str(self.root)), self.assertRaisesRegex(ValueError, 'missing query files'):
            bench.query_items('all-tuned')

    def test_source_hashes_match_the_recorded_coverage_snapshot(self):
        import hashlib
        with (REPO / 'queries/correctness/coverage.csv').open() as f:
            rows = list(csv.DictReader(f))
        self.assertEqual([int(row['query']) for row in rows], list(range(1, 100)))
        for row in rows:
            for prefix in ('adapted', 'adopted'):
                if row[prefix + '_file']:
                    self.assertEqual(hashlib.sha256((REPO / row[prefix + '_file']).read_bytes()).hexdigest(),
                                     row[prefix + '_sql_sha256'])

    def test_complete_run_uses_whole_files_and_records_all_99(self):
        directory, calls, code = self.run_workload()
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 99)
        for payload, (_, path) in zip(calls, bench.query_items('all-tuned')):
            self.assertTrue(payload.endswith(Path(path).read_text(encoding='utf-8-sig').encode()))
            self.assertIn(b'SET SESSION max_statement_time=10;', payload)
        q14 = json.loads((directory / 'query14.json').read_text())
        self.assertEqual((q14['rows'], q14['result_set_rows']), (2, [1, 1]))
        with (directory / '_coverage.csv').open() as f:
            coverage = list(csv.DictReader(f))
        self.assertEqual(len(coverage), 99)
        self.assertTrue(all(row['correctness'] == 'NOT_COMPARED' for row in coverage))
        self.assertEqual(bench.verify_run(directory, 'all-tuned'), 99)

    def test_sql_timeout_and_output_failures_are_not_successful_coverage(self):
        for failure in ['sql', 'timeout', 'malformed']:
            directory = self.root / failure
            with self.subTest(failure=failure), self.assertRaisesRegex(ValueError, 'errors'):
                self.run_workload(failure=failure, directory=directory)
            summary = json.loads((directory / '_summary.json').read_text())
            self.assertEqual((summary['queries'], summary['errors']), (99, 1))

    def test_saved_answer_tampering_is_detected(self):
        directory, _, _ = self.run_workload()
        answer = directory / 'answers/query1.json'
        answer.write_text('[{"columns":["value"],"rows":[["different"]]}]')
        with self.assertRaisesRegex(ValueError, 'recorded hashes'):
            bench.verify_run(directory, 'all-tuned')

    def test_repeat_commands_archive_answers_and_keep_latest_paths(self):
        directory = self.root / 'tuned'
        for which in ('all-tuned', 'tuned', 'all-tuned'):
            previous = ({str(p.relative_to(directory)): p.read_bytes()
                         for p in directory.rglob('*') if p.is_file()}
                        if directory.exists() else {})
            _, calls, code = self.run_workload(which, directory=directory)
            self.assertEqual((code, len(calls)), (0, len(bench.query_items(which))))
            self.assertEqual(bench.verify_run(directory, which), len(calls))
            if previous:
                archive = sorted((self.root / '.history/tuned').iterdir())[-1] / 'run'
                saved = {str(p.relative_to(archive)): p.read_bytes()
                         for p in archive.rglob('*') if p.is_file()}
                self.assertEqual(saved, previous)
        self.assertEqual(len(list((self.root / '.history/tuned').iterdir())), 2)

    def test_legacy_answers_are_preserved_and_new_run_still_works(self):
        directory = self.root / 'tuned'
        directory.mkdir()
        legacy = b'{"query": 999, "md5": "historical-tsv-hash"}\n'
        (directory / 'query999.json').write_bytes(legacy)
        (directory / '_summary.json').write_text('{"errors": 0}')
        self.run_workload(directory=directory)
        self.assertFalse((directory / 'query999.json').exists())
        archives = list((self.root / '.history/tuned').iterdir())
        self.assertEqual(len(archives), 1)
        self.assertEqual((archives[0] / 'run/query999.json').read_bytes(), legacy)
        self.assertEqual(bench.verify_run(directory, 'all-tuned'), 99)

    def test_legacy_artifacts_are_not_accepted_as_new_format(self):
        directory, _, _ = self.run_workload()
        summary = json.loads((directory / '_summary.json').read_text())
        summary.pop('result_format')
        (directory / '_summary.json').write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'legacy'):
            bench.verify_run(directory, 'all-tuned')

    def test_log_is_archived_before_reopening_and_stale_comparison_is_preserved(self):
        directory = self.root / 'tuned'
        directory.mkdir()
        (directory / '_summary.json').write_bytes(b'old summary\n')
        logfile = self.root / 'tuned.log'
        logfile.write_bytes(b'previous run log\n')
        comparison = self.root / '_answer_comparison.json'
        comparison.write_bytes(b'previous comparison\n')
        argv = ['bench.py', '--prepare-output', str(directory), str(logfile)]
        with patch.object(sys, 'argv', argv), patch.object(bench.subprocess, 'run') as client, \
                redirect_stdout(io.StringIO()):
            self.assertEqual(bench.main(), 0)
        client.assert_not_called()
        archive = next((self.root / '.history/tuned').iterdir())
        self.assertEqual(archive.stat().st_mode & 0o777, 0o755)
        self.assertEqual((archive / 'run/_summary.json').read_bytes(), b'old summary\n')
        self.assertEqual((archive / 'tuned.log').read_bytes(), b'previous run log\n')
        self.assertEqual((archive / '_answer_comparison.json').read_bytes(), b'previous comparison\n')
        self.assertEqual(list(directory.iterdir()), [])
        self.assertFalse(comparison.exists())
        logfile.write_text('new log')  # What tee does after --prepare-output.
        with redirect_stdout(io.StringIO()):
            self.assertIsNone(bench.prepare_output(directory))
        self.assertEqual(logfile.read_text(), 'new log')

    def test_archive_failure_stops_before_connecting_or_overwriting(self):
        directory = self.root / 'tuned'
        directory.mkdir()
        old = directory / '_summary.json'
        old.write_text('previous run')
        argv = ['bench.py', '/unused', str(directory), 'tuned', 'all-tuned']
        with patch.object(sys, 'argv', argv), \
                patch.object(Path, 'rename', side_effect=PermissionError('archive blocked')), \
                patch.object(bench.subprocess, 'run') as client, \
                self.assertRaisesRegex(PermissionError, 'archive blocked'):
            bench.main()
        client.assert_not_called()
        self.assertEqual(old.read_text(), 'previous run')

    def test_comparison_matches_99_and_rejects_different_dataset_or_coverage(self):
        expected, _, _ = self.run_workload('all')
        actual, _, _ = self.run_workload('all-tuned')
        comparison = bench.compare_runs(expected, actual)
        self.assertTrue(comparison['all_ordered_results_match'])
        self.assertEqual(comparison['queries'], 99)
        summary_file = actual / '_summary.json'
        summary = json.loads(summary_file.read_text())
        summary['rngseed'] = '11'
        summary_file.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'different rngseed'):
            bench.compare_runs(expected, actual)
        subset, _, _ = self.run_workload('smoke')
        with self.assertRaisesRegex(ValueError, 'different query coverage'):
            bench.compare_runs(expected, subset)

    def test_comparison_cli_fails_on_answer_difference_without_connecting(self):
        expected, _, _ = self.run_workload('all')
        actual, _, _ = self.run_workload('all-tuned')
        answer = [{'columns': ['value'], 'rows': [['changed']]}]
        (actual / 'answers/query1.json').write_text(json.dumps(answer))
        path = actual / 'query1.json'
        record = json.loads(path.read_text())
        record.update(fingerprints(answer))
        path.write_text(json.dumps(record))
        out = io.StringIO()
        with patch.object(sys, 'argv', ['bench.py', '--compare', str(expected), str(actual)]), \
                patch.object(bench.subprocess, 'run') as client, redirect_stdout(out):
            self.assertEqual(bench.main(), 1)
        client.assert_not_called()
        comparison = json.loads(out.getvalue())
        self.assertEqual(comparison['results'][0]['status'], 'MISMATCH')

    def test_adopted_q70_fix_survives_regeneration(self):
        spec = importlib.util.spec_from_file_location('correctness_builder', REPO / 'queries/build-tuned.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        body, dropped = builder.clean((REPO / 'queries/optimized/q70-sf4/query70_v1_nosubquery.sql').read_text())
        expected = ('-- query70\n-- source: queries/optimized/q70-sf4/query70_v1_nosubquery.sql\n\n'
                    + builder.SQLMODE + '\n\n' + body)
        self.assertFalse(dropped)
        self.assertEqual((REPO / 'queries/tuned/query70.sql').read_text(), expected)


if __name__ == '__main__':
    unittest.main()
