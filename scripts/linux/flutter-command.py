#!/usr/bin/env python3
"""Dispatch framework commands with the matching locked local Linux engine."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def clear_foreign_cmake_cache(root, mode):
    """Remove a mode cache generated from a different checkout path."""
    mode_root = root / 'build' / 'linux' / 'x64' / mode
    cache = mode_root / 'CMakeCache.txt'
    if not cache.is_file():
        return False
    match = re.search(r'^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$',
                      cache.read_text(errors='replace', encoding='utf-8'), re.MULTILINE)
    if match is None:
        return False
    expected = (root / 'linux').resolve()
    actual = Path(match.group(1)).resolve()
    if actual == expected:
        return False
    print(f'Removing foreign CMake cache for {mode}: {actual}', file=sys.stderr)
    shutil.rmtree(mode_root)
    return True


def command(paths, args):
    if not args:
        raise ValueError('Expected a Flutter command')
    if any(a.startswith('--local-engine') for a in args):
        raise ValueError('The Linux wrapper owns all local engine arguments')
    modes = [m for m in ['debug', 'profile', 'release'] if '--' + m in args]
    if len(modes) > 1:
        raise ValueError('Select exactly one build mode')
    # Engine flags are global Flutter-tool arguments. Package resolution only
    # needs the pinned framework SDK; passing a local engine there makes pub
    # look for sky_engine in the engine output instead of the SDK artifact cache.
    flags = ['--local-engine=' + paths['engine'],
             '--local-engine-host=' + paths['engine'],
             '--local-engine-src-path=' + paths['engine_src']]
    if args[0] == 'format':
        return [str(Path(paths['sdk']) / 'bin/dart'), *args]
    if args[0] == 'pub':
        return [str(Path(paths['sdk']) / 'bin/flutter'), *args]
    return [str(Path(paths['sdk']) / 'bin/flutter'), *flags, *args]


def main():
    args = sys.argv[1:]
    try:
        if not args:
            raise ValueError('Usage: scripts/linux/flutter.sh COMMAND [ARGS]')
        if args[0] in {'format', 'pub'}:
            result = subprocess.run(
                [sys.executable, str(ROOT / 'scripts/prepare-flutter-framework.py')],
                stdout=subprocess.PIPE, text=True)
            if result.returncode:
                return result.returncode
            sdk = json.loads(result.stdout)['sdk']
            env = os.environ.copy()
            env['PATH'] = str(Path(sdk) / 'bin') + os.pathsep + env['PATH']
            paths = {'sdk': sdk, 'engine': '', 'engine_src': ''}
            return subprocess.call(command(paths, args), env=env)
        mode = next((m for m in ['debug', 'profile', 'release']
                     if '--' + m in args), None)
        if mode is None:
            requested_mode = os.environ.get('GITLAMA_LINUX_MODE')
            if requested_mode in ['debug', 'profile', 'release']:
                mode = requested_mode
        if mode is None:
            mode = 'release' if args[:2] == ['build', 'linux'] else 'debug'
        if args[0] in {'build', 'run'}:
            clear_foreign_cmake_cache(ROOT, mode)
        installed = os.environ.get('GITLAMA_LINUX_SDK_DIR')
        if installed:
            result = subprocess.run([sys.executable, str(HERE / 'sdk-package.py'), 'verify',
                                     '--root', installed, '--mode', mode],
                                    stdout=subprocess.PIPE, text=True)
        else:
            result = subprocess.run([sys.executable, str(HERE / 'prepare-toolchain.py'), '--mode', mode],
                                    stdout=subprocess.PIPE, text=True)
        if result.returncode:
            return result.returncode
        paths = json.loads(result.stdout)
        framework_result = subprocess.run(
            [sys.executable, str(ROOT / 'scripts/prepare-flutter-framework.py')],
            stdout=subprocess.PIPE, text=True)
        if framework_result.returncode:
            return framework_result.returncode
        framework_sdk = json.loads(framework_result.stdout)['sdk']
        paths['sdk'] = framework_sdk
        env = os.environ.copy()
        env['PATH'] = str(Path(paths['sdk']) / 'bin') + os.pathsep + env['PATH']
        return subprocess.call(command(paths, args), env=env)
    except (ValueError, OSError, KeyError) as error:
        print(f'Linux Flutter wrapper: {error}', file=sys.stderr)
        return 64


if __name__ == '__main__':
    sys.exit(main())
