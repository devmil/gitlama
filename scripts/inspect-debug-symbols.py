#!/usr/bin/env python3
"""Verify one private diagnostics archive, list images and optionally extract it."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--extract', type=Path, help='new private destination; existing paths are refused')
    parser.add_argument('--image', help='image basename or recorded relative path')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('private_symbols', Path(__file__).with_name('retain-debug-symbols.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='gitlama-inspect-symbols-') as folder:
        source = Path(folder)
        manifest = module.unpack_verified(args.archive, source)
        module.validate_unit(manifest, source)
        binaries = [entry for entry in manifest['binaries'] if args.image is None
                    or args.image in (entry['file'], Path(entry['file']).name)]
        if not binaries:
            parser.error('image is not recorded in this archive')
        print(json.dumps({'unit': manifest['unit'], 'version': manifest['version'],
                          'build': manifest['build'], 'provenance': manifest['provenance'],
                          'binaries': binaries}, indent=2, sort_keys=True))
        if args.extract:
            shutil.copytree(source, args.extract)


if __name__ == '__main__':
    main()
