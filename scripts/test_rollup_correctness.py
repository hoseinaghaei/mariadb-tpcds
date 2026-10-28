"""Independent GROUPING-level oracle and optional SELECT-only MariaDB fixtures.

Live checks: TPCDS_LIVE_TESTS=1 python3 -B scripts/test_rollup_correctness.py -v
No tables, indexes or other database objects are created.
"""
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'docker'))
from result_sets import parse_results
from query_trial import split_statements


def fixture(scenario='normal'):
    dates = [(2451911, 2001, 1212), (2450815, 1998, 1176), (2451000, 1999, 1188)]
    items = [(1, 'A', 'x'), (2, 'A', None), (3, None, 'z'), (4, None, None),
             (5, 'B', 'k'), (6, 'A', 'x'), (7, 'C', 'zero'), (8, 'D', 'nil')]
    stores = [(1, 'TN', 'X'), (2, 'TN', None), (3, None, 'Y'),
              (4, 'CA', 'X'), (5, 'TN', 'X')]
    sales = []
    for date in (2451911, 2450815):
        sales += [(date, i, s, p, v) for i, s, p, v in [
            (1, 1, '10', '100'), (2, 2, '20', '100'), (3, 1, '30', '100'),
            (4, 2, '40', '100'), (5, 4, '-5', '100'), (6, 5, '10', '100'),
            (7, 1, '1', '0'), (8, 1, None, None), (1, 3, '999', '100'),
            (99, 1, '7', '100'), (None, 1, '3', '100'), (1, 99, '1000', '100'),
            (1, 1, '10', '100')]]  # duplicate fact must contribute again
    sales += [(None, 1, 1, '1000', '100'), (2451000, 1, 1, '888', '100')]
    web = [(2450815, i, v) for i, v in [(1, '10'), (2, '20'), (3, '30'),
           (4, '40'), (5, '-5'), (6, '10'), (7, None), (8, '0'),
           (99, '999'), (None, '999')]] + [(2451000, 1, '888')]
    if scenario == 'empty':
        sales, web = [], []
    elif scenario == 'all-null':
        sales = [(d, i, s, None, None) for d, i, s, _, _ in sales]
        web = [(d, i, None) for d, i, _ in web]
    return dates, items, stores, sales, web


def sql_fixture(scenario):
    dates, items, stores, sales, web = fixture(scenario)
    tables = [
        ('date_dim', ['d_date_sk', 'd_year', 'd_month_seq'], ['SIGNED'] * 3, dates),
        ('item', ['i_item_sk', 'i_category', 'i_class'], ['SIGNED', 'CHAR(50)', 'CHAR(50)'], items),
        ('store', ['s_store_sk', 's_state', 's_county'], ['SIGNED', 'CHAR(2)', 'CHAR(50)'], stores),
        ('store_sales', ['ss_sold_date_sk', 'ss_item_sk', 'ss_store_sk', 'ss_net_profit', 'ss_ext_sales_price'],
         ['SIGNED'] * 3 + ['DECIMAL(7,2)'] * 2, sales),
        ('web_sales', ['ws_sold_date_sk', 'ws_item_sk', 'ws_net_paid'],
         ['SIGNED', 'SIGNED', 'DECIMAL(7,2)'], web)]

    def literal(value):
        return 'NULL' if value is None else "'" + str(value).replace("'", "''") + "'"

    ctes = []
    for name, columns, types, rows in tables:
        selects = ['SELECT ' + ', '.join(f'CAST({literal(v)} AS {t}) AS {c}'
                   for v, t, c in zip(row, types, columns)) for row in rows]
        if not selects:
            selects = ['SELECT ' + ', '.join(f'CAST(NULL AS {t}) AS {c}'
                       for t, c in zip(types, columns)) + ' WHERE FALSE']
        ctes.append(name + ' AS (\n' + '\nUNION ALL\n'.join(selects) + '\n)')
    return 'WITH ' + ',\n'.join(ctes) + ',\n'


