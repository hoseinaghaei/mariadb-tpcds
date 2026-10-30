"""Evidence preservation and release selection tests; no Docker/database needed."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import subprocess
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('course_submission', REPO / 'scripts/submission.py')
submission = importlib.util.module_from_spec(spec)
spec.loader.exec_module(submission)
from result_sets import FORMAT, fingerprints


class SubmissionEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = self.root / 'results/tuned'
        self.run.mkdir(parents=True)
        self.sql = b'SELECT 1;\n'
        self.answer = [{'columns': ['value', 'value'], 'rows': [[None, '1.00'], ['', '1.0']]}]

    def completed_run(self, structured=True):
        summary = dict(tag='tuned', queryset='smoke', queries=4, errors=0,
                       query_ids=[3, 12, 18, 76], scale=1, rngseed='10')
        if structured:
            summary['result_format'] = FORMAT
        (self.run / '_summary.json').write_text(json.dumps(summary))
        (self.run / 'answers').mkdir()
        for n in summary['query_ids']:
            source = self.root / f'queries/mariadb/query{n}.sql'
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(self.sql)
            record = dict(query=n, status='OK', queryset='smoke', rows=2,
                          result_set_rows=[2], result_set_columns=[['value', 'value']],
                          sql_file=str(source.relative_to(self.root)),
                          sql_sha256=submission.digest(self.sql), **fingerprints(self.answer))
            if structured:
                record['result_format'] = FORMAT
            (self.run / f'query{n}.json').write_text(json.dumps(record))
            (self.run / 'answers' / f'query{n}.json').write_text(json.dumps(self.answer))

    def test_complete_export_preserves_values_sql_and_hash_manifest(self):
        self.completed_run()
        payload, manifest = submission.run_payload(self.run, root=self.root)
        self.assertEqual(manifest['artifact_integrity'], 'VERIFIED')
        self.assertIsNone(manifest['execution_commit'])
        self.assertEqual(manifest['reference_answer_correctness'], 'NOT_ESTABLISHED_BY_EXPORT')
        self.assertEqual(manifest['missing_sql_snapshots'], [])
        self.assertEqual(json.loads(payload['run/answers/query3.json']), self.answer)
        self.assertEqual(payload['sql/query3.sql'], self.sql)
        for name, details in manifest['files'].items():
            self.assertEqual(submission.digest(payload[name]), details['sha256'])
        output = self.root / 'export.zip'
        submission.write_zip(output, payload)
        with zipfile.ZipFile(output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(set(archive.namelist()), set(payload))

    def test_incomplete_and_failed_runs_are_refused(self):
        with self.assertRaisesRegex(ValueError, 'no summary'):
            submission.run_payload(self.run, self.root)
        self.completed_run()
        (self.run / 'query3.json').unlink()
        with self.assertRaisesRegex(ValueError, 'coverage'):
            submission.run_payload(self.run, self.root)

    def test_tampered_answer_cannot_be_exported_as_verified(self):
        self.completed_run()
        (self.run / 'answers/query3.json').write_text('[{"columns":["value"],"rows":[["changed"]]}]')
        with self.assertRaisesRegex(ValueError, 'hashes'):
            submission.run_payload(self.run, self.root)

    def test_legacy_export_does_not_invent_answer_validation(self):
        self.completed_run(structured=False)
        payload, manifest = submission.run_payload(self.run, self.root)
        self.assertEqual(manifest['artifact_integrity'], 'LEGACY_RECORDS_ONLY')
        self.assertFalse(any('/answers/' in name for name in payload))

    def test_current_sql_change_recovers_matching_historical_contents(self):
        path = self.root / 'queries/mariadb/query3.sql'
        path.parent.mkdir(parents=True)
        path.write_text('SELECT 2;')
        with patch.object(submission, 'git', side_effect=[b'abc123\n', self.sql]):
            data, origin = submission.execution_sql('queries/mariadb/query3.sql',
                                                   submission.digest(self.sql), self.root)
        self.assertEqual(data, self.sql)
        self.assertIn('not an execution-commit claim', origin)

    def test_missing_sql_contents_are_disclosed(self):
        self.completed_run()
        with patch.object(submission, 'execution_sql', return_value=(None, 'unavailable')):
            payload, manifest = submission.run_payload(self.run, self.root)
        self.assertEqual(manifest['missing_sql_snapshots'], [3, 12, 18, 76])
        self.assertFalse(any(name.startswith('sql/') for name in payload))

    def test_recorded_sql_path_cannot_escape_checkout(self):
        for path in ('../private.sql', '/private.sql'):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'unsafe'):
                submission.execution_sql(path, 'unused', self.root)

    def test_existing_archive_is_not_overwritten(self):
        output = self.root / 'existing.zip'
        output.write_bytes(b'original evidence')
        with self.assertRaises(FileExistsError):
            submission.write_zip(output, {'new': b'data'})
        self.assertEqual(output.read_bytes(), b'original evidence')

    def test_source_package_excludes_unrelated_untracked_files(self):
        (self.root / 'README.md').write_text('instructions')
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/submission.py').write_text('source')
        (self.root / 'personal.env').write_text('private')
        with patch.object(submission, 'git', side_effect=[b'README.md\0',
                                                        b'scripts/submission.py\0personal.env\0']):
            payload = submission.source_payload(self.root)
        self.assertEqual(set(payload), {'README.md', 'scripts/submission.py'})

    def test_source_zip_can_be_rebuilt_without_git_metadata(self):
        (self.root / 'README.md').write_text('packaged instructions')
        (self.root / 'unrelated.txt').write_text('not part of the source inventory')
        (self.root / 'SUBMISSION-MANIFEST.json').write_text(json.dumps({
            'schema': 'tpcds-course-submission-v1', 'files': {'README.md': {}}}))
        with patch.object(submission, 'git', side_effect=subprocess.CalledProcessError(128, 'git')):
            payload = submission.source_payload(self.root)
        self.assertEqual(payload, {'README.md': b'packaged instructions'})

    def test_packaged_inventory_cannot_escape_the_source_root(self):
        (self.root / 'SUBMISSION-MANIFEST.json').write_text(json.dumps({
            'schema': 'tpcds-course-submission-v1', 'files': {'../private.txt': {}}}))
        with patch.object(submission, 'git', side_effect=FileNotFoundError('git')), \
                self.assertRaisesRegex(ValueError, 'unsafe source member'):
            submission.source_payload(self.root)

    def test_reported_table_remains_reported_and_sums_consistently(self):
        data = json.loads((REPO / 'report/submission_evidence.json').read_text())
        campaign = data['reported_scaling_campaign']
        self.assertEqual(campaign['evidence_level'], 'UNVERIFIED_TABLE_NOT_USED')
        self.assertFalse(campaign['use_in_submission_results'])
        self.assertFalse(campaign['raw_run_artifacts_available'])
        self.assertEqual(submission.digest((REPO / campaign['source']).read_bytes()), campaign['source_sha256'])
        self.assertEqual(len(campaign['query_measurements']), 40)
        for row in campaign['measurements']:
            total = sum(q['seconds_by_scale'][str(row['scale'])] for q in campaign['query_measurements'])
            self.assertAlmostEqual(total, row['seconds'], places=5)
        self.assertTrue(data['open_items'])

    def test_unsupported_campaign_is_not_rendered(self):
        evidence = {'reported_scaling_campaign': {'use_in_submission_results': False}}
        with patch.object(submission.subprocess, 'run') as run:
            submission.render_figures(evidence, self.root, {})
        run.assert_not_called()
        self.assertFalse((self.root / 'scaling.svg').exists())


if __name__ == '__main__':
    unittest.main()
