import csv,math,json,collections
from pathlib import Path
D=Path('generated/data')
def rows(n):return list(csv.DictReader((D/n).open()))
def gm(v):return math.exp(sum(math.log(x) for x in v)/len(v))
def geo(r,k):
 g=collections.defaultdict(list)
 for x in r:g[x['suite']].append(float(x[k]))
 return gm([gm(v) for v in g.values()])
main=rows('full_rst_main_mb2_5k.csv');assert len(main)==88 and len({x['file'] for x in main})==88
assert sum(int(x['pages']) for x in main)==435461
p=[x for x in rows('main_plot_data.csv') if x['row_type']=='benchmark'];assert len(p)==88
metrics={k:geo(p,k) for k in ['rst','asic_deflate','software_deflate']}
expected={64:3.095199,128:3.420740,192:3.541648,256:3.561355}
v=rows('rst_stage_4_summary.csv');assert len(v)==4
checks=[]
for x in v:
 n=int(x['dictsize']);r=rows(f'stage_v_{n}B_per_benchmark.csv');assert len(r)==88 and len({z['file'] for z in r})==88
 assert sum(int(z['pages']) for z in r)==435461
 val=geo(r,'ratio');assert abs(val-float(x['overall_geogeo_CR']))<1e-10
 assert abs(val-expected[n])<1e-6
 checks.append({'dictionary_bytes':n,'measured':val,'author_checkpoint':expected[n],'absolute_difference':val-expected[n],'datasets':88,'pages':435461})
a={Path(x['file']).name:float(x['rst_full']) for x in main};b={Path(x['file']).name:float(x['ratio']) for x in rows('stage_v_128B_per_benchmark.csv')}
assert a==b
report={'status':'PASS','datasets':88,'suites':7,'pages_per_sweep':435461,'metrics':metrics,'stage_v':checks,'main_stage_v_128B_per_dataset_equal':True,'stage_v_recomputed':True,'paper_rounded_values':{'rst':3.4,'asic_deflate':3.3,'software_deflate':3.84},'stage_IV_A_display_alias':{'measured_bytes':80,'displayed_bytes':64}}
Path('reproduction/full-comparison.json').write_text(json.dumps(report,indent=2))
lines=['RST 完整软件复现实验对比（2026-11-07）','', '验收：PASS。88 个数据集，7 类程序，主扫描及阶段 V 每轮均处理435461页。','87个文件各5000页；DATABASES_tpc-c.dump仅461页。','统计方法：类别内几何平均，再对7类几何平均。','','指标 | 本次实测 | 论文约值 | 相对差异']
for k,paper in report['paper_rounded_values'].items():lines.append(f'{k} | {metrics[k]:.9f}x | {paper}x | {(metrics[k]/paper-1)*100:+.4f}%')
lines+=['','阶段V：全部从头重新计算，没有读取作者检查点。','字典大小 | 本次实测 | 作者附带检查点 | 绝对差']
for x in checks:lines.append(f"{x['dictionary_bytes']} B | {x['measured']:.9f}x | {x['author_checkpoint']:.6f}x | {x['absolute_difference']:+.10f}")
lines+=['','128B阶段V与主扫描的88个逐数据集压缩比完全一致。','四种字典配置均与作者检查点一致到6位小数。','', '128B消融逐步结果：']
for i in [1,2,3]:
 x=next(x for x in rows(f'rst_step_{i}_summary.csv') if x['dictsize']=='128');lines.append(f"IV.{chr(64+i)}: {float(x['overall_geogeo_CR']):.9f}x")
lines+= [f"V: {metrics['rst']:.9f}x",'', '差异与限制：','论文主图为约值，百分比偏差包含取整差异；阶段V精确参考来自复现包检查点，已明确区分。','IV.A原始80B配置被作者绘图脚本显示成64B；本次保留该行为与原始CSV，不能声称该柱严格为64B。','本次完成图18/19对应软件压缩率与消融复现。未重跑88集RTL、ASIC综合或Gem5性能；不能由此验证18ns、15%加速或芯片功耗面积。','本次修改仅为GCC兼容宏、阶段V逐数据集记录及32工作进程设置，没有更改压缩算法。','所有任务和传输共用一个SSH连接，未使用tmux/screen/sudo或启动虚拟机。','本地源码不含编译产物、Debian镜像和大型原始数据集；原始数据留在服务器。']
Path('reproduction/完整复现对比.txt').write_text('\n'.join(lines),encoding='utf-8')
print(json.dumps(report,indent=2))
