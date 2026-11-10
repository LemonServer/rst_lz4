import os,sys,json,time,signal,fcntl,traceback,subprocess,datetime
from pathlib import Path
from zoneinfo import ZoneInfo
signal.signal(signal.SIGHUP,signal.SIG_IGN)
base=Path(os.environ['RST_ARTIFACT_ROOT']);root=Path(os.environ['RST_HW_ROOT'])
os.chdir(base);out=root/'build/full88';folder=base/'reproduction/rtl88'
lock=(out/'coordinator.lock').open('a')
try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:
 print('ANOTHER_FULL_COORDINATOR_IS_RUNNING',flush=True);raise SystemExit(2)
status_path=folder/'job-status.json';started=time.time()
def now():return datetime.datetime.now(ZoneInfo('Asia/Shanghai')).isoformat()
state={'phase':'starting','wrapper_pid':os.getpid(),'resume_started_epoch':started,'resume_started_at_shanghai':now(),'contract':'all-pages-v2','selected_pages':435461,'datasets':88,'latency_pages':'ALL','log_file':os.environ['RTL_DURABLE_LOG']}
def save():
 state['updated_at_shanghai']=now()
 tmp=status_path.with_suffix('.json.tmp');tmp.write_text(json.dumps(state,indent=2));tmp.replace(status_path)
def snapshot():
 qualified=[]
 for p in (out/'results').glob('*.json'):
  try:r=json.loads(p.read_text())
  except (OSError,json.JSONDecodeError):continue
  n=r.get('input_accounting',{}).get('selected_pages')
  if r.get('status')=='PASS' and r.get('coverage_contract')=='all-pages-v2' and r.get('decompressor_latency',{}).get('page_count')==n and r.get('decompressor_decode',{}).get('page_count')==n:qualified.append(r)
 state.update(full_datasets_completed=len(qualified),full_pages_completed=sum(x['input_accounting']['selected_pages'] for x in qualified),roundtrip_logs=len(list((out/'logs').glob('*.log'))),decode_checkpoints=len(list((out/'results').glob('*.run_sv_decompressor_check.isolated_v1.checkpoint'))),full_latency_checkpoints=len(list((out/'results').glob('*._run_direct_latency_measurement.all_pages_v2.checkpoint'))))
 state['new_errors']=[p.name for p in (out/'results').glob('*.error.txt') if p.stat().st_mtime>=started]
 save()
try:
 meta_path=folder/'run-metadata.json'
 meta=json.loads(meta_path.read_text()) if meta_path.exists() else {'started_at_epoch':started,'started_at_shanghai':now()}
 meta.setdefault('recovery_events',[]).append({'resumed_at_epoch':started,'resumed_at_shanghai':now(),'reason':'Resume after verified process termination; enforce full-page latency coverage'})
 meta_path.write_text(json.dumps(meta,indent=2))
 child=subprocess.Popen([sys.executable,'-u','reproduction/rtl88/run_full.py'],stdin=subprocess.DEVNULL)
 state.update(phase='running',child_pid=child.pid);snapshot()
 print('DURABLE_STARTED',json.dumps(state),flush=True)
 while True:
  try:code=child.wait(timeout=600);break
  except subprocess.TimeoutExpired:snapshot();print('DURABLE_PROGRESS',json.dumps(state),flush=True)
 snapshot()
 if code!=0:raise RuntimeError('RTL driver exited with '+str(code))
 summary=json.loads((out/'full-summary.json').read_text())
 if summary.get('status')!='PASS' or len(summary.get('results',[]))!=88:raise RuntimeError('Full verification is incomplete')
 state['phase']='auditing';save()
 subprocess.run([sys.executable,'reproduction/rtl88/acceptance_audit.py'],check=True)
 state['phase']='packaging';save()
 subprocess.run([sys.executable,'reproduction/rtl88/compare_and_pack.py'],check=True)
 archive=folder/'rtl88-results.tar.gz'
 state.update(phase='complete_server',archive=str(archive),archive_bytes=archive.stat().st_size,finished_at_shanghai=now(),resume_elapsed_seconds=time.time()-started)
 save();print('DURABLE_COMPLETE',json.dumps(state),flush=True)
except BaseException:
 state.update(phase='failed',failure=traceback.format_exc(),finished_at_shanghai=now())
 save();print(state['failure'],flush=True);raise

