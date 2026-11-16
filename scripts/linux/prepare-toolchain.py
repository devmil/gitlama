#!/usr/bin/env python3
"""Prepare an owned, content-addressed Linux Flutter checkout and local engine.

stdout is one JSON object. Subprocess diagnostics stream to stderr, including
stdout from failed compilers. Never modifies the developer's global SDK.
"""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / 'tooling/linux/flutter.lock.json'
BOUNDARIES = {
    'flutter-linux-embedder': 'engine/src/flutter/shell/platform/linux/',
}


class ToolchainError(Exception):
    pass


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def owned_path(root, relative):
    p = Path(relative)
    if p.is_absolute() or '..' in p.parts:
        raise ToolchainError(f'Unsafe relative path: {relative}')
    resolved = (root / p).resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise ToolchainError(f'Path leaves its owner: {relative}')
    return resolved


def validate_lock(root=ROOT, lock_path=LOCK):
    data = json.loads(lock_path.read_text(encoding='utf-8'))
    if data['schema_version'] != 1 or data['bootstrap_version'] != 1:
        raise ToolchainError('Unsupported lock/bootstrap schema')
    if data['target'] != {'os': 'linux', 'architecture': 'x64'}:
        raise ToolchainError('Only Linux x64 is supported')
    for source in ['flutter', 'depot_tools']:
        revision = data[source]['revision']
        if not re.fullmatch(r'[0-9a-f]{40}', revision) or len(set(revision)) == 1:
            raise ToolchainError(f'{source} requires a full immutable commit')
    tag = data['flutter']['version_tag']
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-\d+\.\d+\.pre)?', tag['name']):
        raise ToolchainError('Immutable Flutter version tag required')
    for field in ['revision', 'merge_base']:
        if not re.fullmatch(r'[0-9a-f]{40}', tag[field]) or len(set(tag[field])) == 1:
            raise ToolchainError('Immutable version-tag ancestry required')
    if not 1 <= tag['fetch_depth'] <= 10000 or tag['commits_past_merge_base'] < 0:
        raise ToolchainError('Bounded version-tag ancestry required')
    if data['flutter']['repository'] != 'https://github.com/flutter/flutter.git':
        raise ToolchainError('Unexpected Flutter source authority')
    if data['depot_tools']['repository'] != 'https://chromium.googlesource.com/chromium/tools/depot_tools.git':
        raise ToolchainError('Unexpected depot_tools source authority')
    if not re.fullmatch(r'[^\s]+@sha256:[0-9a-f]{64}', data['builder']['image']):
        raise ToolchainError('Builder requires an immutable image digest')
    recipe = owned_path(root, data['builder']['recipe'])
    if digest(recipe) != data['builder']['sha256']:
        raise ToolchainError('Builder recipe hash mismatch')
    if data['builder']['image'] not in recipe.read_text(encoding='utf-8'):
        raise ToolchainError('Builder recipe and lock image disagree')
    if set(data['modes']) != {'debug', 'profile', 'release'}:
        raise ToolchainError('All three build modes must be locked')
    for mode, config in data['modes'].items():
        expected = 'host_' + mode + ('_unopt' if mode == 'debug' else '')
        if config['output'] != expected or '--runtime-mode=' + mode not in config['gn']:
            raise ToolchainError(f'Invalid engine configuration: {mode}')
        if not config['targets'] or any(not re.fullmatch(r'[a-zA-Z0-9_-]+', t) for t in config['targets']):
            raise ToolchainError('Invalid Ninja targets')
    if set(data['patches']) != set(BOUNDARIES):
        raise ToolchainError('Missing or unexpected patch boundary')
    for boundary, prefix in BOUNDARIES.items():
        entries = data['patches'][boundary]
        names = (root / 'patches' / boundary / 'series').read_text(encoding='utf-8').splitlines()
        if names != [Path(e['path']).name for e in entries] or not entries:
            raise ToolchainError(f'Patch order disagrees with series: {boundary}')
        for entry in entries:
            path = owned_path(root, entry['path'])
            expected_parent = (root / 'patches' / boundary).resolve()
            if path.parent != expected_parent or digest(path) != entry['sha256']:
                raise ToolchainError(f'Patch hash/path mismatch: {entry["path"]}')
            headers = re.findall(r'^diff --git a/(\S+) b/(\S+)$', path.read_text(encoding='utf-8'), re.M)
            if not headers or any(not a.startswith(prefix) or not b.startswith(prefix) for a, b in headers):
                raise ToolchainError(f'Patch crosses ownership boundary: {path.name}')
    for authority in data['authorities'].values():
        if not owned_path(root, authority).is_file():
            raise ToolchainError(f'Missing authority: {authority}')
    if not re.fullmatch(r'[0-9a-f]{64}', data['flutter']['deps_file_sha256']):
        raise ToolchainError('DEPS checksum required')
    if json.loads((root / '.fvmrc').read_text(encoding='utf-8'))['flutter'] != tag['expected_version']:
        raise ToolchainError('Framework lock disagrees with .fvmrc')
    return data


