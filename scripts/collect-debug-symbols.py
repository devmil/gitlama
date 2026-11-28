#!/usr/bin/env python3
"""Retain symbols from the exact packaged build, outside user installers."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

from lib.debug_symbols import SymbolError, canonical, file_record, identity, matches
from lib.package_contract import Version
import shared_git_pin

ROOT = Path(__file__).resolve().parent.parent
# These SDK/vendor payloads are not built by this project. A gap is recorded,
# never represented by an unrelated dSYM or an empty .debug file.
VENDOR_GAPS = {
    'Sparkle': 'vendor_symbols_not_in_resolved_package',
    'Autoupdate': 'vendor_symbols_not_in_resolved_package',
    'Updater': 'vendor_symbols_not_in_resolved_package',
    'D3DCompiler_47.dll': 'microsoft_symbols_external',
    'vcruntime140.dll': 'microsoft_symbols_external',
    'vcruntime140_1.dll': 'microsoft_symbols_external',
    'msvcp140.dll': 'microsoft_symbols_external',
}


# Qt's prebuilt release (libraries, frameworks, plugins and QML module
# plugins) ships without DWARF; its symbols are Qt's own debug archives.
QT_RUNTIME = re.compile(
    r'^(lib)?(Qt6\w*|icu\w+|double-conversion|md4c|b2)(\.so[.0-9]*|\.dll)?$|^Qt\w+$|^opengl32sw\.dll$')


def vendor_gap(relative: str) -> str | None:
    parts = Path(relative).parts
    if 'Sparkle.framework' in parts:
        return 'vendor_symbols_not_in_resolved_package'
    name = Path(relative).name
    if (any(part.endswith('.framework') and part.startswith('Qt') for part in parts)
            or any(part in ('plugins', 'PlugIns', 'qml') for part in parts)
            or QT_RUNTIME.match(name)):
        return 'qt_prebuilt_symbols_external'
    if name.startswith('libswift') and name.endswith('.dylib'):
        return 'apple_swift_runtime_symbols_external'
    return VENDOR_GAPS.get(name)


def command(*args):
    argv = [str(arg) for arg in args]
    argv[0] = shutil.which(argv[0]) or argv[0]
    return subprocess.check_output(argv, text=True).strip()


def qt_version() -> str | None:
    qmake = os.environ.get('QMAKE') or shutil.which('qmake6') or shutil.which('qmake')
    return command(qmake, '-query', 'QT_VERSION') if qmake else None


def provenance(helper: bool) -> dict:
    commit = os.environ.get('GITLAMA_SOURCE_COMMIT') or command('git', '-C', ROOT, 'rev-parse', 'HEAD')
    if len(commit) != 40 or any(c not in '0123456789abcdef' for c in commit):
        raise SymbolError('invalid_source_commit')
    qt = None if helper else qt_version()
    if not helper and not qt:
        raise SymbolError('qt_provenance_missing')
    checkout = (ROOT / '.git').exists()
    if checkout and command('git', '-C', ROOT, 'rev-parse', 'HEAD') != commit:
        raise SymbolError('source_commit_does_not_match_checkout')
    changes = command('git', '-C', ROOT, 'status', '--porcelain') if checkout else ''
    if changes:
        # Name the changed paths: a release build that is unexpectedly marked as
        # development is otherwise only reported later, without a cause.
        print('collect-debug-symbols: checkout has changes, marking the build as development:',
              file=sys.stderr)
        print(changes, file=sys.stderr)
    development = os.environ.get('GITLAMA_DIAGNOSTICS_DEVELOPMENT') == '1' or bool(changes)
    native_tools = {}
    for name, args in [('cc', ['--version'])]:
        if shutil.which(name):
            native_tools[name] = command(name, *args).splitlines()[0]
    if platform.system() == 'Darwin':
        native_tools['xcode'] = command('xcodebuild', '-version')
        native_tools['macos_sdk'] = command('xcrun', '--sdk', 'macosx', '--show-sdk-version')
    return {
        'native_tools': native_tools,
        'host_os_release': platform.release(),
        'build_purpose': 'development' if development else 'release',
        'source_commit': commit,
        'qt_version': qt,
        'rustc': command('rustc', '--version'),
        'python': platform.python_version(),
        'host_system': platform.system(),
        'host_architecture': platform.machine(),
        'shared_git_revision': shared_git_pin.revision(),
    }


@contextmanager
def payload(bundle: Path | None, dmg: Path | None):
    if dmg is None:
        if bundle is None or not bundle.exists():
            raise SymbolError('release_bundle_missing')
        yield bundle
        return
    with tempfile.TemporaryDirectory(prefix='gitlama-symbol-mount-') as folder:
        mount = Path(folder) / 'payload'
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
        try:
            yield mount / 'GitLama.app'
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)


def files(root: Path):
    if root.is_file():
        yield root
    elif root.is_dir():
        for path in sorted(root.rglob('*')):
            if path.is_file() and not path.is_symlink():
                yield path


def symbol_sources(roots: list[Path]):
    seen = set()
    for root in roots:
        for path in files(root):
            # Avoid reading Cargo rlibs, object caches, assets and unrelated
            # debug build trees. DWARF files inside dSYMs have no extension.
            if not (path.suffix.lower() in ('.so', '.dylib', '.dll', '.exe', '.pdb', '.debug', '.symbols')
                    or path.name in ('gitlama', 'GitLama', 'gitlama-remote-helper')
                    or path.parent.name == 'DWARF'):
                continue
            if path.resolve() in seen:
                continue
            seen.add(path.resolve())
            try:
                value = identity(path)
            except SymbolError:
                continue
            if value:
                yield path, value


def retain_symbol(source: Path, value: dict, work: Path, index: int) -> Path:
    if value['format'] == 'elf':
        destination = work / 'symbols' / f'{index}.debug'
        cross = 'aarch64-linux-gnu-objcopy' if 'arm64' in value['ids'] and platform.machine() not in ('arm64', 'aarch64') else 'objcopy'
        objcopy = shutil.which('llvm-objcopy') or shutil.which(cross)
        if not objcopy:
            raise SymbolError('objcopy_missing')
        subprocess.run([objcopy, '--only-keep-debug', str(source), str(destination)], check=True)
        if not identity(destination)['debug']:
            raise SymbolError('empty_elf_debug_file')
        return destination
    if source.parent.name == 'DWARF':
        dsym = source.parents[3]
        if not dsym.name.endswith('.dSYM'):
            raise SymbolError('invalid_dsym_layout')
        destination = work / 'symbols' / f'{index}-{dsym.name}'
        shutil.copytree(dsym, destination, symlinks=True)
        return destination / source.relative_to(dsym)
    destination = work / 'symbols' / str(index) / source.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return destination


def collect(bundle: Path, unit: str, output: Path, roots: list[Path],
            packages: list[Path], *, helper=False) -> Path:
    version = Version.read(ROOT / 'VERSION')
    name = f'GitLama-{version.marketing}-{version.build}-{unit}-diagnostics.tar.gz'
    output.mkdir(parents=True, exist_ok=True)
    destination = output / name
    if destination.exists():
        raise SymbolError('diagnostics_archive_already_exists')
    sources = list(symbol_sources(roots))
    with tempfile.TemporaryDirectory(prefix='gitlama-symbols-') as folder:
        work = Path(folder)
        (work / 'symbols').mkdir()
        (work / 'binaries').mkdir()
        records = []
        for binary in files(bundle):
            if binary.suffix.lower() == '.pdb':
                continue  # WiX excludes these from the installed payload.
            relative = binary.name if bundle.is_file() else binary.relative_to(bundle).as_posix()
            value = identity(binary)
            if value is None:
                continue
            index = len(records)
            stored = work / 'binaries' / relative
            stored.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(binary, stored)
            record = {**file_record(stored, 'binaries/' + relative), 'identity': value}
            helper_parts = relative.split('/')
            if 'remote-helper' in helper_parts and not helper:
                at = helper_parts.index('remote-helper')
                record.update(coverage='separate_helper_archive', helper_unit='helper-' + helper_parts[at + 1])
            else:
                match = next(((path, info) for path, info in sources
                              if info['debug'] and matches(value, info)), None)
                # Rust's macOS default keeps DWARF in object files. Link the
                # dSYM while Cargo's exact build objects still exist.
                if match is None and value['format'] == 'macho':
                    original = next((path for path, info in sources if matches(value, info)), None)
                    if original:
                        generated = work / f'generated-{index}.dSYM'
                        subprocess.run(['xcrun', 'dsymutil', str(original), '-o', str(generated)], check=True, stdout=subprocess.DEVNULL)
                        candidate = generated / 'Contents/Resources/DWARF' / original.name
                        info = identity(candidate)
                        if info and info['debug'] and matches(value, info):
                            match = candidate, info
                if match:
                    symbol = retain_symbol(*match, work, index)
                    symbol_identity = identity(symbol)
                    if not matches(value, symbol_identity):
                        raise SymbolError('retained_symbols_do_not_match_binary')
                    record.update(coverage='native_symbols', symbol_file=symbol.relative_to(work).as_posix(), symbol_identity=symbol_identity)
                elif vendor_gap(relative):
                    record.update(coverage='vendor_symbols_unavailable', reason=vendor_gap(relative))
                else:
                    raise SymbolError(f'required_symbols_missing: {relative}')
            records.append(record)
        if not records:
            raise SymbolError('no_native_payload_found')
        for relative in ('VERSION', 'rust-core/Cargo.toml', 'rust-core/Cargo.lock',
                         'rust-toolchain.toml',
                         'rust-core/remote-helper/COMPATIBILITY',
                         'qml/Meridian/MANIFEST.json'):
            source = ROOT / relative
            if source.is_file():
                target = work / 'provenance' / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
        manifest = {
            'schema': 1, 'unit': unit, 'version': version.marketing, 'build': version.build,
            'provenance': provenance(helper), 'binaries': records,
            'packages': [file_record(path, path.name) for path in packages],
            'files': [file_record(path, path.relative_to(work).as_posix()) for path in files(work)
                      if not path.parts[len(work.parts)].startswith('generated-')],
        }
        (work / 'manifest.json').write_bytes(canonical(manifest))
        temporary = destination.with_suffix('.part')
        try:
            with tarfile.open(temporary, 'w:gz') as archive:
                for path in sorted(files(work)):
                    relative = path.relative_to(work)
                    if relative.parts[0].startswith('generated-'):
                        continue
                    info = archive.gettarinfo(str(path), arcname=relative.as_posix())
                    info.uid = info.gid = 0
                    info.uname = info.gname = ''
                    info.mode = 0o600
                    with path.open('rb') as stream:
                        archive.addfile(info, stream)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit', required=True, choices=['macos-arm64', 'linux-x86_64', 'windows-x86_64',
        'helper-macos-arm64', 'helper-macos-x86_64', 'helper-linux-x86_64', 'helper-linux-arm64'])
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--dmg', type=Path)
    parser.add_argument('--search', type=Path, action='append', default=[])
    parser.add_argument('--package', type=Path, action='append', default=[])
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/diagnostics')
    args = parser.parse_args()
    os.umask(0o077)
    helper = args.unit.startswith('helper-')
    with payload(args.bundle, args.dmg) as bundle:
        print(collect(bundle, args.unit, args.output, args.search, args.package, helper=helper))


if __name__ == '__main__':
    main()
