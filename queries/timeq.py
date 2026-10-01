#!/usr/bin/env python3
"""Time one SQL file against tpcds and save its output.
   usage: timeq.py <file.sql> <out-file> <label>"""
import subprocess, sys, time
PRE = ("SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE'); "
       "SET STATEMENT max_statement_time=1800 FOR ")
sql = open(sys.argv[1]).read().strip().rstrip(';')
t = time.time()
r = subprocess.run(['mariadb','-B','tpcds','-e',PRE+sql],
                   capture_output=True, text=True, timeout=2000)
el = time.time() - t
open(sys.argv[2],'w').write(r.stdout)
err = [l for l in r.stderr.splitlines() if 'ERROR' in l]
rows = max(0, len(r.stdout.strip().splitlines()) - 1)
print(f"  {sys.argv[3]:<26} {el:7.1f}s  rows={rows}  {err[0][:60] if err else ''}")
