"""Q24/Q34/Q36/Q45 SF4 study. Index DDL only outside measured batches."""
import datetime, hashlib, json, os, pathlib, re, shutil, signal, statistics, subprocess, sys, time
IDS=[24,34,36,45]
STAMP='next4-sf4-20261029'
def dump(p,v):p.write_text(json.dumps(v,indent=2),encoding='utf-8')
def clean(s):return re.sub(r'/\*(?![+!]).*?\*/|--[^\n]*','',s,flags=re.S).strip()
def split(s):
    s=clean(s);parts=[];start=0;quote=None;i=0
    while i<len(s):
        c=s[i]
        if quote:
            if c=='\\':i+=2;continue
            if c==quote:
                if i+1<len(s) and s[i+1]==quote:i+=2;continue
                quote=None
        elif c in "'\"`":quote=c
        elif c==';':
            if s[start:i].strip():parts.append(s[start:i].strip())
            start=i+1
        i+=1
    if s[start:].strip():parts.append(s[start:].strip())
    return parts
if sys.argv[1]=='prepare':
    root=pathlib.Path(__file__).resolve().parents[2];p=root/'windows/docker/next4-input';p.mkdir(exist_ok=True)
    for q in IDS:
        d=p/f'q{q}';d.mkdir(exist_ok=True)
        shutil.copyfile(root/f'queries/mariadb/query{q}.sql',d/'original.sql')
        old=root/f'queries/optimized/Nafiz/tier3/q{q}'
        for f in old.glob('*.sql'):shutil.copyfile(f,d/('sf1-'+f.name))
        if (old/'README.md').exists():shutil.copyfile(old/'README.md',d/'sf1-README.md')
    print('Prepared four untouched originals and historical SF1 alternatives.');sys.exit()

stage=pathlib.Path('/setup/next4-input');out=pathlib.Path('/results')/STAMP;out.mkdir(exist_ok=True)
CLI=['mariadb','--socket=/data/mysql.sock','-uroot','-N','-B','--raw','tpcds']
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');SET SESSION max_statement_time=180;\n"
def sql(s,timeout=240):
    r=subprocess.run(CLI,input=(PRE+s).encode(),capture_output=True,timeout=timeout)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace'))
    return r.stdout
def statdump():return sql("SELECT table_name,index_name,stat_name,stat_value,sample_size FROM mysql.innodb_index_stats WHERE database_name='tpcds' ORDER BY table_name,index_name,stat_name")
def verify():
    from reference_indexes import verify_indexes
    assert verify_indexes()==95
    assert sql('SELECT @@innodb_buffer_pool_size,@@innodb_page_size,@@innodb_stats_persistent_sample_pages').strip()==b'8589934592\t32768\t160'
    assert pathlib.Path('/data/tpcds-data/.scale').read_text().strip()=='4:10'
def plan(dest,label,s,actual=False):
    for i,part in enumerate(split(s),1):
        prefix='ANALYZE FORMAT=JSON ' if actual else 'EXPLAIN FORMAT=JSON '
        if part.upper().startswith('SET STATEMENT '):
            head,body=re.split(r'\s+FOR\s+',part,maxsplit=1,flags=re.I);statement=head+' FOR '+prefix+body
        else:statement=prefix+part
        (dest/f'{label}-part{i}.{ "analyze" if actual else "explain"}.json').write_bytes(sql(statement))
def measure(dest,label,s,warm=False,roundno=0):
    print(f'Q{dest.name[1:]} {label}: '+('warm-up' if warm else f'round {roundno}'),flush=True)
    t=time.perf_counter()
    try:b=sql(s)
    except Exception as e:
        failures=json.loads((dest/'failures.json').read_text()) if (dest/'failures.json').exists() else []
        failures.append({'label':label,'warmup':warm,'round':roundno,'elapsed_seconds':time.perf_counter()-t,'error':str(e),'sql_sha256':hashlib.sha256(s.encode()).hexdigest()})
        dump(dest/'failures.json',failures);raise
    secs=time.perf_counter()-t
    expected=(dest/'original.out').read_bytes()
    if b!=expected:
        (dest/(label+'.mismatch.out')).write_bytes(b)
        raise AssertionError(f'{dest.name} {label} output differs')
    (dest/(label+'.out')).write_bytes(b)
    runs=json.loads((dest/'runs.json').read_text()) if (dest/'runs.json').exists() else []
    runs.append({'label':label,'warmup':warm,'round':roundno,'seconds':secs,'sql_sha256':hashlib.sha256(s.encode()).hexdigest(),'output_sha256':hashlib.sha256(b).hexdigest(),'exact_match':True})
    dump(dest/'runs.json',runs);print(f'  {secs:.6f}s, {len(b.splitlines())} rows, exact match',flush=True)
    return secs

