#!/usr/bin/env python3
"""Run one adapted TPC-DS query against MariaDB, time it, compare to the TPC answer set.
   usage: run_query.py <n> [tag]"""
import subprocess, sys, os, json, re, time, glob

ROOT='/Users/hosseinaghaei/Desktop/projects/dw'
QDIR=f'{ROOT}/queries/mariadb'; ADIR=f'{ROOT}/DSGen-software-code-4.0.0/answer_sets'
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE');"
NUM=re.compile(r'^-?\d+(\.\d+)?$')

def norm(c):
    c=c.strip()
    if c in ('NULL','','None'): return ''
    return f"{round(float(c),2):.2f}" if NUM.match(c) else c

def parse_ans(p):
    ls=[l.rstrip('\n') for l in open(p,encoding='latin-1') if l.strip()]
    if not ls: return []
    if '|' in ls[0]: return [[norm(c) for c in l.split('|')] for l in ls[1:]]
    body = ls[2:] if set(ls[1].strip())<=set('- ') else ls[1:]
    return [[norm(c) for c in l.split()] for l in body]

def parse_out(t):
    ls=[l for l in t.split('\n') if l.strip()]
    return [[norm(c) for c in l.split('\t')] for l in ls[1:]]

def main():
    n=int(sys.argv[1]); tag=sys.argv[2] if len(sys.argv)>2 else 'base'
    rdir=f'{ROOT}/queries/results/{tag}'; os.makedirs(rdir,exist_ok=True)
    sts=[s.strip() for s in open(f'{QDIR}/query{n}.sql').read().split(';') if s.strip()]
    out,err,t0=[],None,time.time()
    for st in sts:
        p=subprocess.run(['mariadb','-B','--default-character-set=utf8mb4','tpcds','-e',PRE+st],
                         capture_output=True,text=True,timeout=7200)
        if p.returncode:
            e=[l for l in p.stderr.strip().splitlines() if 'ERROR' in l]
            err=(e[0] if e else p.stderr.strip())[:250]; break
        out.append(p.stdout)
    secs=round(time.time()-t0,1)
    r={'query':n,'seconds':secs,'tag':tag}
    if err: r.update(status='ERROR',detail=err)
    else:
        open(f'{rdir}/query{n}.out','w').write('\n===\n'.join(out))
        got=[x for c in out for x in parse_out(c)]; r['rows']=len(got)
        afs=[f'{ADIR}/{n}.ans'] if os.path.exists(f'{ADIR}/{n}.ans') else sorted(glob.glob(f'{ADIR}/{n}_*.ans'))
        if not afs: r['status']='NO_ANSWER_SET'
        else:
            best=None
            for af in afs:
                exp=parse_ans(af); same=exp==got
                c={'ans':os.path.basename(af),'exp_rows':len(exp),'match':same}
                if same: best=c; break
                if best is None or abs(len(exp)-len(got))<abs(best['exp_rows']-len(got)): best=c
            r.update(best)
            r['status']='MATCH' if best['match'] else ('ROWS_DIFF' if best['exp_rows']!=len(got) else 'VALUES_DIFF')
    json.dump(r,open(f'{rdir}/query{n}.json','w'),indent=1)
    print(f"query{n:<3} {r['status']:<13} {secs:>7.1f}s rows={r.get('rows','-')}/{r.get('exp_rows','-')} {r.get('detail','')}")
main()
