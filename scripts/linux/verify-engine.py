#!/usr/bin/env python3
"""Bind a built/extracted bundle to the selected, verified local engine bytes."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def selected(mode):
    installed = os.environ.get('GITLAMA_LINUX_SDK_DIR')
    args = ([sys.executable, str(HERE / 'sdk-package.py'), 'verify', '--root', installed, '--mode', mode]
            if installed else [sys.executable, str(HERE / 'prepare-toolchain.py'), '--offline', '--mode', mode])
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE, text=True)
    return json.loads(result.stdout)


def verify(bundle, paths, mode, write=False):
    base = Path(paths['engine_src']) / 'out' / paths['engine']
    producer = base / 'libflutter_linux_gtk.so'
    packaged = bundle / 'lib/libflutter_linux_gtk.so'
    if not producer.is_file() or not packaged.is_file() or packaged.is_symlink():
        raise ValueError('Missing exact producer or bundled engine')
    expected = digest(producer)
    if digest(packaged) != expected:
        raise ValueError('Bundled Flutter engine does not match its producer')
    dynamic = subprocess.run(['nm', '-D', '--defined-only', str(packaged)], check=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
    for symbol in ['fl_dart_project_set_enable_resize_vsync', 'fl_dart_project_get_enable_resize_vsync']:
        if not any(line.split()[-1] == symbol for line in dynamic.splitlines() if line.split()):
            raise ValueError('Bundled engine lacks the declared resize ABI')
    report = {'schema_version': 1, 'identity': paths['identity'], 'mode': mode,
              'engine_sha256': expected, 'resize_vsync_abi': 1}
    provenance = bundle / 'gitlama-linux-engine.json'
    if write:
        provenance.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    elif not provenance.is_file() or json.loads(provenance.read_text(encoding='utf-8')) != report:
        raise ValueError('Missing or mismatched packaged engine provenance')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], required=True)
    parser.add_argument('--write-provenance', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.bundle, selected(args.mode), args.mode, args.write_provenance)))
        return 0
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print('Linux engine identity: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
