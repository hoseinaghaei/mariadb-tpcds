"""Check that composite relationships are neither omitted nor reduced to one key."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_ri_check


class RelationshipCoverage(unittest.TestCase):
    def test_all_relationships_and_composite_null_rules(self):
        with tempfile.TemporaryDirectory() as name:
            output = Path(name) / "relationships.sql"
            with patch("sys.argv", ["build_ri_check.py", "--output", str(output)]), \
                    contextlib.redirect_stdout(io.StringIO()):
                build_ri_check.main()
            manifest = json.loads(output.with_suffix(".json").read_text())
            self.assertEqual(manifest["relationship_count"], 107)
            sql = output.read_text()
            self.assertEqual(sql.count("AS orphan_count"), 107)
            statement = next(s for s in sql.split("UNION ALL") if "store_returns.sr_i_tn" in s)
            self.assertIn("c.`sr_item_sk`=p.`ss_item_sk` AND c.`sr_ticket_number`=p.`ss_ticket_number`", statement)
            self.assertIn("c.`sr_item_sk` IS NOT NULL AND c.`sr_ticket_number` IS NOT NULL", statement)
            self.assertNotIn("ALTER TABLE", sql)


if __name__ == "__main__":
    unittest.main()
