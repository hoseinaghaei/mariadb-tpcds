"""Offline evidence checks for the LaTeX report; no database or TeX required."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('latex_report', ROOT / 'scripts/build_latex_report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class ReportInputs(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def run_folder(self, name, queryset='all', indexes=190):
        path = self.root / name
        path.mkdir(); (path / 'answers').mkdir()
        answer = [{'columns': ['x', 'x'], 'rows': [[None, '1.00'], ['', '1.0']]}]
        summary = dict(queries=99, errors=0, query_ids=list(range(1, 100)),
                       result_format=report.FORMAT, queryset=queryset,
                       scale=1, rngseed='10', indexes=indexes, total_seconds=99.0)
        (path / '_summary.json').write_text(json.dumps(summary))
        for n in range(1, 100):
            r = dict(query=n, status='OK', queryset=queryset, result_format=report.FORMAT,
                     sql_sha256=report.sha(b'SELECT 1;'), seconds=1.0, rows=2,
                     result_set_rows=[2], result_set_columns=[['x', 'x']],
                     **report.fingerprints(answer))
            (path / f'query{n}.json').write_text(json.dumps(r))
            (path / 'answers' / f'query{n}.json').write_text(json.dumps(answer))
        return path

    def test_complete_run_preserves_nulls_duplicate_columns_and_numeric_text(self):
        r = report.read_run(self.run_folder('original'))
        self.assertEqual(len(r['records']), 99)
        self.assertEqual(r['answers'][1][0]['rows'], [[None, '1.00'], ['', '1.0']])

    def test_missing_query_cannot_become_a_successful_total(self):
        path = self.run_folder('original')
        (path / 'query99.json').unlink()
        with self.assertRaises(FileNotFoundError):
            report.read_run(path)

    def test_modified_answer_is_rejected(self):
        path = self.run_folder('original')
        (path / 'answers/query1.json').write_text('[{"columns":["x"],"rows":[["changed"]]}]')
        with self.assertRaisesRegex(ValueError, 'invalid query1'):
            report.read_run(path)

    def test_failed_summary_is_rejected(self):
        path = self.run_folder('original')
        p = path / '_summary.json'; summary = json.loads(p.read_text()); summary['errors'] = 1
        p.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'not a complete successful'):
            report.read_run(path)

    def test_total_must_match_per_query_timings(self):
        path = self.run_folder('original')
        p = path / '_summary.json'; summary = json.loads(p.read_text()); summary['total_seconds'] = 999
        p.write_text(json.dumps(summary))
        with self.assertRaisesRegex(ValueError, 'do not sum'):
            report.read_run(path)

    def test_index_difference_is_disclosed_without_hiding_matching_answers(self):
        a = report.read_run(self.run_folder('original'))
        b = report.read_run(self.run_folder('adopted', 'all-tuned', indexes=188))
        c = report.compare_pair(a, b)
        self.assertEqual(c['ordered_matches'], 99)
        self.assertEqual(c['declared_configuration_differences']['indexes'], [190, 188])

    def test_different_seed_cannot_be_a_valid_comparison(self):
        a = report.read_run(self.run_folder('original'))
        b = report.read_run(self.run_folder('adopted', 'all-tuned'))
        b['summary']['rngseed'] = '11'
        with self.assertRaisesRegex(ValueError, 'different rngseed'):
            report.compare_pair(a, b)

    def test_order_difference_is_not_silently_accepted(self):
        a = report.read_run(self.run_folder('original'))
        b = report.read_run(self.run_folder('adopted', 'all-tuned'))
        b['answers'][1][0]['rows'].reverse()
        c = report.compare_pair(a, b)
        self.assertEqual(c['ordered_matches'], 98)
        self.assertEqual(c['results'][1], 'ORDER_DIFFERENCE_REQUIRES_REVIEW')

    def test_selected_optimization_count_excludes_fallback_originals(self):
        sources = report.adopted_sources()
        self.assertEqual(len(sources), 40)
        original_ids = sorted(n for n, source in sources.items() if '/optimized/' not in source)
        self.assertEqual(original_ids, [38, 58, 66, 71, 77])
        self.assertEqual(sum('/optimized/' in source for source in sources.values()), 35)

    def test_preserved_bundles_work_without_active_result_directories(self):
        a = report.read_run(self.run_folder('original'))
        b = report.read_run(self.run_folder('adopted', 'all-tuned'))
        for sf in (1, 4):
            folder = self.root / f'experiments/evidence/docker_sf{sf}_99'
            folder.mkdir(parents=True)
            for filename in ('run.zip', 'original-run.zip'):
                (folder / filename).write_bytes(b'only the discovery path is tested here')

        def load(path):
            sf = 1 if 'docker_sf1_99' in str(path) else 4
            base = a if path.name == 'original-run.zip' else b
            return {**base, 'path': path, 'summary': {**base['summary'], 'scale': sf}}

        with patch.object(report, 'read_run', side_effect=load):
            runs, comparisons = report.collect(self.root)
        self.assertEqual(set(runs), {(1, 'original'), (1, 'adopted'), (4, 'original'), (4, 'adopted')})
        self.assertEqual(comparisons[1]['ordered_matches'], 99)
        self.assertFalse((self.root / 'results').exists())

    def generation_inputs(self, extra_scale=False):
        a = report.read_run(self.run_folder('original'))
        b = report.read_run(self.run_folder('adopted', 'all-tuned', 188))
        a['path'] = ROOT / 'results/test-report-original'
        b['path'] = ROOT / 'results/test-report-adopted'
        four_a = {**a, 'summary': {**a['summary'], 'scale': 4}}
        four_b = {**b, 'summary': {**b['summary'], 'scale': 4}}
        runs = {(4, 'original'): four_a, (4, 'adopted'): four_b}
        comparisons = {4: report.compare_pair(four_a, four_b)}
        if extra_scale:
            runs.update({(1, 'original'): a, (1, 'adopted'): b})
            comparisons[1] = report.compare_pair(a, b)
        return runs, comparisons

    def test_one_scale_does_not_become_a_scaling_curve(self):
        latex = self.root / 'latex'; latex.mkdir()
        runs, comparisons = self.generation_inputs()
        with patch.object(report, 'plot'), patch.object(report.subprocess, 'run') as process:
            report.generate(latex, runs, comparisons, report.adopted_sources(), {})
        process.assert_not_called()
        self.assertIn('No scaling curve', (latex / 'generated/scaling-figure.tex').read_text())
        scales = (latex / 'generated/scales.tex').read_text()
        self.assertNotIn('Pending', scales)
        self.assertIn('4 & 99.0 & 99.0', scales)
        self.assertNotIn('1 &', scales)

    def test_two_scales_include_only_measured_points_and_csv_from_inputs(self):
        latex = self.root / 'latex'; latex.mkdir()
        runs, comparisons = self.generation_inputs(extra_scale=True)
        with patch.object(report, 'plot'), patch.object(report.subprocess, 'run'):
            report.generate(latex, runs, comparisons, report.adopted_sources(), {})
        points = (latex / 'assets/scaling.dat').read_text().splitlines()
        self.assertEqual(points, ['1 99.0 99.0', '4 99.0 99.0'])
        with (latex / 'generated/sf1-comparison.csv').open(newline='') as stream:
            rows = list(report.csv.DictReader(stream))
        self.assertEqual(len(rows), 99)
        self.assertEqual(rows[0]['original_seconds'], '1.0')
        self.assertEqual(rows[0]['answer_status'], 'MATCH')

    def q71_example(self):
        original = [{'columns': ['brand_id', 'brand', 't_hour', 't_minute', 'ext_price'],
                     'rows': [['10', 'A', '8', '0', '3.00'], ['10', 'A', '9', '0', '3.00'],
                              ['11', 'X', '17', '0', None], ['11', 'Y', '18', '0', None]]}]
        adopted = [{'columns': original[0]['columns'],
                    'rows': [original[0]['rows'][1], original[0]['rows'][0],
                             original[0]['rows'][3], original[0]['rows'][2]]}]
        sql = 'select i_brand_id brand_id, i_brand brand,t_hour,t_minute,sum(ext_price) ext_price from t order by ext_price desc, i_brand_id;'
        return original, adopted, sql

    def test_q71_tied_row_permutations_include_null_prices(self):
        a, b, sql = self.q71_example()
        review = report.review_q71_ties(a, b, sql, sql)
        self.assertEqual(review['status'], 'EQUAL_VALUES_AND_VALID_ORDER_BY_TIES')
        self.assertEqual(review['changed_row_positions'], 4)

    def test_q71_different_values_are_never_accepted(self):
        a, b, sql = self.q71_example()
        b[0]['rows'] = [list(row) for row in b[0]['rows']]
        b[0]['rows'][0][1] = 'different'
        self.assertIsNone(report.review_q71_ties(a, b, sql, sql))

    def test_q71_wrong_sort_order_is_never_accepted(self):
        a, b, sql = self.q71_example()
        b[0]['rows'] = b[0]['rows'][2:] + b[0]['rows'][:2]
        self.assertIsNone(report.review_q71_ties(a, b, sql, sql))

    def test_q71_limit_or_changed_sql_requires_separate_review(self):
        a, b, sql = self.q71_example()
        limited = sql.rstrip(';') + ' LIMIT 100;'
        self.assertIsNone(report.review_q71_ties(a, b, limited, limited))
        self.assertIsNone(report.review_q71_ties(a, b, sql, sql.replace('from t', 'from other_t')))

    def test_executed_sql_uses_snapshot_when_working_query_has_changed(self):
        _, _, sql = self.q71_example()
        archive = self.root / 'experiments/evidence/docker_sf2_99/original-run.zip'
        archive.parent.mkdir(parents=True)
        with report.zipfile.ZipFile(archive, 'w') as stream:
            stream.writestr('sql/query71.sql', sql)
        working = self.root / 'queries/mariadb/query71.sql'
        working.parent.mkdir(parents=True); working.write_text('SELECT different_sql;')
        run = {'path': self.root / 'results/original/tuned',
               'summary': {'scale': 2, 'queryset': 'all'},
               'records': {71: {'sql_file': 'queries/mariadb/query71.sql',
                                'sql_sha256': report.sha(sql.encode())}}}
        with patch.object(report, 'REPO', self.root):
            self.assertEqual(report.executed_sql(run, 71), sql)

    def test_workload_ratio_uses_total_times_instead_of_mean_query_ratios(self):
        runs, comparisons = self.generation_inputs()
        a, b = runs[4, 'original'], runs[4, 'adopted']
        a['records'][1]['seconds'] = 100.0; b['records'][1]['seconds'] = 50.0
        a['summary']['total_seconds'] = 198.0; b['summary']['total_seconds'] = 148.0
        stat = report.campaign_statistics(runs, comparisons)[0]
        self.assertAlmostEqual(stat['ratio'], 198 / 148)
        self.assertNotAlmostEqual(stat['ratio'], 100 / 99)
        self.assertEqual(stat['faster'], 1)
        self.assertEqual(stat['slower'] + stat['same_rounded_time'], 98)

    def test_core_savings_account_for_offsets_in_other_queries(self):
        runs, comparisons = self.generation_inputs()
        a, b = runs[4, 'original'], runs[4, 'adopted']
        for n, seconds in [(14, 10.0), (23, 8.0), (59, 7.0)]:
            a['records'][n]['seconds'] = seconds; b['records'][n]['seconds'] = 2.0
        b['records'][10]['seconds'] = 6.0
        a['summary']['total_seconds'] = 121.0; b['summary']['total_seconds'] = 107.0
        stat = report.campaign_statistics(runs, comparisons)[0]
        self.assertEqual(stat['core_seconds_saved'], 19.0)
        self.assertEqual(stat['seconds_saved'], 14.0)
        self.assertEqual((stat['faster'], stat['slower'], stat['same_rounded_time']), (3, 1, 95))

    def test_four_scale_tables_contain_all_query_timings(self):
        latex = self.root / 'latex'; latex.mkdir()
        runs, comparisons = self.generation_inputs(extra_scale=True)
        for sf in (2, 3):
            for mode in ('original', 'adopted'):
                base = runs[1, mode]
                runs[sf, mode] = {**base, 'summary': {**base['summary'], 'scale': sf}}
            comparisons[sf] = report.compare_pair(runs[sf, 'original'], runs[sf, 'adopted'])
        with patch.object(report, 'plot'), patch.object(report.subprocess, 'run'):
            report.generate(latex, runs, comparisons, report.adopted_sources(), {})
        full = (latex / 'generated/all-queries.tex').read_text()
        self.assertIn(r'\multicolumn{2}{c}{SF4}', full)
        query_rows = [line for line in full.splitlines() if line.startswith('Q') and not line.startswith('Query')]
        self.assertEqual(len(query_rows), 99)
        self.assertTrue(all(line.count('&') == 8 for line in query_rows))
        self.assertEqual(len((latex / 'assets/normalized-growth.dat').read_text().splitlines()), 4)


if __name__ == '__main__':
    unittest.main()
