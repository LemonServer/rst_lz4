"""Export exactly the committed source layout, without ignored runtime files."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
dest=root/'reproduction/rst-project-source.tar.gz'
subprocess.run(['git','-C',str(root),'archive','--format=tar.gz','--output',str(dest),'HEAD'],check=True)
print('SOURCE_PACKAGE_BYTES',dest.stat().st_size)
