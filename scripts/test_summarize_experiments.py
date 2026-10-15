"""Keep speedup calculations from mixing profiles or including failed trials."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import summarize_experiments


class MeasurementProtocol(unittest.TestCase):
    def test_medians_exclude_probes_failures_and_other_configurations(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            records = []
            for variant, configuration, seconds in [
                ("v0", "A", [10, 20, 30]), ("v1", "A", [2, 4, 6]),
                ("v1", "B", [1, 1, 1]),
            ]:
                for rep, value in enumerate(seconds, 1):
                    records.append({"label": f"q31_{variant}_pk_{configuration}_r{rep}",
                                    "variant": variant, "configuration": configuration,
                                    "seconds": value, "status": "OK"})
            records.extend([
                {"label": "q31_v0_pk_probe", "variant": "v0", "configuration": "A",
                 "seconds": 1000, "status": "OK"},
                {"label": "q31_v1_pk_A_r4", "variant": "v1", "configuration": "A",
                 "seconds": 1000, "status": "RESULT_DIFF"},
            ])
            for record in records:
                directory = root / "runs" / record["label"]
                directory.mkdir(parents=True)
                record.update(mode="run", profile_label="pk", database="tpcds_test",
                              scale_label=1, data_seed_label=10, context=[record.pop("configuration")],
                              sql_sha256=record.pop("variant"), result_set_rows=[44], strict_result_match=True)
                (directory / "run.json").write_text(json.dumps(record))
            argv = ["summarize_experiments.py", "--runs", str(root / "runs"),
                    "--out", str(root / "summary")]
            with patch("sys.argv", argv), contextlib.redirect_stdout(io.StringIO()):
                summarize_experiments.main()
            summary = json.loads((root / "summary/summary.json").read_text())
            self.assertEqual(len(summary["groups"]), 3)
            medians = sorted(row["median_seconds"] for row in summary["groups"])
            self.assertEqual(medians, [1, 4, 20])
            candidate_a = next(row for row in summary["groups"] if row["median_seconds"] == 4)
            self.assertEqual(candidate_a["speedup_vs_same_profile_v0"], 5)
            candidate_b = next(row for row in summary["groups"] if row["median_seconds"] == 1)
            self.assertIsNone(candidate_b["speedup_vs_same_profile_v0"])
            self.assertTrue(all(row["n"] == 3 for row in summary["groups"]))
            self.assertEqual(summary["failed_repetitions"],
                             [{"label": "q31_v1_pk_A_r4", "status": "RESULT_DIFF"}])


if __name__ == "__main__":
    unittest.main()
