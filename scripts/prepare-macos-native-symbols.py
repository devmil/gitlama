#!/usr/bin/env python3
"""Enable DWARF in an owned copy of the pinned objective_c native hook."""
import hashlib
import json
from pathlib import Path
import shutil
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parent.parent
HOOK_SHA256 = 'bd1946fe6b63edb85503f10ed12ffe628a9a4553980c0d0a2036f563c17f758f'


def prepare(root=ROOT):
    config_path = root / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text(encoding='utf-8'))
    package = next(p for p in config['packages'] if p['name'] == 'objective_c')
    source = Path(url2pathname(urlparse(urljoin(config_path.as_uri(), package['rootUri'])).path))
    hook = source / 'hook/build.dart'
    contents = hook.read_bytes()
    destination = root / '.dart_tool/gitlama-symbol-sources/objective_c'
    receipt = destination.parent / 'receipt.json'
    if source == destination:
        original = json.loads(receipt.read_text(encoding='utf-8'))
        if hashlib.sha256(contents).hexdigest() != original['patched_hook_sha256']:
            raise ValueError('native_symbol_overlay_changed')
        return
    if hashlib.sha256(contents).hexdigest() != HOOK_SHA256:
        raise ValueError('objective_c_hook_requires_symbol_review')
    marker = b"    final cFlags = <String>[\n"
    if contents.count(marker) != 1:
        raise ValueError('objective_c_compile_flags_changed')
    patched = contents.replace(marker, marker + b"      '-g', // GitLama exact-build native symbols.\n")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    (destination / 'hook/build.dart').write_bytes(patched)
    receipt.write_text(json.dumps({
        'package': 'objective_c', 'version': '9.3.0',
        'original_hook_sha256': HOOK_SHA256,
        'patched_hook_sha256': hashlib.sha256(patched).hexdigest(),
        'change': 'enable_dwarf_for_compile_and_link',
    }, indent=2), encoding='utf-8')
    package['rootUri'] = destination.as_uri()
    config_path.write_text(json.dumps(config, indent=2), encoding='utf-8')


if __name__ == '__main__':
    prepare()