def identity(data, mode, root=ROOT):
    inputs = {'lock': data, 'mode': mode, 'scripts': {}}
    # Only the source builder changes engine preparation. Packaging/reporting
    # and app-command wrappers do not change engine bytes or required host tools.
    builder = root / 'scripts/linux/prepare-toolchain.py'
    inputs['scripts'][builder.name] = digest(builder)
    for name in ['sdk-package.py', 'capture-symbols.py']:
        inputs['scripts'][name] = digest(root / 'scripts/linux' / name)
    return hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()


def run(args, cwd, env=None):
    print('+ ' + ' '.join(str(a) for a in args), file=sys.stderr, flush=True)
    # Both streams go to the diagnostic channel. No buffered compiler errors.
    subprocess.run([str(a) for a in args], cwd=cwd, env=env,
                   stdout=sys.stderr, stderr=sys.stderr, check=True)


def capture(args, cwd, env=None):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env,
                            stdout=subprocess.PIPE, stderr=sys.stderr, text=True)
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, args)
    return result.stdout.strip()


def gtk_display_is_usable(environ):
    """Return whether GTK can initialize against the selected display."""
    probe = '''
import ctypes
import ctypes.util
import sys

library = ctypes.util.find_library('gtk-3')
if library is None:
    sys.exit(1)
gtk = ctypes.CDLL(library)
gtk.gtk_init_check.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
gtk.gtk_init_check.restype = ctypes.c_int
sys.exit(0 if gtk.gtk_init_check(None, None) else 1)
'''
    result = subprocess.run(
        [sys.executable, '-c', probe], env=environ,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def gui_test_setup(environ=None, has_xvfb=None, display_probe=None):
    """Select an isolated display or a GTK-verified desktop backend."""
    environ = dict(os.environ if environ is None else environ)
    has_xvfb = shutil.which('xvfb-run') is not None if has_xvfb is None else has_xvfb
    if has_xvfb:
        # An inherited Wayland-only selection prevents GTK from using Xvfb.
        environ['GDK_BACKEND'] = 'x11'
        return ['dbus-run-session', '--', 'xvfb-run', '-a'], environ

    display_probe = gtk_display_is_usable if display_probe is None else display_probe
    available = []
    if environ.get('WAYLAND_DISPLAY'):
        available.append('wayland')
    if environ.get('DISPLAY'):
        available.append('x11')

    requested = [backend.strip() for backend in
                 environ.get('GDK_BACKEND', '').split(',') if backend.strip()]
    candidates = []
    for backend in [*requested, *available]:
        if backend in available and backend not in candidates:
            candidates.append(backend)

    for backend in candidates:
        candidate = environ.copy()
        candidate['GDK_BACKEND'] = backend
        if display_probe(candidate):
            # Keep the desktop session bus when using its display. GTK's ATK
            # bridge is connected to that bus; replacing it makes AtkPlug
            # return a null ID and turns an otherwise valid test into a failure.
            return [], candidate

    advertised = ', '.join(available) if available else 'none'
    raise ToolchainError(
        'Engine GUI tests require xvfb-run or a GTK-accessible desktop '
        f'display; advertised backends: {advertised}')


@contextlib.contextmanager
def cache_lock(path):
    with path.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def clone_exact(source, path, parent):
    if not (path / '.git').exists():
        path.mkdir(parents=True, exist_ok=True)
        run(['git', 'init', path], parent)
        run(['git', 'remote', 'add', 'origin', source['repository']], path)
    run(['git', 'fetch', '--depth=1', 'origin', source['revision']], path)
    run(['git', 'checkout', '--detach', source['revision']], path)
    if capture(['git', 'rev-parse', 'HEAD'], path) != source['revision']:
        raise ToolchainError('Fetched source identity mismatch')


def prepare_version_tags(source, sdk, env=None):
    tag = source['version_tag']
    ref = 'refs/tags/' + tag['name']
    existing = capture(['git', 'tag', '--list'], sdk, env).splitlines()
    if any(name != tag['name'] for name in existing):
        raise ToolchainError('Unexpected version tags in owned pinned SDK')
    if not existing:
        run(['git', 'fetch', '--no-tags', '--depth=' + str(tag['fetch_depth']),
             'origin', source['revision'], tag['revision']], sdk, env)
        run(['git', 'update-ref', ref, tag['revision']], sdk, env)
    if capture(['git', 'rev-parse', ref], sdk, env) != tag['revision']:
        raise ToolchainError('Flutter version tag revision mismatch')
    base = capture(['git', 'merge-base', source['revision'], ref], sdk, env)
    count = capture(['git', 'rev-list', '--count', base + '..' + source['revision']], sdk, env)
    if base != tag['merge_base'] or int(count) != tag['commits_past_merge_base']:
        raise ToolchainError('Flutter version ancestry mismatch; do not fetch online latest tags')
    version_file = sdk / 'bin/cache/flutter.version.json'
    if version_file.exists() and json.loads(version_file.read_text(encoding='utf-8')).get('frameworkVersion') != tag['expected_version']:
        version_file.unlink()


def apply_patches(data, sdk):
    if capture(['git', 'rev-parse', 'HEAD'], sdk) != data['flutter']['revision']:
        raise ToolchainError('Wrong Flutter base commit')
    marker = sdk.parent / 'patched.json'
    if marker.exists():
        recorded = json.loads(marker.read_text(encoding='utf-8'))
        actual = capture(['git', 'diff', '--binary', 'HEAD'], sdk)
        if hashlib.sha256(actual.encode()).hexdigest() != recorded['diff_sha256']:
            raise ToolchainError('Interrupted checkout has unexpected source edits')
        return recorded['diff_sha256']
    if capture(['git', 'status', '--porcelain', '--untracked-files=no'], sdk):
        raise ToolchainError('Refusing to patch a dirty source checkout')
    patches = [owned_path(ROOT, e['path']) for boundary in BOUNDARIES for e in data['patches'][boundary]]
    # Validate the dependent series against a temporary index. `git apply
    # --check a.patch b.patch` checks every patch against HEAD independently,
    # which rejects later patches that deliberately extend files created by an
    # earlier patch. The index gives each check the result of its predecessor
    # without mutating the worktree.
    with tempfile.TemporaryDirectory(prefix='gitlama-patch-index-') as temporary:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / 'index'))
        run(['git', 'read-tree', 'HEAD'], sdk, env)
        for patch in patches:
            run(['git', 'apply', '--cached', '--check', patch], sdk, env)
            run(['git', 'apply', '--cached', patch], sdk, env)
    for patch in patches:
        run(['git', 'apply', patch], sdk)
    # New files must participate in diff/provenance without committing them.
    for patch in patches:
        for name in re.findall(r'^\+\+\+ b/(.+)$', patch.read_text(encoding='utf-8'), re.M):
            run(['git', 'add', '--intent-to-add', '--', name], sdk)
    actual = capture(['git', 'diff', '--binary', 'HEAD'], sdk)
    checksum = hashlib.sha256(actual.encode()).hexdigest()
    marker.write_text(json.dumps({'diff_sha256': checksum}) + '\n', encoding='utf-8')
    return checksum


