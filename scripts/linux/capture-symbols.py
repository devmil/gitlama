#!/usr/bin/env python3
"""Retain exact engine DWARF and bind it to the runtime build ID."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def build_id(path):
    notes = subprocess.check_output(['readelf', '-n', str(path)], text=True)
    match = re.search(r'Build ID: ([0-9a-f]+)', notes)
    if not match:
        raise ValueError('Engine has no GNU build ID')
    return match.group(1)


def capture(paths_file, destination):
    paths = json.loads(paths_file.read_text(encoding='utf-8'))
    output = Path(paths['engine_src']) / 'out' / paths['engine']
    original = output / 'lib.unstripped/libflutter_linux_gtk.so'
    runtime = output / 'libflutter_linux_gtk.so'
    identity = build_id(runtime)
    if build_id(original) != identity:
        raise ValueError('Engine symbols and runtime have different build IDs')
    sections = subprocess.check_output(['readelf', '-S', '--wide', str(original)], text=True)
    if '.debug_info' not in sections or '.debug_line' not in sections:
        raise ValueError('Original engine has no source-level DWARF')
    dynamic = subprocess.check_output(['nm', '-D', '--defined-only', str(runtime)], text=True)
    address = next((line.split()[0] for line in dynamic.splitlines()
                    if line.split()[-1] == 'fl_dart_project_set_enable_resize_vsync'), None)
    if address is None:
        raise ValueError('Runtime lacks the resize API')
    symbolizer = Path(paths['engine_src']) / 'flutter/buildtools/linux-x64/clang/bin/llvm-addr2line'
    location = subprocess.check_output([str(symbolizer), '-e', str(original), '0x' + address], text=True).strip()
    if not re.search(r'fl_dart_project\.cc:[1-9][0-9]*', location):
        raise ValueError('Engine symbols cannot resolve the resize API to a source line')
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / ('libflutter_linux_gtk.so.' + identity + '.debug')
    shutil.copyfile(original, target)
    report = {'schema_version': 1, 'identity': paths['identity'], 'mode': paths['mode'],
              'build_id': identity, 'symbols': target.name,
              'source_line_verified': True,
              'symbols_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'runtime_sha256': hashlib.sha256(runtime.read_bytes()).hexdigest(),
              'durable_retention': 'CI transport only; archive with release diagnostics before expiry'}
    (destination / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    shutil.copyfile(paths['manifest'], destination / 'producer-manifest.json')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--paths', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(capture(args.paths, args.output)))
