#!/usr/bin/env python3
"""Load an extracted/built native artifact; never search a development fallback."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('bundle',type=Path,help='.app on macOS, bundle directory on Linux/Windows')
args=parser.parse_args()
bundle=args.bundle.resolve()
relative={'Darwin':'Contents/Frameworks/gitlama_core.framework/gitlama_core',
          'Linux':'lib/libgitlama_core.so','Windows':'gitlama_core.dll'}[platform.system()]
library=bundle/relative
if not library.is_file(): parser.error(f'Native asset missing: {library}')
env=dict(
    os.environ,
    GITLAMA_NATIVE_LIBRARY=str(library),
    GIT_AUTHOR_NAME='GitLama Fixture',
    GIT_AUTHOR_EMAIL='fixture@gitlama.invalid',
    GIT_COMMITTER_NAME='GitLama Fixture',
    GIT_COMMITTER_EMAIL='fixture@gitlama.invalid',
)
pinned_flutter = root / '.fvm' / 'flutter_sdk' / 'bin'
if pinned_flutter.is_dir():
    env['PATH'] = str(pinned_flutter) + os.pathsep + env.get('PATH', '')
subprocess.run([sys.executable,str(root/'scripts/verify.py'),'--native'],cwd=root,env=env,check=True)