def verify_manifest(entry, key, mode):
    manifest = json.loads((entry / 'manifest.json').read_text(encoding='utf-8'))
    if manifest['identity'] != key or manifest['mode'] != mode or not manifest['files']:
        raise ToolchainError('Cache manifest identity/mode is invalid')
    for name, checksum in manifest['files'].items():
        path = owned_path(entry, name)
        if not path.is_file() or digest(path) != checksum:
            raise ToolchainError(f'Cache artifact missing/corrupt: {name}')
    sdk = entry / 'flutter'
    if capture(['git', 'rev-parse', 'HEAD'], sdk) != manifest['flutter_revision']:
        raise ToolchainError('Cached framework revision is wrong')
    actual = capture(['git', 'diff', '--binary', 'HEAD'], sdk)
    if hashlib.sha256(actual.encode()).hexdigest() != manifest['patched_diff_sha256']:
        raise ToolchainError('Cached source was modified')
    return manifest


def prepare(data, mode, cache, jobs, offline=False):
    key = identity(data, mode)
    entry = cache / key
    cache.mkdir(parents=True, exist_ok=True)
    marker = cache / '.gitlama-sdk-owner'
    if not marker.exists():
        if any(cache.iterdir()):
            raise ToolchainError('Refusing an unowned nonempty engine cache')
        marker.write_text('gitlama-linux-sdk-v1\n', encoding='utf-8')
    if marker.read_text(encoding='utf-8') != 'gitlama-linux-sdk-v1\n':
        raise ToolchainError('Engine cache ownership mismatch')
    if os.environ.get('VPYTHON_BYPASS'):
        raise ToolchainError('VPYTHON_BYPASS is unsupported for engine production')
    with cache_lock(cache / (key + '.lock')):
        if entry.exists():
            try:
                verify_manifest(entry, key, mode)
                return paths(entry, data, mode, key)
            except (ToolchainError, OSError, ValueError, KeyError):
                # Preserve corrupt entries for diagnosis, never reuse bad bytes.
                quarantine = cache / (key + '.corrupt-' + str(time.time_ns()))
                workspace = cache / (key + '.work')
                if entry.is_symlink() and entry.resolve() == workspace.resolve() and workspace.is_dir():
                    entry.unlink()
                    workspace.rename(quarantine)
                else:
                    entry.rename(quarantine)
                print(f'Quarantined corrupt toolchain: {quarantine}', file=sys.stderr)
        if offline:
            raise ToolchainError('Offline cache miss. Prepare this exact mode online first.')
        # Keep absolute GN/Ninja paths stable. Atomically publish a pointer to
        # the verified workspace instead of relocating a built checkout.
        work = cache / (key + '.work')
        work.mkdir(exist_ok=True)
        depot = work / 'depot_tools'
        sdk = work / 'flutter'
        env = os.environ.copy()
        env.update(PATH=str(depot) + os.pathsep + env['PATH'], DEPOT_TOOLS_UPDATE='0',
                   DEPOT_TOOLS_BOOTSTRAP_PYTHON3='1')
        clone_exact(data['depot_tools'], depot, work)
        run([depot / 'ensure_bootstrap'], depot, env)
        if not (sdk / '.git').exists():
            clone_exact(data['flutter'], sdk, work)
        prepare_version_tags(data['flutter'], sdk, env)
        if digest(sdk / 'DEPS') != data['flutter']['deps_file_sha256']:
            raise ToolchainError('Pinned DEPS checksum mismatch')
        # Normal upstream bootstrap. No replacement vpython binary or symlink.
        (sdk / '.gclient').write_text('solutions = ' + repr([{
            'name': '.', 'url': data['flutter']['repository'], 'managed': False,
            'deps_file': 'DEPS', 'custom_deps': {}, 'safesync_url': '',
            'custom_vars': data['custom_vars'],
        }]) + '\n', encoding='utf-8')
        sync_marker = work / 'synced.json'
        if not sync_marker.exists():
            run([depot / 'gclient', 'sync', '--no-history', '--revision',
                 '.@' + data['flutter']['revision'], '--jobs', str(jobs)], sdk, env)
            sync_marker.write_text(json.dumps({'deps_sha256': digest(sdk / 'DEPS')}) + '\n', encoding='utf-8')
        if validate_lock() != data or identity(data, mode) != key:
            raise ToolchainError('Toolchain inputs changed during preparation; restart with the new identity')
        diff_hash = apply_patches(data, sdk)
        src = sdk / 'engine/src'
        config = data['modes'][mode]
        run([src / 'flutter/tools/gn', *config['gn']], src, env)
        output = src / 'out' / config['output']
        run(['ninja', '-C', output, '-j', str(jobs), *config['targets']], src, env)
        run([output / 'flow_unittests'], src, env)
        gui_prefix, gui_env = gui_test_setup(env)
        run(gui_prefix + [output / 'flutter_linux_unittests'], src, gui_env)
        # Initialize matching framework/Dart/host artifacts before promotion.
        run([sdk / 'bin/flutter', '--local-engine=' + config['output'],
             '--local-engine-host=' + config['output'],
             '--local-engine-src-path=' + str(src), '--version'], sdk, env)
        runtime_version = json.loads(capture([sdk / 'bin/flutter', '--local-engine=' + config['output'],
             '--local-engine-host=' + config['output'],
             '--local-engine-src-path=' + str(src), '--version', '--machine'], sdk, env))
        if runtime_version['frameworkRevision'] != data['flutter']['revision'] or runtime_version['frameworkVersion'] != data['flutter']['version_tag']['expected_version']:
            raise ToolchainError('Built framework version disagrees with immutable source/tag ancestry')
        # Hash all selected runtime/header/host artifacts, not Ninja objects.
        required = ['libflutter_linux_gtk.so', 'gen_snapshot', 'icudtl.dat',
                    'impellerc', 'libtessellator.so', 'font-subset', 'flutter_tester', 'args.gn',
                    'flow_unittests', 'flutter_linux_unittests',
                    'lib.unstripped/libflutter_linux_gtk.so']
        files = [sdk / 'bin/cache/flutter_tools.snapshot', sdk / 'bin/cache/engine.stamp',
                 sdk / 'bin/cache/flutter.version.json']
        for name in required:
            path = output / name
            if not path.is_file():
                raise ToolchainError(f'Required engine artifact missing: {name}')
            files.append(path)
        for folder in ['flutter_linux', 'flutter_patched_sdk', 'gen/dart-pkg/sky_engine', 'shader_lib']:
            paths_in_folder = [p for p in (output / folder).rglob('*') if p.is_file()]
            if not paths_in_folder:
                raise ToolchainError(f'Required artifact directory missing: {folder}')
            files.extend(paths_in_folder)
        dart_sdk = sdk / 'bin/cache/dart-sdk'
        dart_sdk_files = [p for p in dart_sdk.rglob('*') if p.is_file()]
        if not dart_sdk_files:
            raise ToolchainError('Matching framework Dart SDK is missing')
        files.extend(dart_sdk_files)
        (work / 'deps-revisions.txt').write_text(capture([depot / 'gclient', 'revinfo', '--actual'], sdk, env) + '\n', encoding='utf-8')
        files.append(work / 'deps-revisions.txt')
        manifest = {'schema_version': 1, 'identity': key, 'mode': mode,
                    'flutter_revision': data['flutter']['revision'],
                    'patched_diff_sha256': diff_hash, 'resize_vsync_abi': data['resize_vsync_abi'],
                    'target': data['target'], 'builder': data['builder'],
                    'host': platform.platform(), 'framework_version': runtime_version,
                    'runtime_acceptance': 'not-run',
                    'tests': {'flow': 'passed', 'linux_embedder': 'passed'},
                    'files': {str(p.relative_to(work)): digest(p) for p in files}}
        if validate_lock() != data or identity(data, mode) != key:
            raise ToolchainError('Toolchain inputs changed during build; refusing cache publication')
        (work / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        published = cache / (key + '.publish')
        published.unlink(missing_ok=True)
        published.symlink_to(work.name, target_is_directory=True)
        published.replace(entry)
        verify_manifest(entry, key, mode)
        return paths(entry, data, mode, key)


def paths(entry, data, mode, key):
    entry = entry.resolve()
    return {'identity': key, 'sdk': str(entry / 'flutter'),
            'engine_src': str(entry / 'flutter/engine/src'),
            'engine': data['modes'][mode]['output'], 'manifest': str(entry / 'manifest.json'),
            'mode': mode}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], default='debug')
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--jobs', type=int, default=int(os.environ.get('GITLAMA_LINUX_JOBS', '2')))
    args = parser.parse_args()
    try:
        data = validate_lock()
        if not 1 <= args.jobs <= 64:
            raise ToolchainError('Build jobs must be in the range 1..64')
        if args.validate_only:
            print(json.dumps({'valid': True, 'identity': identity(data, args.mode),
                              'resize_vsync_abi': data['resize_vsync_abi']}))
            return 0
        if sys.platform != 'linux' or platform.machine() != 'x86_64':
            raise ToolchainError('Preparing this engine requires Linux x86-64')
        cache = Path(os.environ.get('GITLAMA_LINUX_CACHE_DIR',
                     str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) /
                         'gitlama/linux-toolchain'))).expanduser().resolve()
        print(json.dumps(prepare(data, args.mode, cache, args.jobs, args.offline)))
        return 0
    except subprocess.CalledProcessError as error:
        return error.returncode if error.returncode > 0 else 1
    except (ToolchainError, OSError, ValueError, KeyError) as error:
        print(f'Linux toolchain: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
