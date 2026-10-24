"""Check that batch failures cannot silently skip validation or execute later jobs."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run_query_batch


class BatchFailureSafety(unittest.TestCase):
    def invoke(self, jobs, result_codes):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "jobs.json"
            path.write_text(json.dumps(jobs))
            argv = ["run_query_batch.py", "--database", "tpcds_test",
                    "--jobs", str(path), "--out", str(Path(name) / "runs")]
            from subprocess import CompletedProcess
            results = [CompletedProcess([], code) for code in result_codes]
            with patch("sys.argv", argv), patch("run_query_batch.subprocess.run", side_effect=results) as run:
                code = run_query_batch.main()
                return code, run.call_count

    def test_failure_stops_later_trials(self):
        jobs = [{"file": "q.sql", "label": f"trial{i}", "profile": "pk"} for i in range(3)]
        code, count = self.invoke(jobs, [0, 1])
        self.assertEqual((code, count), (1, 2))

    def test_invalid_later_job_fails_before_any_trial(self):
        jobs = [{"file": "q.sql", "label": "first", "profile": "pk"},
                {"file": "q.sql", "label": "second", "profile": "pk", "command": "ignored?"}]
        with patch("run_query_batch.subprocess.run") as run:
            with self.assertRaises(SystemExit):
                self.invoke(jobs, [])
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