mode=sys.argv[1]
if mode=='diagnose':
    d=out/f'q{int(sys.argv[2])}';s=statdump();(d/'partial-statistics-after.tsv').write_bytes(s)
    print('Persistent statistics unchanged:',s==(d/'statistics-before.tsv').read_bytes())
    print(sql("SELECT id,time,LEFT(info,150) FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").decode());sys.exit()
if mode=='stop':
    q=sys.argv[2];found=[]
    for p in pathlib.Path('/proc').iterdir():
        if not p.name.isdigit():continue
        try:cmd=(p/'cmdline').read_bytes().decode().split('\0')
        except (OSError,UnicodeError):continue
        if len(cmd)>=4 and cmd[1]==__file__ and cmd[2:4]==['study',q]:os.kill(int(p.name),signal.SIGTERM);found.append(int(p.name))
    print('Stopped only owned study workers:',found);sys.exit()
if mode=='cleanup':
    from reference_indexes import actual_indexes,expected_indexes
    q=int(sys.argv[2]);definitions=json.loads((stage/f'q{q}/indexes.json').read_text())
    actual,ignored=actual_indexes();expected=expected_indexes();owned={(i['table'],i['name']) for i in definitions}
    assert not ignored and set(actual)-set(expected)<=owned
    assert all(actual[k]==expected[k] for k in expected)
    for t,n in sorted(set(actual)-set(expected)):sql(f'DROP INDEX {n} ON {t}',600)
    verify();print('Removed only owned experiment indexes; shared95 verified.');sys.exit()
