import sys,os,json,time,traceback,argparse
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor,wait,FIRST_COMPLETED
root=Path(os.environ['RST_HW_ROOT']);sys.path.insert(0,str(root/'tools'))
import run_rst_verify as v
sys.argv=['run_rst_verify.py','--pages','5000','--jobs','1','--build-jobs','2','--verilator-bin',os.environ['RST_VERILATOR_BIN'],'--roundtrip-build-dir','build/native/roundtrip','--decompressor-build-dir','build/native/decompressor','--latency-build-dir','build/native/latency','--cpp-build-dir','build/native/cpp','--log-dir','build/full88/logs']
args=v.parse_args(); artifacts=None
originals={n:getattr(v,n) for n in ['run_hardware_roundtrip','run_sv_decompressor_check','_run_direct_latency_measurement']}
out=root/'build/full88';(out/'results').mkdir(parents=True,exist_ok=True)
def work(name):
 p=Path(name);dest=out/'results'/(p.stem+'.json')
 if dest.exists():
  r=json.loads(dest.read_text())
  if r.get('status')=='PASS':return {'name':p.name,'status':'PASS','cached':True}
 start=time.time()
 try:
  for fn in ['run_hardware_roundtrip','run_sv_decompressor_check','_run_direct_latency_measurement']:
   original=originals[fn]
   checkpoint=out/'results'/(p.stem+'.'+fn+'.checkpoint')
   def cached(*a,_fn=original,_cp=checkpoint,**kw):
    if _cp.exists(): return json.loads(_cp.read_text())
    print('STAGE_START',p.name,_fn.__name__,flush=True)
    value=_fn(*a,**kw)
    _cp.write_text(json.dumps(value))
    print('STAGE_DONE',p.name,_fn.__name__,flush=True)
    return value
   setattr(v,fn,cached)
  loaded=v.load_paged_input(root,p,5000)
  r=v._verify_input(args=args,root=root,loaded_input=loaded,pages_requested=5000,artifacts=artifacts)
  r['elapsed_seconds']=time.time()-start
  dest.write_text(json.dumps(r))
  return {'name':p.name,'status':r['status'],'seconds':round(time.time()-start)}
 except Exception:
  err=traceback.format_exc();(out/'results'/(p.stem+'.error.txt')).write_text(err)
  return {'name':p.name,'status':'FAIL','error':err}
if __name__=='__main__':
 import multiprocessing as mp
 artifacts=v._prepare_shared_artifacts(args,root,2)
 inputs=sorted((root/'data/full88').iterdir());assert len(inputs)==88
 print('FULL RTL: 88 datasets, 5000 requested pages each, all-page standalone decode and direct latency; 88 worker processes',flush=True)
 start=time.time();completed=[]
 with ProcessPoolExecutor(max_workers=88,mp_context=mp.get_context('fork')) as ex:
  pending={ex.submit(work,str(p)):p for p in inputs}
  while pending:
   done,_=wait(pending,timeout=45,return_when=FIRST_COMPLETED)
   for f in done:
    p=pending.pop(f);r=f.result();completed.append(r);print('COMPLETED',len(completed),'/88',json.dumps(r),flush=True)
   print('HEARTBEAT',round(time.time()-start),'seconds; completed',len(completed),'active/pending',len(pending),flush=True)
 results=[json.loads(p.read_text()) for p in sorted((out/'results').glob('*.json'))]
 summary={'status':'PASS' if len(results)==88 and all(r['status']=='PASS' for r in results) else 'FAIL','pages_requested':5000,'aggregate':v._aggregate_results(results),'paper_metric_summary':v._paper_metric_summary(results),'results':results,'elapsed_seconds':time.time()-start}
 (out/'full-summary.json').write_text(json.dumps(summary))
 v._print_suite_summary(str(root/'data/full88'),results)
 print('FINAL_STATUS',summary['status'],flush=True)
