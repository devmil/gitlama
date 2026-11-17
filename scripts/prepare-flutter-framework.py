#!/usr/bin/env python3
"""Prepare the shared pinned framework with normal upstream platform artifacts.

Linux product builds must use scripts/linux/flutter.sh and its custom engine.
This helper supplies the same framework to macOS and fast source checks.
"""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def invoke(args, cwd, env):
    subprocess.run(args, cwd=cwd, env=env, stdout=sys.stderr, stderr=sys.stderr, check=True)


def output(args, cwd, env):
    result = subprocess.run(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=sys.stderr, text=True)
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, args)
    return result.stdout.strip()


def main():
    try:
        spec = importlib.util.spec_from_file_location('linux_lock', ROOT / 'scripts/linux/prepare-toolchain.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        source = module.validate_lock()['flutter']
        override = os.environ.get('GITLAMA_FLUTTER_FRAMEWORK_SDK')
        if override:
            sdk = Path(override).expanduser().resolve()
            version = json.loads(output([str(sdk / 'bin/flutter'), '--version', '--machine'], sdk, os.environ.copy()))
            if version['frameworkRevision'] != source['revision'] or version['frameworkVersion'] != source['version_tag']['expected_version']:
                raise ValueError('Selected framework differs from the Linux lock')
            print(json.dumps({'sdk': str(sdk), 'framework_revision': source['revision']}))
            return 0
        cache = Path(os.environ.get('GITLAMA_FLUTTER_FRAMEWORK_CACHE_DIR',
                     str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) /
                         'gitlama/framework'))).expanduser().resolve()
        cache.mkdir(parents=True, exist_ok=True)
        sdk = cache / source['revision']
        env = os.environ.copy()
        # The source checkout computes its own fixed content hash. A caller's
        # ephemeral CI artifact override must not select a different engine.
        env.pop('FLUTTER_PREBUILT_ENGINE_VERSION', None)
        env.pop('FLUTTER_REALM', None)
        with (cache / (source['revision'] + '.lock')).open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if not (sdk / '.git').exists():
                sdk.mkdir(exist_ok=True)
                invoke(['git', 'init', sdk], cache, env)
                invoke(['git', 'remote', 'add', 'origin', source['repository']], sdk, env)
                invoke(['git', 'fetch', '--depth=1', 'origin', source['revision']], sdk, env)
                invoke(['git', 'checkout', '--detach', source['revision']], sdk, env)
            module.prepare_version_tags(source, sdk, env)
            if output(['git', 'rev-parse', 'HEAD'], sdk, env) != source['revision']:
                raise ValueError('Shared framework cache has the wrong revision; use a fresh owned cache')
            if output(['git', 'status', '--porcelain', '--untracked-files=no'], sdk, env):
                raise ValueError('Shared framework was modified; refusing to use it')
            if module.digest(sdk / 'DEPS') != source['deps_file_sha256']:
                raise ValueError('Shared framework DEPS checksum mismatch')
            expected_engine = output([str(sdk / 'bin/internal/content_aware_hash.sh')], sdk, env)
            invoke([str(sdk / 'bin/flutter'), '--version'], sdk, env)
            version = json.loads(output([str(sdk / 'bin/flutter'), '--version', '--machine'], sdk, env))
            if version['frameworkRevision'] != source['revision'] or version['engineContentHash'] != expected_engine or version['frameworkVersion'] != source['version_tag']['expected_version']:
                raise ValueError('Framework/runtime artifact identity mismatch')
            if sys.platform == 'darwin':
                invoke([str(sdk / 'bin/flutter'), 'precache', '--macos'], sdk, env)
            manifest = {'framework_revision': source['revision'], 'engine_content_hash': expected_engine,
                        'host': sys.platform, 'version': version, 'linux_product_engine': False}
            (sdk / 'bin/cache/gitlama-framework.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
            print(json.dumps({'sdk': str(sdk), 'framework_revision': source['revision'],
                              'engine_content_hash': expected_engine}))
        return 0
    except subprocess.CalledProcessError as error:
        return error.returncode if error.returncode > 0 else 1
    except (OSError, ValueError, KeyError) as error:
        print(f'Pinned Flutter framework: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
