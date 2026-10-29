"""Exact index definitions from the team's default Docker setup."""
import pathlib
import re
import subprocess
import json

SOURCES = ('all_indexes.sql',)

def expected_indexes():
    manifest = pathlib.Path('/data/reference-recipe.json')
    if not manifest.exists():
        manifest = pathlib.Path('/results/reference-recipe.json')
    if manifest.exists():
        rows = json.loads(manifest.read_text())['indexes']
        return {(r['table'], r['name']): (1, tuple(c.strip().strip('`') for c in r['columns'].split(','))) for r in rows}
    expected = {}
    for name in SOURCES:
        text = pathlib.Path('/project/sql', name).read_text()
        text = re.sub(r'--[^\n]*', '', text)
        matches = re.findall(r'CREATE\s+(UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s+ON\s+(\w+)\s*\(([^;]+)\)\s*;', text, re.I)
        assert len(matches) == len(re.findall(r'CREATE\s+(?:UNIQUE\s+)?INDEX', text, re.I)), name
        for unique, index, table, columns in matches:
            definition = (0 if unique else 1, tuple(c.strip().strip('`') for c in columns.split(',')))
            key = (table, index)
            assert key not in expected or expected[key] == definition, key
            expected[key] = definition
    return expected

def sql(statement):
    return subprocess.run(['mariadb', '--socket=/data/mysql.sock', '-uroot', '-N', '-B', 'tpcds', '-e', statement], check=True, capture_output=True, text=True).stdout.strip()

def actual_indexes():
    rows = sql("SELECT table_name,index_name,non_unique,column_name,sub_part,collation,ignored FROM information_schema.statistics WHERE table_schema='tpcds' AND index_name<>'PRIMARY' ORDER BY table_name,index_name,seq_in_index")
    actual, ignored = {}, set()
    for row in rows.splitlines():
        table, index, non_unique, column, prefix, order, hidden = row.split('\t')
        assert prefix == 'NULL' and order == 'A', row
        key = (table, index)
        actual.setdefault(key, (int(non_unique), []))[1].append(column)
        if hidden == 'YES':
            ignored.add(key)
    return {k: (v[0], tuple(v[1])) for k, v in actual.items()}, ignored

def verify_indexes():
    expected = expected_indexes()
    actual, ignored = actual_indexes()
    assert actual == expected, f'Index mismatch: missing={set(expected)-set(actual)}, extra={set(actual)-set(expected)}, changed={[k for k in actual.keys() & expected.keys() if actual[k] != expected[k]]}'
    assert not ignored, f'Ignored indexes: {ignored}'
    return len(actual)
