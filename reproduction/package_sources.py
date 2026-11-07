from pathlib import Path
import tarfile,os,json
root=Path.cwd(); hw=Path(os.environ['RST_HW_ROOT']); chosen=[]
blocked={'build','bin','obj','obj_dir','.git','__pycache__','.venv','data','5kcorrectdumps','results','libs'}
exts={'.o','.a','.so','.pyc','.qcow2','.img','.dump','.gz','.zip'}
with tarfile.open('reproduction/rst-project-source.tar.gz','w:gz') as tf:
 for source,prefix in [(root/'MemComp','software/MemComp'),(root/'ablation','software/ablation'),(root/'rst_figures','software/rst_figures'),(hw,'hardware')]:
  for p in source.rglob('*'):
   rel=p.relative_to(source)
   if not p.is_file() or p.is_symlink() or any(t in blocked for t in rel.parts) or p.suffix in exts:continue
   if p.open('rb').read(4)==b'\x7fELF':continue
   target=str(Path(prefix)/rel); tf.add(p,arcname=target,recursive=False);chosen.append(target)
 for p in root.iterdir():
  if p.is_file() and p.suffix in {'.sh','.md'} or p.name=='LICENSE':tf.add(p,arcname='software/'+p.name,recursive=False)
 for name in ['env.sh','run_native.sh','README.txt','python-packages.txt','deflate.Makefile.original','build_full_rst_stage4_summary.original.py']:
  tf.add(root/'reproduction'/name,arcname='reproduction/'+name,recursive=False)
Path('reproduction/source-file-list.json').write_text(json.dumps(chosen,indent=2))
print('SOURCE_PACKAGE_BYTES',Path('reproduction/rst-project-source.tar.gz').stat().st_size,'FILES',len(chosen))
