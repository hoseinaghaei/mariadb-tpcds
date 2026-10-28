"""Exercise reproduction settings with a fake Docker CLI; no daemon or DB needed."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout


REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'docker'))
CONFIG_KEYS = (REPO / 'docker/profiles.sh').read_text().split('TPCDS_CONFIG_KEYS="', 1)[1].split('"', 1)[0].split()
spec = importlib.util.spec_from_file_location('docker_bench', REPO / 'docker/bench.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class ReproductionCLI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.checkout = self.root / 'checkout with spaces'
        (self.checkout / 'docker').mkdir(parents=True)
        for filename in ['reproduce.sh', 'run-scales.sh', 'docker/profiles.sh']:
            shutil.copy2(REPO / filename, self.checkout / filename)
        binary = self.root / 'bin'
        binary.mkdir()
        self.log = self.root / 'docker.jsonl'
        fake = binary / 'docker'
        fake.write_text(f'''#!{sys.executable}
import json, os, sys
with open(os.environ['FAKE_DOCKER_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'info' and '--format' in sys.argv:
    print(os.environ['FAKE_DOCKER_MEMORY'])
elif sys.argv[1] == 'build':
    print('fake-image')
elif sys.argv[1] not in ('info', 'run'):
    sys.exit(2)
''')
        fake.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items()
                    if k not in CONFIG_KEYS + ['RESULTS_DIR', 'VOLUME']}
        self.env.update(PATH=str(binary) + os.pathsep + self.env['PATH'],
                        FAKE_DOCKER_LOG=str(self.log),
                        FAKE_DOCKER_MEMORY=str(16 * 1024**3))

    def invoke(self, *args, memory_gib=16, **environment):
        env = {**self.env, **environment, 'FAKE_DOCKER_MEMORY': str(memory_gib * 1024**3)}
        return subprocess.run(['bash', str(self.checkout / 'reproduce.sh'), *args],
                              cwd=self.root, env=env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def forwarded(self):
        run = next(call for call in reversed(self.calls()) if call[0] == 'run')
        return dict(run[i + 1].split('=', 1) for i, value in enumerate(run) if value == '-e')

    def test_cli_override_is_checked_and_forwarded(self):
        result = self.invoke('quick', 'BUFFER_POOL=4G', memory_gib=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('buffer pool 4G', result.stdout)
        self.assertEqual(self.forwarded()['BUFFER_POOL'], '4G')
        self.assertEqual([call[0] for call in self.calls()], ['info', 'info', 'build', 'run'])

    def test_environment_is_forwarded_and_cli_has_precedence(self):
        result = self.invoke('BUFFER_POOL=2G', memory_gib=6, BUFFER_POOL='8G')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.forwarded()['BUFFER_POOL'], '2G')

    def test_environment_override_without_arguments(self):
        result = self.invoke(memory_gib=6, BUFFER_POOL='2G')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.forwarded()['BUFFER_POOL'], '2G')

    def test_reference_defaults_remain_unchanged(self):
        result = self.invoke('full')
        self.assertEqual(result.returncode, 0, result.stderr)
        settings = self.forwarded()
        self.assertEqual((settings['SCALE'], settings['BUFFER_POOL']), ('4', '8G'))
        self.assertEqual(settings['TMP_TABLE_SIZE'], '1536M')
        self.assertEqual(settings['ARIA_PAGECACHE_BUFFER_SIZE'], '1G')
        self.assertEqual(settings['QUERYSET'], 'tuned')

    def test_all_tuned_workload_is_forwarded(self):
        result = self.invoke('quick', 'QUERYSET=all-tuned')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.forwarded()['QUERYSET'], 'all-tuned')

    def test_previous_commands_can_be_repeated_without_changing_storage_or_defaults(self):
        commands = [(), ('full', 'BUFFER_POOL=2G'),
                    ('quick', 'QUERYSET=tier45', 'TUNED=both'), ('smoke',)]
        for command in commands:
            with self.subTest(command=command):
                for _ in range(2):
                    result = self.invoke(*command)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    settings = self.forwarded()
                    smoke = command == ('smoke',)
                    self.assertEqual(settings['RNGSEED'], '10')
                    self.assertEqual(settings['MARIADB_TAG'], '13.0.2')
                    self.assertEqual(settings['QUERYSET'], 'smoke' if smoke else
                                     'tier45' if 'QUERYSET=tier45' in command else 'tuned')
                    run = self.calls()[-1]
                    self.assertIn(str(self.checkout) + ':/project:ro', run)
                    self.assertIn(('tpcds-smoke-data' if smoke else 'tpcds-data') + ':/data', run)
                    output = self.checkout / ('results/smoke' if smoke else 'results')
                    self.assertIn(str(output) + ':/results', run)

    def test_scale_sweep_retains_commands_and_per_scale_paths_on_repeat(self):
        for _ in range(2):
            result = subprocess.run(
                ['bash', str(self.checkout / 'run-scales.sh'), '2', '3', 'BUFFER_POOL=2G'],
                cwd=self.root, env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        runs = [c for c in self.calls() if c[0] == 'run' and c[-1] == 'tpcds-mariadb']
        self.assertEqual(len(runs), 4)
        for run, scale in zip(runs, (2, 3, 2, 3)):
            settings = dict(run[i + 1].split('=', 1) for i, value in enumerate(run) if value == '-e')
            self.assertEqual((settings['SCALE'], settings['BUFFER_POOL'], settings['RNGSEED']),
                             (str(scale), '2G', '10'))
            self.assertEqual(settings['QUERYSET'], 'tuned')
            self.assertIn(f'tpcds-data-sf{scale}:/data', run)
            self.assertIn(str(self.checkout / f'results/sf{scale}') + ':/results', run)

    def test_smoke_has_small_limits_and_separate_storage(self):
        result = self.invoke('smoke', memory_gib=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        settings = self.forwarded()
        self.assertEqual((settings['BUFFER_POOL'], settings['QUERYSET']), ('1G', 'smoke'))
        self.assertEqual(settings['ARIA_PAGECACHE_BUFFER_SIZE'], '64M')
        self.assertEqual(settings['TMP_TABLE_SIZE'], '32M')
        self.assertEqual(settings['JOIN_BUFFER_SIZE'], '4M')
        run = self.calls()[-1]
        self.assertIn('tpcds-smoke-data:/data', run)
        self.assertIn(str(self.checkout / 'results/smoke') + ':/results', run)

    def test_custom_smoke_output_stays_separate(self):
        result = self.invoke('smoke', RESULTS_DIR=str(self.root / 'outputs'), memory_gib=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(self.root / 'outputs/smoke') + ':/results', self.calls()[-1])

    def test_memory_units(self):
        for size, forwarded in [('1024M', '1024M'), ('1g', '1G'), ('1073741824', '1073741824')]:
            with self.subTest(size=size):
                result = self.invoke('smoke', 'BUFFER_POOL=' + size, memory_gib=2)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.forwarded()['BUFFER_POOL'], forwarded)

    def test_insufficient_memory_fails_before_build_or_output(self):
        result = self.invoke('quick', 'BUFFER_POOL=4G', memory_gib=6)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('BUFFER_POOL=4G', result.stderr)
        self.assertIn('./reproduce.sh smoke', result.stderr)
        self.assertTrue(all(call[0] == 'info' for call in self.calls()))
        self.assertFalse((self.checkout / 'results').exists())

    def test_other_buffers_are_included_in_memory_check(self):
        result = self.invoke('smoke', 'TMP_TABLE_SIZE=2G', 'MAX_HEAP_TABLE_SIZE=2G', memory_gib=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('build', [call[0] for call in self.calls()])

    def test_invalid_memory_sizes_fail_before_docker(self):
        for value in ['0', '-1G', '1.5G', 'lots', '9999999999999999999G']:
            with self.subTest(value=value):
                result = self.invoke('BUFFER_POOL=' + value)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_unknown_or_empty_options_fail_before_docker(self):
        for option in ['buffer_pool=4g', 'PATH=/tmp', 'BUFFER_POOL=', '=1G']:
            with self.subTest(option=option):
                result = self.invoke(option)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_image_override_applies_at_build_time(self):
        result = self.invoke('MARIADB_TAG=11.4')
        self.assertEqual(result.returncode, 0, result.stderr)
        build = next(call for call in self.calls() if call[0] == 'build')
        self.assertIn('MARIADB_TAG=11.4', build)

    def test_smoke_rejects_query_files_with_memory_overrides(self):
        result = self.invoke('smoke', 'QUERYSET=tuned')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_shared_container_defaults_match_wrapper(self):
        # Direct container invocation sources this same file, with no Docker
        # calls involved in checking its default configuration here.
        code = '. "$1"; tpcds_profile_defaults; tpcds_validate_config; tpcds_memory_cnf'
        result = subprocess.run(['bash', '-eu', '-c', code, 'profiles', str(REPO / 'docker/profiles.sh')],
                                env={**self.env, 'PROFILE': 'smoke'}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('tmp_table_size                 = 32M', result.stdout)
        self.assertIn('aria_pagecache_buffer_size     = 64M', result.stdout)

    def test_smoke_limits_apply_during_setup(self):
        # Exercise only the real config-writing function, not the entrypoint's
        # generator, service or database operations.
        source = (REPO / 'docker/entrypoint.sh').read_text()
        function = source[source.index('write_cnf() {'):source.index('\nstart_server() {')]
        code = '. "$1"; tpcds_profile_defaults; tpcds_validate_config; MEMORY_BLOCK=$(tpcds_memory_cnf)\n'
        code += function + '\nwrite_cnf ""\n'
        env = {**self.env, 'PROFILE': 'smoke', 'DATA': str(self.root),
               'DATADIR': '/unused/data', 'SOCK': '/unused/socket'}
        result = subprocess.run(['bash', '-eu', '-c', code, 'config', str(REPO / 'docker/profiles.sh')],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.root / 'my.cnf').read_text()
        self.assertIn('innodb_buffer_pool_size        = 1G', config)
        self.assertIn('tmp_table_size                 = 32M', config)
        self.assertIn('aria_pagecache_buffer_size     = 64M', config)
        self.assertIn('join_buffer_size               = 4M', config)
        self.assertIn('max_statement_time             = 3600', config)

    def test_entrypoint_repeat_archives_log_before_tee_and_keeps_workloads_separate(self):
        # Run the actual benchmark function and Python harness, substituting
        # only service/configuration operations and the MariaDB client. No
        # Docker daemon, database, dataset generation or SQL execution occurs.
        client = self.root / 'bin/mariadb'
        client.write_text(f'''#!{sys.executable}
import sys
if '-e' in sys.argv:
    sql = sys.argv[-1]
    print(32768 if sql == 'select @@innodb_page_size' else
          2147483648 if sql == 'select @@innodb_buffer_pool_size' else 160)
else:
    sys.stdin.buffer.read()
    print('<resultset><row><field name="value">1</field></row></resultset>')
''')
        client.chmod(0o755)
        output = self.root / 'outputs with spaces'
        prior = output / 'tuned'
        prior.mkdir(parents=True)
        (prior / '_summary.json').write_text('legacy summary')
        (prior / 'query999.json').write_text('legacy record')
        (output / 'tuned.log').write_text('legacy log\n')
        (output / '_answer_comparison.json').write_text('legacy comparison')
        source = (REPO / 'docker/entrypoint.sh').read_text()
        function = source[source.index('run_one() {'):source.index('\nTUNING_BLOCK=')]
        function = function.replace('/usr/local/bin/bench.py', '"$BENCH_SCRIPT"')
        code = ('stop_server() { :; }; write_cnf() { :; }; chown() { :; }; '
                'start_server() { :; }; check_settings() { :; }\n')
        code += function + '\nrun_one tuned ""\nQUERYSET=all-tuned\nrun_one tuned ""\n'
        code += 'QUERYSET=tuned\nrun_one tuned ""\nrun_one baseline ""\n'
        reporting = source[source.index('python3 - "$RESULTS" "$PROFILE" "$QUERYSET" "$TUNED"'):
                           source.index('\nsay "Done"')]
        code += reporting
        env = {**self.env, 'RESULTS': str(output), 'DATA': str(self.root),
               'BENCH_SCRIPT': str(REPO / 'docker/bench.py'), 'PROFILE': 'full',
               'SOCK': '/unused/socket', 'QUERYSET': 'tuned', 'SCALE': '4',
               'RNGSEED': '10', 'STATEMENT_TIMEOUT': '10', 'PYTHONDONTWRITEBYTECODE': '1',
               'TUNED': 'both', 'PYTHONPATH': str(REPO / 'docker')}
        result = subprocess.run(['bash', '-Eeuo', 'pipefail', '-c', code],
                                env=env, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(bench.verify_run(prior, 'tuned'), 40)
        archives = sorted((output / '.history/tuned').iterdir())
        self.assertEqual(len(archives), 3)
        self.assertEqual((archives[0] / 'run/query999.json').read_text(), 'legacy record')
        self.assertEqual((archives[0] / 'tuned.log').read_text(), 'legacy log\n')
        self.assertEqual((archives[0] / '_answer_comparison.json').read_text(), 'legacy comparison')
        self.assertEqual(bench.verify_run(archives[1] / 'run', 'tuned'), 40)
        self.assertEqual(bench.verify_run(archives[2] / 'run', 'all-tuned'), 99)
        for archived, count in ((archives[1], 40), (archives[2], 99)):
            self.assertIn(f'over {count} queries, 0 errors', (archived / 'tuned.log').read_text())
        self.assertIn('over 40 queries, 0 errors', (output / 'tuned.log').read_text())
        comparison = json.loads((output / '_answer_comparison.json').read_text())
        self.assertEqual(comparison['queries'], 40)
        self.assertTrue(comparison['all_ordered_results_match'])


class SmokeExecution(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        self.qdir = patch.object(bench, 'QDIR', str(REPO / 'queries/mariadb'))
        self.qdir.start()
        self.addCleanup(self.qdir.stop)

    def run_bench(self, failure=None):
        def client(command, **kwargs):
            sql = command[-1] if '-e' in command else ''
            if sql.startswith('select @@'):
                name = sql.removeprefix('select @@')
                value = {'innodb_page_size': 32768, 'innodb_stats_persistent_sample_pages': 160,
                         'innodb_buffer_pool_size': 1024**3}.get(name, 32 * 1024**2)
                return subprocess.CompletedProcess(command, 0, str(value), '')
            if sql.startswith('select count('):
                return subprocess.CompletedProcess(command, 0, '24', '')
            if failure == 'timeout':
                raise subprocess.TimeoutExpired(command, kwargs.get('timeout'))
            if failure == 'sql':
                return subprocess.CompletedProcess(command, 1, b'', b'ERROR 1234: test failure')
            return subprocess.CompletedProcess(command, 0,
                b'<resultset><row><field name="value">1</field></row></resultset>', b'')

        argv = ['bench.py', '/unused/socket', str(self.output), 'tuned', 'smoke']
        with patch.object(sys, 'argv', argv), patch.object(bench.subprocess, 'run', side_effect=client), \
                patch.dict(os.environ, PROFILE='smoke', SCALE='1', RNGSEED='10', STATEMENT_TIMEOUT='300'), \
                patch.object(bench.time, 'perf_counter', side_effect=[1, 1.1] * 4), redirect_stdout(io.StringIO()):
            return bench.main()

    def test_fast_smoke_run_passes_and_records_actual_configuration(self):
        self.assertEqual(self.run_bench(), 0)
        summary = json.loads((self.output / '_summary.json').read_text())
        self.assertLess(summary['total_seconds'], 5)
        self.assertEqual(summary['query_ids'], [3, 12, 18, 76])
        self.assertEqual(summary['purpose'], 'functional-check')
        self.assertEqual(summary['profile'], 'smoke')
        self.assertEqual(summary['buffer_pool_bytes'], 1024**3)
        self.assertEqual(summary['server_settings_bytes']['tmp_table_size'], 32 * 1024**2)
        self.assertEqual(bench.verify_run(self.output, 'smoke'), 4)

    def test_sql_errors_and_timeouts_cannot_pass(self):
        for failure in ['sql', 'timeout']:
            self.output = Path(self.temp.name) / failure
            with self.subTest(failure=failure), self.assertRaisesRegex(ValueError, 'errors'):
                self.run_bench(failure)

    def test_missing_query_files_are_not_silently_skipped(self):
        with patch.object(bench, 'QDIR', str(self.output)), self.assertRaisesRegex(ValueError, 'missing query files'):
            bench.query_items('smoke')

    def test_missing_hash_is_rejected(self):
        self.run_bench()
        path = self.output / 'query3.json'
        result = json.loads(path.read_text())
        del result['md5']
        path.write_text(json.dumps(result))
        with self.assertRaisesRegex(ValueError, 'hashes'):
            bench.verify_run(self.output, 'smoke')

    def test_missing_and_stale_query_artifacts_are_rejected(self):
        self.run_bench()
        missing = self.output / 'query3.json'
        saved = missing.read_bytes()
        missing.unlink()
        with self.assertRaisesRegex(ValueError, 'missing or unexpected'):
            bench.verify_run(self.output, 'smoke')
        missing.write_bytes(saved)
        (self.output / 'query999.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'unexpected'):
            bench.verify_run(self.output, 'smoke')


if __name__ == '__main__':
    unittest.main()
