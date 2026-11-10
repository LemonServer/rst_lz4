import os,json,csv,tarfile,hashlib,math,time,datetime
from pathlib import Path
root=Path(os.environ['RST_HW_ROOT']);base=Path('reproduction/rtl88');out=root/'build/full88'
audit=json.loads((base/'acceptance.json').read_text())
assert audit['status']=='PASS' and audit['datasets']==88 and audit['pages']==435461 and audit['latency_cases']==6967376
assert hashlib.sha256((out/'full-summary.json').read_bytes()).hexdigest()==audit['summary_sha256']
state=json.loads((base/'job-status.json').read_text())
finished=state.get('simulation_finished_at_shanghai',state.get('finished_at_shanghai'))
end=datetime.datetime.fromisoformat(finished).timestamp() if finished else time.time()
d=json.loads((out/'full-summary.json').read_text());r=d['results'];meta=json.loads((base/'run-metadata.json').read_text());d['end_to_end_elapsed_seconds']=end-meta['started_at_epoch'];d['started_at_shanghai']=meta['started_at_shanghai'];d['simulation_finished_at_shanghai']=finished;d['acceptance']=audit['audited_at_shanghai'];assert len(r)==88 and all(x['status']=='PASS' for x in r)
assert sum(x['input_accounting']['selected_pages'] for x in r)==435461
for x in r:
 assert x.get('artifact_isolation')=='decode_dataset-v1' and x.get('coverage_contract')=='all-pages-v2'
 n=x['input_accounting']['selected_pages'];assert x['decompressor_latency']['case_count']==16*n;assert x['decompressor_latency']['page_count']==n and x['decompressor_decode']['page_count']==n
assert len({x['decompressor_decode']['build_dir'] for x in r})==88
assert len({x['decompressor_latency']['build_dir'] for x in r})==88
def converted_metrics(summary):
 # The verifier stores B/cycle and cycles, not derived GB/s or ns fields.
 return {'compressor_gbps_at_2_5ghz':summary['compressor_bpc']*2.5,
         'decompressor_gbps_at_2_5ghz':summary['decompressor_bpc']*2.5,
         'decompressor_critical64_ns_at_2_5ghz':summary['decompressor_critical64_cycles']/2.5,
         'decompressor_full_chunk_ns_at_2_5ghz':summary['decompressor_full_chunk_cycles']/2.5}
s=converted_metrics(d['paper_metric_summary']['suite_geomean_of_geomeans']);a=converted_metrics(json.loads((root/'evidence/full_suite_88x5000_summary.json').read_text())['paper_metric_summary']['suite_geomean_of_geomeans'])
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
lines+=['','完整chunk平均延迟：'+str(s['decompressor_full_chunk_ns_at_2_5ghz'])+' ns；作者附带值：'+str(a['decompressor_full_chunk_ns_at_2_5ghz'])+' ns。','本次运行large RTL：硬件压缩-解压逐字节一致性、独立解压检查和直接延迟测量均通过。','周期转换不是实测芯片频率/功耗/面积；本次为Verilator RTL仿真，不等同于论文的时序收敛后门级仿真。','论文18ns由17ns计算和1ns定位组成；本次critical64是RTL直接输出可用周期，未额外加入该1ns定位开销，口径并非完全相同。','论文正文13.3GB/s与附带全量汇总18.0227GB/s并不一致；两套参考值分别列出，不能把后者当作论文正文值。','原始逐页硬件日志留在服务器旧硬件工程build/full88/logs；全页直接延迟刺激/结果在build/full88/latency_all/<dataset>/。','本地传回逐数据集CSV、汇总JSON、验收证据、驱动、报告和运行日志，不含编译产物或Debian镜像。','SSH全过程仅一个连接，未使用tmux/screen/sudo。']
lines+=['首轮检查点记录曾因字节序列化报错，真实通过日志已保留，并由修正驱动继续完成后续全部检查。','完整运行起点（上海）：'+d['started_at_shanghai'],'仿真完成/首次打包时间（上海）：'+str(finished),'完整墙钟耗时（含中断间隔，秒）：'+str(round(d['end_to_end_elapsed_seconds'])),'独立验收时间（上海）：'+audit['audited_at_shanghai'],'验收：88个数据集输入SHA256一致；435461页逐页检查；6967376条原始延迟用例连续覆盖；7类几何平均独立重算一致。','首次自动打包因派生指标字段名错误退出；验收时修复报告脚本后重新打包，未重跑或改动RTL仿真结果。']
(base/'RTL全量对比.txt').write_text('\n'.join(lines),encoding='utf-8')
compact={k:v for k,v in d.items() if k!='results'};compact['results']=[]
for x in r:
 y=json.loads(json.dumps(x));y['hardware_roundtrip'].pop('hardware_pages',None);y['decompressor_decode'].pop('pages',None);compact['results'].append(y)
(base/'summary.json').write_text(json.dumps(compact,indent=2))
archive=base/'rtl88-results.tar.gz'
with tarfile.open(archive,'w:gz') as tf:
 for p in base.iterdir():
  if p.name not in {'job-status.json','current-session.json'} and not p.name.startswith('job-status-') and p.is_file() and p.suffix in {'.py','.txt','.csv','.json','.log','.md'}:tf.add(p,arcname='rtl88/'+p.name)
print('RESULT_ARCHIVE',archive.stat().st_size,hashlib.sha256(archive.read_bytes()).hexdigest(),flush=True)
print(json.dumps(rows,indent=2),flush=True)
