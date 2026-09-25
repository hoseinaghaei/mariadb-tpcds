"""Shared TPC-DS .ans parser.

Three shapes must be handled; getting this wrong silently inflates the
expected row count and makes correct queries look like mismatches:
  * pipe-delimited, single header line
  * fixed-width with a header plus a line of dashes -- and BOTH the header and
    the dash line may WRAP over several physical lines on wide rows
    (25 of the 129 shipped files do this)
  * a trailing "N rows selected." footer (44 of 129 files)
"""
import re

NUM = re.compile(r'^-?\d+(\.\d+)?$')
# Footers seen across the 129 shipped files:
#   "100 rows selected."   (Oracle style)
#   "(100 rows)"           (PostgreSQL style)
FOOTER = re.compile(r'^\s*(?:\d+\s+rows?\s+selected|\(\s*\d+\s+rows?\s*\))', re.I)

def norm(c):
    c = c.strip()
    if c in ('NULL', '', 'None'):
        return ''
    return f"{round(float(c), 2):.2f}" if NUM.match(c) else c

def parse_ans(path):
    ls = [l.rstrip('\n') for l in open(path, encoding='latin-1') if l.strip()]
    for k, l in enumerate(ls):
        if FOOTER.match(l):
            ls = ls[:k]
            break
    if not ls:
        return []
    if '|' in ls[0]:
        return [[norm(c) for c in l.split('|')] for l in ls[1:]]
    last_dash = -1
    for k, l in enumerate(ls[:12]):
        if set(l.strip()) <= set('- ') and l.strip():
            last_dash = k
    body = ls[last_dash + 1:] if last_dash >= 0 else ls[1:]
    return [[norm(c) for c in l.split()] for l in body]

def parse_out(text):
    ls = [l for l in text.split('\n') if l.strip()]
    return [[norm(c) for c in l.split('\t')] for l in ls[1:]]