if mode=='all':
    with (out/'study.log').open('a') as log:
        first=int(sys.argv[2]) if len(sys.argv)>2 else IDS[0]
        for q in IDS[IDS.index(first):]:
            p=subprocess.Popen([sys.executable,__file__,'study',str(q)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            for line in p.stdout:print(line,end='',flush=True);log.write(line);log.flush()
            if p.wait():raise RuntimeError(f'Study stopped at Q{q}')
    sys.exit()
if mode=='study':
    q=int(sys.argv[2]);assert q in IDS;verify();d=out/f'q{q}';inp=stage/f'q{q}'
    definitions=json.loads((inp/'indexes.json').read_text());choices=json.loads((inp/'candidates.json').read_text())
    (d/'index-build-before.tsv').write_bytes(statdump());costs=[]
    for ix in definitions:
        t=time.perf_counter();print(f"Q{q}: build {ix['name']} ({ix['columns']}) once, outside timing",flush=True)
        sql(f"SET SESSION max_statement_time=1800;CREATE INDEX {ix['name']} ON {ix['table']} ({ix['columns']})",1900)
        costs.append(dict(ix,build_seconds=time.perf_counter()-t))
    dump(d/'index-costs.json',costs)
    before=statdump();(d/'statistics-before.tsv').write_bytes(before)
    def ignore_indexes(s,excluded):
        for table in sorted({i['table'] for i in excluded},key=len,reverse=True):
            names=[i['name'] for i in excluded if i['table']==table]
            pattern=r'\b'+table+r'\b(?!\s*\.)(?:\s+(?:AS\s+)?([A-Za-z_]\w*))?'
            stop={'where','join','inner','left','right','cross','straight_join','on','force','use','ignore','group','order','having','union','limit','with'}
            def sub(m):
                alias=m.group(1);hint=' IGNORE INDEX ('+','.join(names)+')'
                return m.group(0)+hint if alias and alias.lower() not in stop else table+hint+m.group(0)[len(table):]
            s=re.sub(pattern,sub,s,flags=re.I)
        return s
    rejected=[];valid=[]
    for c in choices:
        c['executed_sql']=ignore_indexes(c['sql'],[i for i in definitions if i['name'] not in c['indexes']])
        (d/(c['label']+'.sql')).write_text(c['executed_sql'])
        print(f"Q{q}: test {c['label']} — {c['method']}. {c['reason']}",flush=True)
        try:
            plan(d,c['label'],c['executed_sql'])
            measure(d,c['label'],c['executed_sql'],True)
            if q==24:
                assert len(split(c['executed_sql']))==2
                for n,part in enumerate(split(c['executed_sql']),1):
                    actual=sql(part);assert actual==(d/f'original-part{n}.out').read_bytes(),f'Part {n} differs'
                    (d/f"{c['label']}-part{n}.out").write_bytes(actual)
            valid.append(c)
        except Exception as e:
            rejected.append({'label':c['label'],'reason':str(e),'stage':'screening correctness/plan'})
            print(f"Rejected {c['label']}: {e}",flush=True)
    dump(d/'rejected.json',rejected)
    assert any(c['label']=='original' for c in valid)
    for roundno in range(1,4):
        for c in (valid if roundno%2 else list(reversed(valid))):measure(d,c['label'],c['executed_sql'],False,roundno)
    trials=json.loads((d/'runs.json').read_text())
    def med(c):return statistics.median(r['seconds'] for r in trials if r['label']==c['label'] and not r['warmup'])
    baseline=next(c for c in valid if c['label']=='original');bs=med(baseline)
    selected=[baseline]+[c for c in valid if c['label']!='original' and med(c)<bs*.97]
    for c in valid:
        if c not in selected:rejected.append({'label':c['label'],'reason':'Less than 3% exploratory improvement, or slower','stage':'screening speed'})
    fastest=min(selected,key=med)
    control=dict(label='control_original_best_indexes',method='Original with provisional BEST indexes',reason='Separate SQL rewriting from index availability',sql=baseline['sql'],indexes=fastest['indexes'])
    control['executed_sql']=ignore_indexes(control['sql'],[i for i in definitions if i['name'] not in control['indexes']])
    selected.append(control)
    for c in selected:
        (d/('final_'+c['label']+'.sql')).write_text(c['executed_sql'])
        plan(d,'final_'+c['label'],c['executed_sql'])
        measure(d,'final_'+c['label'],c['executed_sql'],True)
    for n in range(1,8):
        for c in (selected if n%2 else list(reversed(selected))):measure(d,'final_'+c['label'],c['executed_sql'],False,n)
    plan(d,'provisional_best_actual',fastest['executed_sql'],True)
    after=statdump();(d/'statistics-after.tsv').write_bytes(after);assert before==after,'Persistent statistics changed during study'
    dump(d/'final-candidates.json',selected);dump(d/'rejected.json',rejected)
    dump(d/'candidate-catalog.json',choices)
    dump(d/'validation.json',{'all_timed_outputs_exact':True,'persistent_statistics_unchanged':True,'q24_both_parts_verified':q==24,'final_repetitions':7,'exploratory_repetitions':3,'metadata_unchanged_during_measurements':True})
    for ix in definitions:sql(f"DROP INDEX {ix['name']} ON {ix['table']}",600)
    verify();print(f'Q{q}: study complete, shared95 restored.',flush=True)
if mode=='inspect':
    verify();assert not sql("SELECT id FROM information_schema.processlist WHERE id<>CONNECTION_ID() AND command<>'Sleep'").strip()
    dump(out/'metadata.json',{'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'settings':sql('SHOW VARIABLES').decode(),'recipe':json.loads(pathlib.Path('/data/reference-recipe.json').read_text())})
    for q in IDS:
        d=out/f'q{q}';d.mkdir(exist_ok=False);s=(stage/f'q{q}/original.sql').read_text();(d/'original.sql').write_text(s)
        plan(d,'original',s)
        (d/'original.out').write_bytes(sql(s))
        for i,part in enumerate(split(s),1):(d/f'original-part{i}.out').write_bytes(sql(part))
        measure(d,'inspect_original',s,True);measure(d,'inspect_original',s,False,1)
        plan(d,'original',s,True)
    diagnostics={
      'q24':"SELECT COUNT(*),COUNT(DISTINCT s_zip) FROM store WHERE s_market_id=10; SELECT s_store_sk,s_zip,(SELECT COUNT(*) FROM customer_address WHERE ca_zip=s_zip) addresses FROM store WHERE s_market_id=10; SELECT i_color,COUNT(*) FROM item WHERE i_color IN ('sky','slate') GROUP BY i_color",
      'q34':"SELECT s_store_sk,s_county FROM store WHERE s_county='Williamson County'; SELECT COUNT(*) FROM household_demographics WHERE hd_buy_potential IN ('>10000','Unknown') AND hd_vehicle_count>0 AND (CASE WHEN hd_vehicle_count>0 THEN hd_dep_count/hd_vehicle_count END)>1.2; SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year IN(1998,1999,2000)",
      'q36':"SELECT s_store_sk FROM store WHERE s_state='TN'; SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year=2001",
      'q45':"SELECT MIN(d_date_sk),MAX(d_date_sk),COUNT(*) FROM date_dim WHERE d_year=2001 AND d_qoy=1;SELECT i_item_sk,i_item_id FROM item WHERE i_item_sk IN(2,3,5,7,11,13,17,19,23,29)"}
    for k,v in diagnostics.items():(out/f'{k}-diagnostics.tsv').write_bytes(sql(v))
    print('All original plans, actual execution diagnostics and outputs saved.',flush=True)
