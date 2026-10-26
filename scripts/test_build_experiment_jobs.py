"""Exercise version selection, comparison controls and portable job manifests."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ExperimentJobs(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name)
        self.repo = self.parent / "original checkout"
        script = self.repo / "scripts/build_experiment_jobs.py"
        script.parent.mkdir(parents=True)
        shutil.copy2(Path(__file__).with_name("build_experiment_jobs.py"), script)
        self.script = script
        self.output = self.repo / "experiments/local/session/jobs.json"
        self.runs = self.output.parent / "runs"

    def sql(self, query, filename):
        path = self.repo / f"queries/optimized/q{query}" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("SELECT 1;\n", encoding="utf-8")

    def invoke(self, *options):
        return subprocess.run(
            [sys.executable, str(self.script), "--profile", "reference",
             "--runs", str(self.runs), "--output", str(self.output), *options],
            cwd=self.parent, capture_output=True, text=True,
        )

    def test_existing_query_selection_keeps_original_pair_order(self):
        self.sql(31, "query31_v0.sql")
        self.sql(31, "query31_v2_pivot.sql")
        result = self.invoke("--queries", "31")
        self.assertEqual(result.returncode, 0, result.stderr)
        jobs = json.loads(self.output.read_text())
        self.assertEqual([j["label"] for j in jobs], [
            "q31_v0_reference_warmup", "q31_v2_reference_warmup",
            "q31_v0_reference_r1", "q31_v2_reference_r1",
            "q31_v2_reference_r2", "q31_v0_reference_r2",
            "q31_v0_reference_r3", "q31_v2_reference_r3",
        ])

    def test_three_versions_rotate_and_survive_moving_the_checkout(self):
        for filename in ["query65_v0.sql", "query65_v1_window.sql",
                         "query65_v2_shared.sql", "query65_v10_other.sql"]:
            self.sql(65, filename)
        result = self.invoke("--queries", "65", "--variants", "v0,v1,v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        jobs = json.loads(self.output.read_text())
        self.assertEqual([j["label"].split("_")[1] for j in jobs], [
            "v0", "v1", "v2",  # warm-ups
            "v0", "v1", "v2",  # round 1
            "v1", "v2", "v0",  # round 2
            "v2", "v0", "v1",  # round 3
        ])
        self.assertNotIn("expect", jobs[0])
        moved = self.parent / "different depth/student's projects/renamed checkout"
        moved.parent.mkdir(parents=True)
        shutil.move(str(self.repo), str(moved))
        manifest = moved / self.output.relative_to(self.repo)
        expected = moved / self.runs.relative_to(self.repo) / "q65_v0_reference_warmup/result.json"
        for job in jobs:
            self.assertEqual(job["path_base"], "manifest")
            self.assertFalse(Path(job["file"]).is_absolute())
            source = (manifest.parent / job["file"]).resolve()
            self.assertTrue(source.is_file())
            self.assertNotEqual(source.name, "query65_v10_other.sql")
            if job is not jobs[0]:
                self.assertEqual((manifest.parent / job["expect"]).resolve(), expected)

    def test_missing_later_query_does_not_write_partial_jobs(self):
        self.sql(65, "query65_v0.sql")
        self.sql(65, "query65_v1_window.sql")
        self.sql(82, "query82_v0.sql")
        result = self.invoke("--queries", "65,82", "--variants", "v0,v1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Q82 v1", result.stderr)
        self.assertFalse(self.output.exists())

    def test_ambiguous_version_is_rejected(self):
        self.sql(65, "query65_v0.sql")
        self.sql(65, "query65_v1_window.sql")
        self.sql(65, "query65_v1_other.sql")
        result = self.invoke("--queries", "65", "--variants", "v0,v1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 2", result.stderr)
        self.assertFalse(self.output.exists())

    def test_invalid_comparison_labels_are_rejected(self):
        for variants in ["v1,v0", "v0", "v0,v1,v1", "v0,v01", "v0,../v1"]:
            with self.subTest(variants=variants):
                result = self.invoke("--queries", "65", "--variants", variants)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
