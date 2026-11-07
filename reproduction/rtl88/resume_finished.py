import time,json,multiprocessing as mp
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor,wait,FIRST_COMPLETED
import run_full as job
if __name__=='__main__':
 job.artifacts=job.v._prepare_shared_artifacts(job.args,job.root,2)
 inputs=sorted((job.root/'data/full88').iterdir());assert len(inputs)==88
 scheduled=set();pending={};next_scan=0
 with ProcessPoolExecutor(max_workers=88,mp_context=mp.get_context('fork')) as pool:
  while True:
   if time.time()>=next_scan:
    for p in inputs:
     err=job.out/'results'/(p.stem+'.error.txt')
     if p.name not in scheduled and err.exists() and 'Object of type bytes is not JSON serializable' in err.read_text():
      scheduled.add(p.name);pending[pool.submit(job.work,str(p))]=p.name
      print('RESUME_SCHEDULED',p.name,flush=True)
    next_scan=time.time()+600
   if len(scheduled)==88 and not pending:break
   if pending:
    done,_=wait(pending,timeout=min(60,max(1,next_scan-time.time())),return_when=FIRST_COMPLETED)
    for f in done:
     name=pending.pop(f)
     try:result=f.result()
     except Exception as e:result={'status':'FAIL','error':repr(e)}
     print('RESUME_COMPLETED',name,json.dumps(result),flush=True)
   else:time.sleep(min(60,max(1,next_scan-time.time())))
 print('RESUME_SUPERVISOR_FINISHED',flush=True)
