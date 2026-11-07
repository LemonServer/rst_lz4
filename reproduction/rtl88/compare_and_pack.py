import os,json,csv,tarfile,hashlib,math,time
from pathlib import Path
root=Path(os.environ['RST_HW_ROOT']);base=Path('reproduction/rtl88');out=root/'build/full88'
d=json.loads((out/'full-summary.json').read_text());r=d['results'];meta=json.loads((base/'run-metadata.json').read_text());d['end_to_end_elapsed_seconds']=time.time()-meta['started_at_epoch'];d['started_at_shanghai']=meta['started_at_shanghai'];assert len(r)==88 and all(x['status']=='PASS' for x in r)
assert sum(x['input_accounting']['selected_pages'] for x in r)==435461
for x in r:
 n=x['input_accounting']['selected_pages'];assert x['decompressor_latency']['page_count']==n and x['decompressor_decode']['page_count']==n
s=d['paper_metric_summary']['suite_geomean_of_geomeans'];a=json.loads((root/'evidence/full_suite_88x5000_summary.json').read_text())['paper_metric_summary']['suite_geomean_of_geomeans']
rows=[]
for k,p in [('compressor_gbps_at_2_5ghz',4.13),('decompressor_gbps_at_2_5ghz',13.3),('decompressor_critical64_ns_at_2_5ghz',18.0)]:
 rows.append({'metric':k,'measured':s[k],'paper':p,'delta_vs_paper_pct':100*(s[k]/p-1),'bundled_full_run':a[k],'delta_vs_bundle_pct':100*(s[k]/a[k]-1)})
(base/'comparison.json').write_text(json.dumps({'status':'PASS','datasets':88,'pages':435461,'all_page_latency':True,'metrics':rows,'paper_metric_summary':d['paper_metric_summary']},indent=2))
with (base/'per_dataset.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['dataset','pages','status','compression_ratio','compressor_B_per_cycle','decompressor_B_per_cycle','critical64_cycles','full_chunk_cycles','latency_pages','latency_cases'])
 for x in r:
  h=x['hardware_roundtrip']['hardware_summary'];l=x['decompressor_latency']['summary'];w.writerow([Path(x['input_file']).name,x['input_accounting']['selected_pages'],x['status'],h['ratio'],h['comp_bpc'],h['decomp_bpc'],l['critical64_cycle_avg'],l['rtl_cycle_avg'],x['decompressor_latency']['page_count'],x['decompressor_latency']['case_count']])
lines=['88 数据集 RTL 全量验证对比','PASS：88/88；共435461页；吞吐率与直接解压延迟均覆盖全部页面。','TPC-C实际461页，其余87个数据集各5000页。','统计口径：先求各类别内几何平均，再对7类取几何平均；2.5GHz换算。','指标 | 本次 | 论文 | 对论文差异 | 作者附带全量汇总 | 对该汇总差异']
for x in rows:lines.append(f"{x['metric']} | {x['measured']:.6f} | {x['paper']} | {x['delta_vs_paper_pct']:+.3f}% | {x['bundled_full_run']:.6f} | {x['delta_vs_bundle_pct']:+.3f}%")
lines+=['','本次运行large RTL：硬件压缩-解压逐字节一致性、独立解压检查和直接延迟测量均通过。','周期转换不是实测芯片频率/功耗/面积。论文18ns含定位开销，复现包critical64为直接RTL输出可用周期，口径并非完全相同。','论文正文13.3GB/s与附带全量汇总18.0227GB/s并不一致；两套参考值分别列出，不能把后者当作论文正文值。','原始逐页硬件日志与直接延迟刺激/结果留在服务器硬件工程build/full88及build/native/latency中。','本地传回逐数据集CSV、汇总JSON、驱动、报告和运行日志，不含编译产物或Debian镜像。','SSH全过程仅一个连接，未使用tmux/screen/sudo。']
lines+=['首轮检查点记录曾因字节序列化报错，真实通过日志已保留，并由修正驱动继续完成后续全部检查。','完整运行起点（上海）：'+d['started_at_shanghai'],'完整运行耗时（秒）：'+str(round(d['end_to_end_elapsed_seconds']))]
(base/'RTL全量对比.txt').write_text('\n'.join(lines),encoding='utf-8')
compact={k:v for k,v in d.items() if k!='results'};compact['results']=[]
for x in r:
 y=json.loads(json.dumps(x));y['hardware_roundtrip'].pop('hardware_pages',None);y['decompressor_decode'].pop('pages',None);compact['results'].append(y)
(base/'summary.json').write_text(json.dumps(compact,indent=2))
archive=base/'rtl88-results.tar.gz'
with tarfile.open(archive,'w:gz') as tf:
 for p in base.iterdir():
  if p.is_file() and p.suffix in {'.py','.txt','.csv','.json','.log','.md'}:tf.add(p,arcname='rtl88/'+p.name)
print('RESULT_ARCHIVE',archive.stat().st_size,hashlib.sha256(archive.read_bytes()).hexdigest(),flush=True)
print(json.dumps(rows,indent=2),flush=True)