def oracle(query, scenario):
    """Compute grouping sets/ranks independently of the SQL implementations."""
    dates, items, stores, sales, web = fixture(scenario)
    dates = {d: (y, m) for d, y, m in dates}
    items = {i: (category, klass) for i, category, klass in items}
    stores = {s: (state, county) for s, state, county in stores}
    observations = []
    dec = lambda v: None if v is None else Decimal(v)
    if query == 86:
        for d, i, value in web:
            if d in dates and 1176 <= dates[d][1] <= 1187 and i in items:
                observations.append((*items[i], dec(value), None))
    else:
        for d, i, s, profit, price in sales:
            if d not in dates or s not in stores:
                continue
            if query == 36 and dates[d][0] == 2001 and stores[s][0] == 'TN' and i in items:
                observations.append((*items[i], dec(profit), dec(price)))
            if query == 70 and 1176 <= dates[d][1] <= 1187 and stores[s][0] is not None:
                observations.append((*stores[s], dec(profit), None))
    groups = defaultdict(list)
    for a, b, value, denominator in observations:
        for level, first, second in [(0, a, b), (1, a, None), (2, None, None)]:
            groups[(level, first, second)].append((value, denominator))
    output = []
    for (level, a, b), values in groups.items():
        numbers = [v for v, _ in values if v is not None]
        measure = sum(numbers) if numbers else None
        if query == 36:
            denominators = [v for _, v in values if v is not None]
            denominator = sum(denominators) if denominators else None
            measure = (measure / denominator).quantize(Decimal('.000001'), rounding=ROUND_HALF_UP) \
                if measure is not None and denominator else None
        output.append([measure, a, b, level])

    def metric_key(value):
        if query == 36:  # ascending, NULL first
            return (0, Decimal(0)) if value is None else (1, value)
        return (1, Decimal(0)) if value is None else (0, -value)

    partitions = defaultdict(list)
    for row in output:
        partitions[(row[3], row[1] if row[3] == 0 else None)].append(row)
    for rows in partitions.values():
        rows.sort(key=lambda row: metric_key(row[0]))
        previous, rank = None, 0
        for pos, row in enumerate(rows, 1):
            key = metric_key(row[0])
            if key != previous:
                rank = pos
            previous = key
            row.append(rank)
    return output


class OracleSanity(unittest.TestCase):
    def test_null_leaf_subtotal_and_total_remain_distinct(self):
        rows = oracle(86, 'normal')
        for value, level in [(Decimal(40), 0), (Decimal(70), 1), (Decimal(105), 2)]:
            self.assertTrue(any(r[:4] == [value, None, None, level] for r in rows))

    def test_empty_input_has_no_grand_total_but_null_measures_do(self):
        for query in (36, 70, 86):
            self.assertEqual(oracle(query, 'empty'), [])
            rows = oracle(query, 'all-null')
            self.assertTrue(rows)
            self.assertTrue(all(r[0] is None for r in rows))


