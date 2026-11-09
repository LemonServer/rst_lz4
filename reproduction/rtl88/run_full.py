import sys,os,json,time,traceback,pickle,fcntl,signal
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor,wait,FIRST_COMPLETED
signal.signal(signal.SIGHUP,signal.SIG_IGN)
root=Path(os.environ['RST_HW_ROOT']);sys.path.insert(0,str(root/'tools'))
import run_rst_verify as v
import run_m4_experimental_regression as runtime
sys.argv=['run_rst_verify.py','--pages','5000','--latency-pages','0','--jobs','1','--build-jobs','2','--verilator-bin',os.environ['RST_VERILATOR_BIN'],'--roundtrip-build-dir','build/native/roundtrip','--decompressor-build-dir','build/native/decompressor','--latency-build-dir','build/native/latency','--cpp-build-dir','build/native/cpp','--log-dir','build/full88/logs']
args=v.parse_args();assert args.pages==5000 and args.latency_pages==0 and not args.skip_decompressor_check and not args.skip_latency_measurement
artifacts=None;out=root/'build/full88';(out/'results').mkdir(parents=True,exist_ok=True)
CONTRACT='all-pages-v2'
runtime_original=runtime.run_runtime_harness
originals={n:getattr(v,n) for n in ['run_hardware_roundtrip','run_sv_decompressor_check','_run_direct_latency_measurement']}
def expected_pages(p):return min(5000,(p.stat().st_size+4095)//4096)
def path_is(value,path):
 try:return v.resolve_repo_path(root,Path(value))==path.resolve()
 except (TypeError,ValueError):return False
def stage_ok(stage,value,n,p):
 if not isinstance(value,dict) or value.get('status')!='PASS':return False
 if stage=='run_hardware_roundtrip':
  return value.get('pages_observed')==n and value.get('hardware_summary',{}).get('pages')==n and len(value.get('hardware_pages',[]))==n
 if stage=='run_sv_decompressor_check':
  pages=value.get('pages',[])
  return value.get('page_count')==n and len(pages)==n and [x['page_idx'] for x in pages]==list(range(n)) and all('[sv-decompressor] PASS' in x.get('sv_stdout','') for x in pages) and path_is(value.get('build_dir'),out/'decode_cases'/p.stem)
 summary=value.get('summary',{})
 return value.get('page_count')==n and summary.get('page_count')==n and value.get('case_count')==16*n and summary.get('case_count')==16*n and path_is(value.get('build_dir'),out/'latency_all'/p.stem)
def full_result_ok(value,p,require_contract=True):
 n=expected_pages(p)
 return isinstance(value,dict) and value.get('status')=='PASS' and (not require_contract or value.get('coverage_contract')==CONTRACT) and value.get('input_accounting',{}).get('selected_pages')==n and all(stage_ok(k,value.get(field,{}),n,p) for k,field in [('run_hardware_roundtrip','hardware_roundtrip'),('run_sv_decompressor_check','decompressor_decode'),('_run_direct_latency_measurement','decompressor_latency')])
def reuse_verified_runtime_log(*a,**kw):
 log=kw['log_path']
 if log.exists():
  text=log.read_text()
  if 'tb_M4ExperimentalRuntimeFileCompressorTop passed' in text:
   _pages,summary=runtime.parse_hardware_log(text)
   if summary['pages']==kw['pages']:
    print('REUSE_VERIFIED_RTL_LOG',kw['input_file'].name,flush=True);return text
 return runtime_original(*a,**kw)
runtime.run_runtime_harness=reuse_verified_runtime_log
def atomic_json(path,value):
 tmp=path.with_suffix('.json.tmp');tmp.write_text(json.dumps(value));tmp.replace(path)
def _work_unlocked(name):
 p=Path(name);n=expected_pages(p);dest=out/'results'/(p.stem+'.json');start=time.time()
 try:
  if dest.exists():
   try:old=json.loads(dest.read_text())
   except (OSError,json.JSONDecodeError):old={}
   if full_result_ok(old,p):return {'name':p.name,'status':'PASS','cached':True}
  for stage in originals:
   suffix='.isolated_v1' if stage=='run_sv_decompressor_check' else '.all_pages_v2' if stage=='_run_direct_latency_measurement' else ''
   checkpoint=out/'results'/(p.stem+'.'+stage+suffix+'.checkpoint')
   def cached(*a,_stage=stage,_fn=originals[stage],_cp=checkpoint,**kw):
    if _cp.exists():
     try:
      value=pickle.loads(_cp.read_bytes())
      if stage_ok(_stage,value,n,p):return value
     except (OSError,pickle.UnpicklingError,EOFError):pass
    print('STAGE_START',p.name,_stage,'pages',n,flush=True)
    value=_fn(*a,**kw)
    if not stage_ok(_stage,value,n,p):raise RuntimeError('Stage coverage/isolation mismatch: '+_stage+' '+p.name)
    tmp=_cp.with_suffix('.checkpoint.tmp');tmp.write_bytes(pickle.dumps(value));tmp.replace(_cp)
    print('STAGE_DONE',p.name,_stage,'pages',n,flush=True);return value
   setattr(v,stage,cached)
  loaded=v.load_paged_input(root,p,5000);local=dict(artifacts)
  local['decompressor_build_dir']=out/'decode_cases'/p.stem
  local['latency_build_dir']=out/'latency_all'/p.stem
  r=v._verify_input(args=args,root=root,loaded_input=loaded,pages_requested=5000,artifacts=local)
  if not full_result_ok(r,p,False):raise RuntimeError('Full-page contract not satisfied: '+p.name)
  r.update(coverage_contract=CONTRACT,artifact_isolation='decode_dataset-v1',elapsed_seconds=time.time()-start)
  atomic_json(dest,r)
  return {'name':p.name,'status':'PASS','pages':n,'seconds':round(time.time()-start)}
 except Exception:
  err=traceback.format_exc();(out/'results'/(p.stem+'.error.txt')).write_text(err)
  return {'name':p.name,'status':'FAIL','error':err}
def work(name):
 locks=out/'locks';locks.mkdir(exist_ok=True)
 with (locks/(Path(name).stem+'.lock')).open('a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX);return _work_unlocked(name)
if __name__=='__main__':
 import multiprocessing as mp
 inputs=sorted((root/'data/full88').iterdir());assert len(inputs)==88 and sum(expected_pages(p) for p in inputs)==435461
 if os.environ.get('RTL_AUDIT_ONLY')=='1':
  accepted=[]
  for p in inputs:
   dest=out/'results'/(p.stem+'.json')
   if dest.exists() and full_result_ok(json.loads(dest.read_text()),p):accepted.append(p.name)
  print(json.dumps({'datasets':88,'pages':435461,'latency_pages_option':args.latency_pages,'accepted_full_results':accepted,'latency_checkpoint_version':CONTRACT}));raise SystemExit(0)
 artifacts=v._prepare_shared_artifacts(args,root,2)
 workers=max(1,min(88,os.cpu_count() or 1,int(os.environ.get('RTL_WORKERS','88'))))
 print('FULL_RTL_START',json.dumps({'datasets':88,'selected_pages':435461,'latency_pages':'ALL','workers':workers,'contract':CONTRACT}),flush=True)
 start=time.time();completed=[]
 with ProcessPoolExecutor(max_workers=workers,mp_context=mp.get_context('fork')) as ex:
  pending={ex.submit(work,str(p)):p for p in inputs}
  while pending:
   done,_=wait(pending,timeout=60,return_when=FIRST_COMPLETED)
   for f in done:
    p=pending.pop(f)
    try:r=f.result()
    except Exception:r={'name':p.name,'status':'FAIL','error':traceback.format_exc()}
    completed.append(r);print('COMPLETED',len(completed),'/88',json.dumps(r),flush=True)
   print('HEARTBEAT',round(time.time()-start),'seconds; completed',len(completed),'active/pending',len(pending),flush=True)
 results=[]
 for p in inputs:
  dest=out/'results'/(p.stem+'.json')
  if dest.exists():
   r=json.loads(dest.read_text())
   if full_result_ok(r,p):results.append(r)
 passed=len(results)==88 and all(r['status']=='PASS' for r in completed)
 summary={'status':'PASS' if passed else 'FAIL','coverage_contract':CONTRACT,'pages_requested':5000,'latency_pages_requested':'ALL','aggregate':v._aggregate_results(results),'paper_metric_summary':v._paper_metric_summary(results) if passed else None,'results':results,'worker_outcomes':completed,'elapsed_seconds':time.time()-start}
 atomic_json(out/'full-summary.json',summary)
 if passed:v._print_suite_summary(str(root/'data/full88'),results)
 print('FINAL_STATUS',summary['status'],'full_datasets',len(results),flush=True)
 raise SystemExit(0 if passed else 1)

