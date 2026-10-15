"""Regression checks for diagnostic safety and exact result comparison."""
import unittest

from query_trial import results, statement_count


class DiagnosticSafety(unittest.TestCase):
    def test_semicolons_in_comments_and_literals(self):
        sql = """-- Rewrite; compare answers first.
        /* A second ; comment */ SELECT 'a;''b', "c;", `d;`; # trailing ;
        """
        self.assertEqual(statement_count(sql), 1)

    def test_second_statement_is_detected(self):
        self.assertEqual(statement_count("SELECT 'a;'; /* ; */ DELETE FROM t;"), 2)

    def test_escaped_quotes_and_trailing_delimiters(self):
        self.assertEqual(statement_count(r"SELECT 'a\';b', `a``;b`;;;"), 1)

    def test_empty_sql(self):
        self.assertEqual(statement_count("-- ;\n/* ; */ ;"), 0)

    def test_invalid_or_executable_comments_are_rejected(self):
        for sql in ["SELECT 'unfinished", "SELECT 1 /* unfinished", "/*! SELECT 1; */"]:
            with self.subTest(sql=sql), self.assertRaises(ValueError):
                statement_count(sql)


class ExactResults(unittest.TestCase):
    def test_null_empty_duplicates_and_set_boundaries(self):
        raw = b'''<?xml version="1.0"?>
        <resultset xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <row><field name="x" xsi:nil="true"/><field name="x"></field>
          <field name="y">NULL</field><field name="z">1.001</field></row>
        </resultset><?xml version="1.0"?><resultset/>'''
        parsed = results(raw)
        self.assertEqual(parsed[0], {"columns": ["x", "x", "y", "z"],
                                     "rows": [[None, "", "NULL", "1.001"]]})
        self.assertEqual(parsed[1], {"columns": [], "rows": []})


if __name__ == "__main__":
    unittest.main()
