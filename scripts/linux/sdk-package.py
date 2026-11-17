#!/usr/bin/env python3
"""Package/install a portable, verified local-engine overlay (no producer tree).

The matching unmodified framework SDK remains a separate, pinned dependency.
Archive members are regular files only; no links, escapes or extraction filters
are trusted. stdout is JSON, while diagnostics go to stderr.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MAX_ARCHIVE = 1024 * 1024 * 1024
MAX_EXPANDED = 4 * 1024 * 1024 * 1024
MAX_MEMBERS = 40000
MANIFEST_LIMIT = 16 * 1024 * 1024
OWNER = '.gitlama-linux-sdk'


def builder():
    spec = importlib.util.spec_from_file_location('sdk_builder', ROOT / 'scripts/linux/prepare-toolchain.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def sha(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def safe_name(value):
    p = PurePosixPath(value)
    if not value or p.is_absolute() or '..' in p.parts or str(p) != value or '\\' in value:
        raise ValueError('Unsafe SDK member path')
    return p


def required(mode, output):
    base = 'engine/src/out/' + output + '/'
    files = ['libflutter_linux_gtk.so', 'gen_snapshot', 'icudtl.dat',
             'flutter_tester', 'impellerc', 'libtessellator.so', 'font-subset', 'args.gn',
             'flutter_linux/flutter_linux.h', 'flutter_linux/fl_dart_project.h',
             'gen/dart-pkg/sky_engine/pubspec.yaml',
             'shader_lib/flutter/runtime_effect.glsl',
             'flutter_patched_sdk/platform_strong.dill',
             'dart-sdk/bin/dart', 'dart-sdk/bin/dartaotruntime',
             'dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot']
    if mode == 'release':
        files.append('flutter_patched_sdk_product/platform_strong.dill')
    else:
        files.append('gen/flutter/lib/snapshot/vm_isolate_snapshot.bin')
    return [base + name for name in files]


def inventory_files(source, prefix, owner):
    source = source.resolve()
    if source.is_file():
        if not source.is_relative_to(owner.resolve()):
            raise ValueError('SDK producer file leaves its owned source tree')
        yield prefix, source
        return
    if not source.is_dir():
        raise ValueError('SDK producer is missing a declared artifact directory: ' + str(source))
    found = 0
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        target = path.resolve()
        if not target.is_relative_to(owner.resolve()):
            raise ValueError('SDK producer link leaves its owned source tree')
        found += 1
        yield prefix + '/' + path.relative_to(source).as_posix(), target
    if not found:
        raise ValueError('Empty SDK artifact directory')


def pack(paths_file, output):
    tool = builder()
    paths = json.loads(paths_file.read_text(encoding='utf-8'))
    data = tool.validate_lock()
    mode = paths['mode']
    identity = tool.identity(data, mode)
    if paths['identity'] != identity:
        raise ValueError('Producer identity disagrees with checked-in lock')
    # Verify every promised producer artifact before selecting portable inputs.
    entry = Path(paths['manifest']).parent
    receipt = tool.verify_manifest(entry, identity, mode)
    source = Path(paths['engine_src'])
    config = data['modes'][mode]
    producer = source / 'out' / config['output']
    base = 'engine/src/out/' + config['output']
    files = {}
    for name in ['libflutter_linux_gtk.so', 'gen_snapshot', 'icudtl.dat',
                 'flutter_tester', 'impellerc', 'libtessellator.so', 'font-subset', 'args.gn']:
        files.update(inventory_files(producer / name, base + '/' + name, source))
    for name in ['flutter_linux', 'flutter_patched_sdk', 'gen/dart-pkg/sky_engine', 'shader_lib',
                 'gen/flutter/lib/snapshot']:
        if name.startswith('gen/flutter') and not (producer / name).exists():
            continue
        files.update(inventory_files(producer / name, base + '/' + name, source))
    if mode == 'release':
        product = producer / 'flutter_patched_sdk_product'
        if not product.is_dir():
            # This pinned GN configuration produces the product platform in its
            # generic local-engine directory; the tool declares both locations.
            product = producer / 'flutter_patched_sdk'
        files.update(inventory_files(product, base + '/flutter_patched_sdk_product', source))
    dart = producer / 'dart-sdk'
    if not (dart / 'bin/dart').is_file():
        dart = source / 'flutter/prebuilts/linux-x64/dart-sdk'
    files.update(inventory_files(dart, base + '/dart-sdk', source))
    if any(name not in files for name in required(mode, config['output'])):
        raise ValueError('SDK portable artifact closure is incomplete')
    manifest = {'schema_version': 1, 'identity': identity, 'mode': mode,
                'engine': config['output'], 'target': data['target'],
                'flutter_revision': data['flutter']['revision'],
                'patched_diff_sha256': receipt['patched_diff_sha256'],
                'resize_vsync_abi': data['resize_vsync_abi'],
                'builder': data['builder'], 'producer': receipt, 'files': {}}
    total = 0
    for name, path in sorted(files.items()):
        safe_name(name)
        size = path.stat().st_size
        total += size
        if total > MAX_EXPANDED:
            raise ValueError('SDK expanded byte budget exceeded')
        manifest['files'][name] = {'sha256': sha(path), 'size': size,
                                   'executable': bool(path.stat().st_mode & stat.S_IXUSR)}
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.partial')
    try:
        with tarfile.open(temporary, 'w:gz', compresslevel=5) as archive:
            for name, path in sorted(files.items()):
                archive.add(path, arcname=name, recursive=False)
            payload = json.dumps(manifest, sort_keys=True, indent=2).encode()
            import io
            info = tarfile.TarInfo('manifest.json')
            info.size = len(payload)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(payload))
        if temporary.stat().st_size > MAX_ARCHIVE:
            raise ValueError('SDK compressed byte budget exceeded')
        temporary.replace(output)
        checksum = sha(output)
        output.with_name(output.name + '.sha256').write_text(checksum + '\n', encoding='utf-8')
        return {'archive': str(output), 'sha256': checksum, 'identity': identity,
                'mode': mode, 'expanded_bytes': total, 'compressed_bytes': output.stat().st_size}
    finally:
        temporary.unlink(missing_ok=True)


def validate_manifest(manifest, data, mode, identity):
    if manifest.get('schema_version') != 1 or manifest.get('identity') != identity or manifest.get('mode') != mode:
        raise ValueError('SDK identity/mode mismatch')
    if manifest.get('flutter_revision') != data['flutter']['revision'] or manifest.get('target') != data['target']:
        raise ValueError('SDK framework/target mismatch')
    tests = manifest.get('producer', {}).get('tests')
    if tests != {'flow': 'passed', 'linux_embedder': 'passed'}:
        raise ValueError('SDK lacks completed producer tests')
    engine = data['modes'][mode]['output']
    if manifest.get('engine') != engine or manifest.get('resize_vsync_abi') != data['resize_vsync_abi']:
        raise ValueError('SDK engine/ABI mismatch')
    entries = manifest.get('files')
    if not isinstance(entries, dict) or not entries or any(name not in entries for name in required(mode, engine)):
        raise ValueError('SDK manifest is incomplete')
    total = 0
    for name, value in entries.items():
        safe_name(name)
        if not name.startswith('engine/src/out/' + engine + '/'):
            raise ValueError('SDK member is outside its engine mode')
        size = value.get('size')
        checksum = value.get('sha256', '')
        if type(value.get('executable')) is not bool or type(size) is not int or size < 0 or len(checksum) != 64 or any(c not in '0123456789abcdef' for c in checksum):
            raise ValueError('Invalid SDK file metadata')
        total += size
    if total > MAX_EXPANDED or len(entries) > MAX_MEMBERS:
        raise ValueError('SDK manifest resource budget exceeded')


def verify(root, data, mode, identity):
    root = root.resolve()
    if (root / OWNER).read_text(encoding='utf-8') != identity + '\n':
        raise ValueError('SDK destination ownership mismatch')
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
    validate_manifest(manifest, data, mode, identity)
    for name, value in manifest['files'].items():
        path = root / name
        if not path.resolve().is_relative_to(root) or path.is_symlink() or not path.is_file() or path.stat().st_size != value['size'] or bool(path.stat().st_mode & stat.S_IXUSR) != value['executable'] or sha(path) != value['sha256']:
            raise ValueError('SDK file missing, stale or corrupt: ' + name)
    return {'identity': identity, 'mode': mode, 'engine': manifest['engine'],
            'engine_src': str(root / 'engine/src'), 'manifest': str(root / 'manifest.json')}


def install(archive_path, checksum, destination, mode):
    tool = builder()
    data = tool.validate_lock()
    identity = tool.identity(data, mode)
    if not archive_path.is_file() or archive_path.stat().st_size > MAX_ARCHIVE or sha(archive_path) != checksum:
        raise ValueError('SDK archive checksum/size mismatch')
    if destination.is_symlink():
        raise ValueError('SDK destination cannot be a link')
    if destination.exists():
        # Never repair or delete someone else's directory or an invalid cache.
        return verify(destination, data, mode, identity)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.gitlama-sdk-', dir=destination.parent) as temporary:
        staging = Path(temporary)
        with tarfile.open(archive_path, 'r:gz') as archive:
            members = []
            expanded = 0
            for member in archive:
                expanded += member.size
                if len(members) >= MAX_MEMBERS or member.size < 0 or expanded > MAX_EXPANDED:
                    raise ValueError('SDK archive resource budget exceeded')
                members.append(member)
            names = set()
            total = 0
            for member in members:
                safe_name(member.name)
                if not member.isfile() or member.name in names or member.size < 0:
                    raise ValueError('SDK archive contains a link, duplicate or special member')
                names.add(member.name)
                total += member.size
                if len(names) > MAX_MEMBERS or total > MAX_EXPANDED:
                    raise ValueError('SDK archive resource budget exceeded')
            metadata = archive.getmember('manifest.json')
            if metadata.size > MANIFEST_LIMIT:
                raise ValueError('SDK manifest too large')
            manifest = json.load(archive.extractfile(metadata))
            validate_manifest(manifest, data, mode, identity)
            if names != set(manifest['files']) | {'manifest.json'}:
                raise ValueError('SDK payload and manifest disagree')
            for member in members:
                if member.name == 'manifest.json':
                    continue
                expected = manifest['files'][member.name]
                if expected['size'] != member.size:
                    raise ValueError('SDK declared size mismatch')
                target = staging / member.name
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open('xb') as out:
                    shutil.copyfileobj(source, out, 1024 * 1024)
                target.chmod(0o755 if expected.get('executable') else 0o644)
            (staging / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        (staging / OWNER).write_text(identity + '\n', encoding='utf-8')
        verify(staging, data, mode, identity)
        # Rename only the newly owned extraction. Failure leaves existing SDKs
        # and framework selection intact; no global SDK path is modified.
        staging.rename(destination)
    return verify(destination, data, mode, identity)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    producer = commands.add_parser('pack')
    producer.add_argument('--paths', type=Path, required=True)
    producer.add_argument('--output', type=Path, required=True)
    consumer = commands.add_parser('install')
    consumer.add_argument('--archive', type=Path, required=True)
    consumer.add_argument('--checksum-file', type=Path, required=True)
    consumer.add_argument('--destination', type=Path, required=True)
    consumer.add_argument('--mode', choices=['debug', 'profile', 'release'], required=True)
    check = commands.add_parser('verify')
    check.add_argument('--root', type=Path, required=True)
    check.add_argument('--mode', choices=['debug', 'profile', 'release'], required=True)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            result = pack(args.paths, args.output)
        elif args.command == 'install':
            result = install(args.archive, args.checksum_file.read_text(encoding='utf-8').strip(), args.destination, args.mode)
        else:
            tool = builder(); data = tool.validate_lock()
            result = verify(args.root, data, args.mode, tool.identity(data, args.mode))
        print(json.dumps(result))
        return 0
    except (ValueError, OSError, KeyError, tarfile.TarError) as error:
        print('Linux SDK artifact: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
