"""Audit all pages and raw latency cases; does not run or rebuild simulation."""
import os,json,hashlib,math,sys,datetime
from pathlib import Path
from collections import defaultdict
from zoneinfo import ZoneInfo

root=Path(os.environ['RST_HW_ROOT']).resolve()
base=Path(__file__).resolve().parent
sys.path.insert(0,str(root/'tools'))
from run_m4_experimental_regression import parse_hardware_log

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()

def resolve(path):
 p=Path(path);return p if p.is_absolute() else root/p

def close(a,b):assert math.isclose(a,b,rel_tol=1e-11,abs_tol=1e-10),(a,b)
def gm(values):return math.exp(sum(map(math.log,values))/len(values))

def main():
 manifest=json.loads((base.parent/'dataset-manifest.json').read_text())
 summary_path=root/'build/full88/full-summary.json'
 d=json.loads(summary_path.read_text());results=d['results']
 assert d['status']=='PASS' and d['coverage_contract']=='all-pages-v2'
 assert d['pages_requested']==5000 and d['latency_pages_requested']=='ALL'
 assert len(results)==len(manifest)==88
 expected={x['name']:x for x in manifest};seen=set();records=[];groups=defaultdict(list)
 for r in results:
  name=Path(r['input_file']).name;assert name not in seen;seen.add(name);m=expected[name]
  src=resolve(r['input_file']);assert src.stat().st_size==m['bytes'] and digest(src)==m['sha256'],name
  n=min(5000,(src.stat().st_size+4095)//4096);assert n==m['pages']
  assert r['status']=='PASS' and r['coverage_contract']=='all-pages-v2' and r['artifact_isolation']=='decode_dataset-v1'
  assert r['input_accounting']['selected_pages']==n
  hw=r['hardware_roundtrip'];hp=hw['hardware_pages'];h=hw['hardware_summary']
  assert hw['status']=='PASS' and hw['pages_observed']==h['pages']==len(hp)==n
  assert [x['page_idx'] for x in hp]==list(range(1,n+1))
  for key in ('comp_cycles','decomp_cycles','raw_bits','encoded_bits'):assert sum(x[key] for x in hp)==h[key],(name,key)
  close(h['comp_bpc'],h['input_bytes']/h['comp_cycles']);close(h['decomp_bpc'],h['input_bytes']/h['decomp_cycles'])
  close(h['ratio'],h['raw_bits']/h['encoded_bits'])
  log=resolve(hw['hardware_log']);text=log.read_text()
  assert 'tb_M4ExperimentalRuntimeFileCompressorTop passed' in text,name
  rawpages,rawsummary=parse_hardware_log(text);assert rawpages==hp and rawsummary['pages']==n
  dec=r['decompressor_decode'];assert dec['status']=='PASS' and dec['page_count']==len(dec['pages'])==n
  assert resolve(dec['build_dir']).resolve()==root/'build/full88/decode_cases'/src.stem
  for idx,p in enumerate(dec['pages']):assert p['page_idx']==idx and '[sv-decompressor] PASS' in p['sv_stdout']
  lat=r['decompressor_latency'];s=lat['summary']
  assert lat['status']=='PASS' and lat['page_count']==s['page_count']==n
  assert lat['case_count']==s['case_count']==16*n
  assert resolve(lat['build_dir']).resolve()==root/'build/full88/latency_all'/src.stem
  raw=resolve(lat['result_file']);count=0;cycle_sum=0;critical_sum=0
  with raw.open() as f:
   for line in f:
    a=line.split()
    if not a:continue
    assert len(a)==46 and int(a[0])==count and a[1]==f'page{count//16:04d}_chunk{count%16:02d}',(name,count)
    cycles=int(a[2]);assert sum(map(int,a[3:9]))==cycles and int(a[9])==256
    ready=list(map(int,a[-4:]));assert all(0<=v<=cycles for v in ready)
    cycle_sum+=cycles;critical_sum+=sum(ready);count+=1
  assert count==16*n;close(cycle_sum/count,s['rtl_cycle_avg']);close(critical_sum/(4*count),s['critical64_cycle_avg'])
  metrics={'compressor_bpc':h['comp_bpc'],'decompressor_bpc':h['decomp_bpc'],'decompressor_critical64_cycles':s['critical64_cycle_avg'],'decompressor_full_chunk_cycles':s['rtl_cycle_avg']}
  groups[name.split('_',1)[0]].append(metrics)
  records.append({'dataset':name,'pages':n,'latency_cases':count,'status':'PASS','input_sha256':m['sha256'],'hardware_log_sha256':digest(log),'latency_results_sha256':digest(raw),**metrics})
  print('AUDIT_PASS',len(records),'/88',name,'pages',n,'latency_cases',count,flush=True)
 assert seen==set(expected) and len(groups)==7
 assert sum(x['pages'] for x in records)==435461 and sum(x['latency_cases'] for x in records)==6967376
 assert len({r['decompressor_decode']['build_dir'] for r in results})==88
 assert len({r['decompressor_latency']['build_dir'] for r in results})==88
 metric_summary={key:gm([gm([v[key] for v in group]) for group in groups.values()]) for key in metrics}
 for key,value in metric_summary.items():close(value,d['paper_metric_summary']['suite_geomean_of_geomeans'][key])
 report={'status':'PASS','audited_at_shanghai':datetime.datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),'datasets':88,'pages':435461,'latency_cases':6967376,'latency_64B_ready_measurements':27869504,'suite_count':7,'contract':'all-pages-v2','checks':['input manifest bytes and SHA256','all hardware pages and exact cycle totals','raw roundtrip logs match page records','standalone decode PASS on every page','unique per-dataset decode and latency directories','every raw latency page/chunk index','raw latency cycle accounting and recomputed means','independent suite-geomean recomputation'],'summary_sha256':digest(summary_path),'runtime_root':str(root),'metrics':metric_summary,'per_dataset':records}
 (base/'acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print('ACCEPTANCE_PASS',json.dumps({k:v for k,v in report.items() if k!='per_dataset'}),flush=True)

if __name__=='__main__':main()