@unittest.skipUnless(os.environ.get('TPCDS_LIVE_TESTS') == '1', 'explicit live MariaDB opt-in required')
class LiveRollup(unittest.TestCase):
    def test_actual_queries_against_independent_grouping_oracle(self):
        files = [(36, 'queries/mariadb/query36.sql'), (70, 'queries/mariadb/query70.sql'),
                 (86, 'queries/mariadb/query86.sql'), (70, 'queries/tuned/query70.sql')]
        for scenario in ('normal', 'empty', 'all-null'):
            for query, filename in files:
                with self.subTest(query=query, file=filename, scenario=scenario):
                    source = (REPO / filename).read_text()
                    start = re.search(r'(?im)^with\s', source).end()
                    sql = ('SET SESSION max_statement_time=10; SET SESSION div_precision_increment=4;\n'
                           + sql_fixture(scenario) + source[start:])
                    command = ['mariadb', '--connect-timeout=5', '--skip-reconnect', '--xml']
                    if os.environ.get('TPCDS_TEST_SOCKET'):
                        command.append('--socket=' + os.environ['TPCDS_TEST_SOCKET'])
                    p = subprocess.run(command, input=sql.encode(), capture_output=True, timeout=20)
                    self.assertEqual(p.returncode, 0, p.stderr.decode(errors='replace'))
                    sets = parse_results(p.stdout)
                    self.assertEqual(len(sets), 1)
                    rows = [[None if r[0] is None else Decimal(r[0]), r[1], r[2], int(r[3]), int(r[4])]
                            for r in sets[0]['rows']]
                    expected = oracle(query, scenario)
                    self.assertLess(len(expected), 100)  # no LIMIT-boundary ambiguity in this fixture
                    self.assertCountEqual(rows, expected)
                    # ORDER BY is not total; validate its keys while permitting ties.
                    keys = [(-r[3], (r[1] is not None, r[1] or '') if r[3] == 0 else (False, ''), r[4])
                            for r in rows]
                    self.assertEqual(keys, sorted(keys))
                    if rows:
                        self.assertEqual(sets[0]['columns'],
                                         ['gross_margin' if query == 36 else 'total_sum',
                                          's_state' if query == 70 else 'i_category',
                                          's_county' if query == 70 else 'i_class',
                                          'lochierarchy', 'rank_within_parent'])


@unittest.skipUnless(os.environ.get('TPCDS_LIVE_EXPLAIN') == '1', 'explicit EXPLAIN opt-in required')
class LiveCoverage(unittest.TestCase):
    def check_files(self, directory, count):
        database = os.environ.get('TPCDS_TEST_DATABASE', '')
        self.assertRegex(database, r'^tpcds(?:_[A-Za-z0-9_]+)?$')
        files = sorted((REPO / directory).glob('query*.sql'))
        self.assertEqual(len(files), count)
        for path in files:
            with self.subTest(sql=str(path.relative_to(REPO))):
                diagnostic = ["SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');",
                              "SET SESSION max_statement_time=5;"]
                expected_plans = 0
                for statement in split_statements(path.read_text(encoding='utf-8-sig')):
                    body = statement.lstrip()
                    while body.startswith(('--', '#', '/*')):
                        if body.startswith('/*'):
                            body = body[body.index('*/') + 2:].lstrip()
                        else:
                            body = body.partition('\n')[2].lstrip()
                    if re.match(r'SET\s+SESSION\b', body, re.I):
                        diagnostic.append(statement)
                    elif re.match(r'SELECT\s+MIN\(d_date_sk\),\s*MAX\(d_date_sk\)\s+INTO\s+@lo,\s*@hi', body, re.I):
                        # Q67's date-bound initialization: bounded SELECT into
                        # session variables, never persistent data.
                        diagnostic.append(statement)
                    else:
                        self.assertRegex(body.upper(), r'^(SELECT|WITH)\b')
                        diagnostic.append('EXPLAIN FORMAT=JSON ' + statement)
                        expected_plans += 1
                command = ['mariadb', '--connect-timeout=5', '--skip-reconnect', '--comments', '--xml']
                if os.environ.get('TPCDS_TEST_SOCKET'):
                    command.append('--socket=' + os.environ['TPCDS_TEST_SOCKET'])
                p = subprocess.run(command + [database], input='\n'.join(diagnostic).encode(),
                                   capture_output=True, timeout=20)
                self.assertEqual(p.returncode, 0, p.stderr.decode(errors='replace'))
                self.assertEqual(len(parse_results(p.stdout)), expected_plans)

    def test_99_adapted_files_parse_on_existing_database(self):
        self.check_files('queries/mariadb', 99)

    def test_40_adopted_files_parse_on_reference_database(self):
        # Some adopted files FORCE an index from sql/11 or sql/14. This
        # deliberately fails if that physical dependency is missing.
        self.check_files('queries/tuned', 40)


if __name__ == '__main__':
    unittest.main()
