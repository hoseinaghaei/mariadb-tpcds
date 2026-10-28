"""Keep old reporting commands usable without comparing incompatible hashes."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'analysis'))
spec = importlib.util.spec_from_file_location('compatible_analysis', REPO / 'analysis/analyze.py')
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)
collector = sys.modules['collect']


def record(environment='docker', scale=1, query=1, **changes):
    row = dict(environment=environment, scale=scale, query=query, seconds=10.0,
               rows=1, status='OK', md5_sorted='same-answer', tag='fixture', rngseed='10',
               result_format='result-sets-json-v1', timing_protocol='whole-file-xml-v1')
    return {**row, **changes}


def anomalies(rows):
    runs = analysis.build(rows)
    return analysis.find_anomalies(runs, analysis.totals(runs))


class AnalysisCompatibility(unittest.TestCase):
    def test_collector_keeps_legacy_records_and_new_metadata_but_excludes_archives(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            latest = root / 'results/sf1/tuned'
            legacy = root / 'results/sf2/tuned'
            archived = root / 'results/sf1/.history/tuned/old/run'
            for directory in (latest, legacy, archived):
                directory.mkdir(parents=True)
                (directory / 'query1.json').write_text(json.dumps(
                    dict(query=1, seconds=1, rows=1, md5_sorted='answer', status='OK')))
            (latest / '_summary.json').write_text(json.dumps(dict(
                rngseed='10', result_format='result-sets-json-v1',
                timing_protocol='whole-file-xml-v1', queryset='all-tuned')))
            sources = [(str(root / 'results/sf*/tuned'), 'docker',
                        lambda p: int(Path(p).parent.name[2:]))]
            with patch.object(collector, 'SOURCES', sources):
                rows = collector.collect()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]['rngseed'], '10')
        self.assertEqual(rows[0]['queryset'], 'all-tuned')
        self.assertEqual(rows[0]['result_format'], 'result-sets-json-v1')
        self.assertIsNone(rows[1]['rngseed'])
        self.assertEqual(rows[1]['result_format'], 'legacy/unknown')

    def test_different_formats_are_not_reported_as_wrong_answers(self):
        rows = [record(), record('legacy', result_format='legacy-tsv', md5_sorted='different')]
        findings = anomalies(rows)
        self.assertTrue(any(a[0] == 'ANSWER CHECK SKIPPED' and 'formats' in a[2] for a in findings))
        self.assertFalse(any(a[0] == 'ANSWER MISMATCH' for a in findings))

    def test_unknown_or_different_seeds_require_explicit_review(self):
        for seed in (None, '11'):
            with self.subTest(seed=seed):
                findings = anomalies([record(), record('other', rngseed=seed, md5_sorted='different')])
                self.assertTrue(any(a[0] == 'ANSWER CHECK SKIPPED' for a in findings))
                self.assertFalse(any(a[0] == 'ANSWER MISMATCH' for a in findings))

    def test_several_wrong_row_counts_cannot_suppress_correctness_failures(self):
        rows = [record(query=q) for q in (1, 2)]
        rows += [record('other', query=q, rows=2, md5_sorted='different') for q in (1, 2)]
        findings = anomalies(rows)
        self.assertEqual([a[1] for a in findings if a[0] == 'ANSWER MISMATCH'], [1, 2])
        self.assertFalse(any(a[0] == 'DIFFERENT DATASET' for a in findings))

    def test_equal_seed_and_format_allow_hash_checks(self):
        self.assertIsNone(analysis.answer_comparison_problem(record(rngseed=10), record()))
        findings = anomalies([record(), record('other')])
        self.assertFalse(any(a[0] in ('ANSWER MISMATCH', 'ANSWER CHECK SKIPPED') for a in findings))

    def test_mixed_40_and_99_query_scales_do_not_crash_reporting(self):
        rows = [record(scale=s, query=q) for s, queries in
                ((1, range(1, 100)), (2, range(1, 41)), (3, range(1, 100))) for q in queries]
        runs = analysis.build(rows)
        totals = analysis.totals(runs)
        findings = analysis.find_anomalies(runs, totals)
        text, figures = analysis.report(runs, totals, findings)
        self.assertIn('| q99 | 10.0s | — | 10.0s | 1.0x |', text)
        self.assertTrue(figures)

    def test_mixed_protocols_keep_raw_times_but_suppress_scaling_ratios(self):
        rows = [record(scale=1, timing_protocol='legacy/unknown'), record(scale=4, seconds=100)]
        runs = analysis.build(rows)
        totals = analysis.totals(runs)
        findings = analysis.find_anomalies(runs, totals)
        self.assertTrue(any(a[0] == 'TIMING PROTOCOL CHANGE' for a in findings))
        self.assertFalse(any(a[0] == 'SUPER-LINEAR' for a in findings))
        text, _ = analysis.report(runs, totals, findings)
        self.assertIn('| q1 | 10.0s | 100.0s | — |', text)

    def test_mixed_protocols_suppress_environment_ratios(self):
        rows = [record(), record('legacy', timing_protocol='legacy/unknown', seconds=100)]
        runs = analysis.build(rows)
        totals = analysis.totals(runs)
        findings = analysis.find_anomalies(runs, totals)
        self.assertTrue(any(a[0] == 'TIMING PROTOCOL CHANGE' for a in findings))
        self.assertFalse(any(a[0] == 'ENVIRONMENT GAP' for a in findings))
        text, _ = analysis.report(runs, totals, findings)
        self.assertIn('| q1 | 10.0s | 100.0s | — |', text)


if __name__ == '__main__':
    unittest.main()
