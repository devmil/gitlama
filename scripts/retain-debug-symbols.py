#!/usr/bin/env python3
"""Verify and permanently retain private diagnostics; never publish via update feeds."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile

from lib.debug_symbols import SymbolError, canonical, file_record, identity, matches, sha256
from lib.package_contract import Version, TARGETS, artifact_name
from lib.release_recovery import parse_state, STATE_NAME

ROOT = Path(__file__).resolve().parent.parent
UNITS = {'macos-arm64', 'linux-x86_64', 'windows-x86_64', 'helper-linux-x86_64',
         'helper-linux-arm64', 'helper-macos-arm64', 'helper-macos-x86_64'}


def unpack_verified(archive: Path, destination: Path) -> dict:
    with tarfile.open(archive, 'r:gz') as stream:
        members = []
        total = 0
        for member in stream:
            members.append(member)
            total += member.size
            if len(members) > 10000 or total > 4 * 1024 ** 3:
                raise SymbolError('diagnostics_exceeds_ingestion_budget')
        names = [item.name for item in members]
        if len(names) != len(set(names)) or 'manifest.json' not in names:
            raise SymbolError('duplicate_or_missing_archive_manifest')
        for item in members:
            path = PurePosixPath(item.name)
            if (not item.isfile() or path.is_absolute() or '..' in path.parts
                    or '\\' in item.name or not path.parts or ':' in item.name
                    or path.as_posix() != item.name):
                raise SymbolError('unsafe_diagnostics_archive_member')
        entry = stream.getmember('manifest.json')
        if entry.size > 2 * 1024 * 1024:
            raise SymbolError('diagnostics_manifest_too_large')
        manifest = json.load(stream.extractfile(entry))
        if manifest.get('schema') != 1:
            raise SymbolError('unknown_diagnostics_manifest_schema')
        records = manifest['files']
        expected = {item['file']: item for item in records}
        if len(expected) != len(records) or set(names) != set(expected) | {'manifest.json'}:
            raise SymbolError('diagnostics_inventory_differs')
        for item in members:
            target = destination / item.name
            target.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            with stream.extractfile(item) as source, target.open('wb') as output:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(chunk)
                    output.write(chunk)
            if item.name != 'manifest.json':
                record = expected[item.name]
                if item.size != record['bytes'] or digest.hexdigest() != record['sha256']:
                    raise SymbolError('diagnostics_member_digest_differs')
    return manifest


def validate_unit(manifest: dict, folder: Path):
    inventory = {entry['file'] for entry in manifest['files']}
    binaries = manifest['binaries']
    if not binaries:
        raise SymbolError('diagnostics_native_inventory_empty')
    maps = [p for p in (folder / 'dart').rglob('*.symbols') if p.stat().st_size > 0] if (folder / 'dart').exists() else []
    if not manifest['unit'].startswith('helper-') and not maps:
        raise SymbolError('dart_maps_missing')
    unit = manifest['unit']
    expected_format = 'macho' if 'macos' in unit else 'pe' if 'windows' in unit else 'elf'
    expected_arch = 'arm64' if unit.endswith('arm64') else 'x86_64'
    required = {'gitlama-remote-helper'} if unit.startswith('helper-') else {
        'macos-arm64': {'GitLama', 'gitlama_core'},
        'windows-x86_64': {'gitlama.exe', 'gitlama_core.dll'},
        'linux-x86_64': {'gitlama', 'libgitlama_core.so'},
    }[unit]
    if not unit.startswith('helper-'):
        engine = {'macos-arm64': 'FlutterMacOS', 'windows-x86_64': 'flutter_windows.dll', 'linux-x86_64': 'libflutter_linux_gtk.so'}[unit]
        engines = [b for b in binaries if Path(b['file']).name == engine]
        allowed = {'native_symbols', 'vendor_symbols_unavailable'} if unit == 'linux-x86_64' else {'native_symbols'}
        if len(engines) != 1 or engines[0]['coverage'] not in allowed:
            raise SymbolError('flutter_engine_symbol_coverage_incomplete')
        if not any(b['coverage'] == 'dart_split_debug_info' for b in binaries):
            raise SymbolError('dart_payload_inventory_missing')
        if {b.get('helper_unit') for b in binaries if b['coverage'] == 'separate_helper_archive'} != {u for u in UNITS if u.startswith('helper-')}:
            raise SymbolError('bundled_helper_inventory_incomplete')
    owned = [b for b in binaries if Path(b['file']).name in required]
    if {Path(b['file']).name for b in owned} != required or any(
            b['identity']['format'] != expected_format or expected_arch not in b['identity']['ids']
            or b['coverage'] != 'native_symbols' for b in owned):
        raise SymbolError('first_party_symbol_coverage_incomplete')
    for record in binaries:
        if record['file'] not in inventory or record.get('symbol_file', record['file']) not in inventory:
            raise SymbolError('binary_or_symbol_not_in_inventory')
        binary = folder / record['file']
        if any(record[key] != value for key, value in file_record(binary, record['file']).items()):
            raise SymbolError('binary_record_digest_differs')
        is_dart = record['coverage'] == 'dart_split_debug_info'
        try:
            actual = identity(binary)
        except SymbolError:
            if not is_dart:
                raise
            actual = {'format': 'dart-aot', 'ids': {}, 'debug': False}
        if actual != record['identity']:
            raise SymbolError('binary_identity_differs')
        coverage = record['coverage']
        if coverage == 'native_symbols':
            symbols = identity(folder / record['symbol_file'])
            if not symbols or not symbols['debug'] or not matches(actual, symbols):
                raise SymbolError('symbol_identity_differs')
        elif coverage == 'dart_split_debug_info':
            if not maps:
                raise SymbolError('dart_maps_missing')
        elif coverage == 'vendor_symbols_unavailable':
            from importlib.util import spec_from_file_location, module_from_spec
            spec = spec_from_file_location('debug_collector', ROOT / 'scripts/collect-debug-symbols.py')
            module = module_from_spec(spec)
            spec.loader.exec_module(module)
            if module.vendor_gap(str(Path(record['file']).relative_to('binaries'))) != record.get('reason'):
                raise SymbolError('unapproved_vendor_symbol_gap')
        elif coverage != 'separate_helper_archive':
            raise SymbolError('unknown_symbol_coverage')


def verify_set(archives: list[Path], packages: Path, version: Version, commit: str) -> dict:
    expected = {artifact_name(version, *target) for target in TARGETS}
    package_records = [file_record(packages / name, name) for name in sorted(expected)]
    if any(item['bytes'] <= 0 for item in package_records):
        raise SymbolError('empty_release_package')
    units = {}
    gaps = []
    reported_packages = []
    engines = set()
    toolchains = set()
    with tempfile.TemporaryDirectory(prefix='gitlama-verify-symbols-') as temporary:
        for index, archive in enumerate(archives):
            folder = Path(temporary) / str(index)
            folder.mkdir()
            manifest = unpack_verified(archive, folder)
            unit = manifest['unit']
            if (unit not in UNITS or unit in units or manifest['version'] != version.marketing
                    or manifest['build'] != version.build
                    or manifest['provenance']['source_commit'] != commit
                    or manifest['provenance'].get('build_purpose') != 'release'):
                raise SymbolError('diagnostics_candidate_identity_differs')
            if archive.name != f'GitLama-{version.marketing}-{version.build}-{unit}-diagnostics.tar.gz':
                raise SymbolError('diagnostics_archive_name_differs')
            validate_unit(manifest, folder)
            units[unit] = manifest
            provenance = manifest['provenance']
            toolchain = tuple(provenance.get(key) for key in ('flutter_version', 'rustc', 'shared_git_revision'))
            if None in toolchain:
                raise SymbolError('diagnostics_toolchain_provenance_missing')
            toolchains.add(toolchain)
            if not unit.startswith('helper-'):
                engines.add(manifest['provenance']['engine_revision'])
                reported_packages.extend(manifest['packages'])
            for binary in manifest['binaries']:
                if binary['coverage'] == 'vendor_symbols_unavailable':
                    gaps.append({'unit': unit, 'file': binary['file'], 'reason': binary['reason']})
        if set(units) != UNITS or len(engines) != 1 or None in engines or len(toolchains) != 1:
            raise SymbolError('diagnostics_target_or_engine_set_incomplete')
        if sorted(reported_packages, key=lambda p: p['file']) != package_records:
            raise SymbolError('diagnostics_package_digests_differ')
        for unit in units.values():
            for binary in unit['binaries']:
                if binary['coverage'] == 'separate_helper_archive':
                    helper = units.get(binary['helper_unit'])
                    if not helper or not any(matches(binary['identity'], item['identity']) for item in helper['binaries']):
                        raise SymbolError('bundled_helper_symbols_do_not_match')
    return {'schema': 1, 'version': version.marketing, 'build': version.build,
            'source_commit': commit, 'packages': package_records,
            'archives': sorted([file_record(p, p.name) for p in archives], key=lambda p: p['file']),
            'vendor_symbol_gaps': sorted(gaps, key=lambda p: (p['unit'], p['file']))}


def retain(archives: list[Path], packages: Path, root: Path, version: Version, commit: str) -> Path:
    index = verify_set(archives, packages, version, commit)
    data = canonical(index)
    tag = f'v{version.marketing}-{version.build}'
    parent = root / tag
    parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = parent / hashlib.sha256(data).hexdigest()
    if destination.exists():
        if (destination / 'index.json').read_bytes() != data or any(
                sha256(destination / entry['file']) != entry['sha256'] for entry in index['archives']):
            raise SymbolError('immutable_diagnostics_retention_changed')
        return destination
    temporary = Path(tempfile.mkdtemp(prefix='.pending-', dir=parent))
    try:
        for path in archives:
            shutil.copyfile(path, temporary / path.name)
        (temporary / 'index.json').write_bytes(data)
        temporary.rename(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return destination


def verify_retention(root: Path, packages: Path, tag: str) -> Path | None:
    state = parse_state((packages / STATE_NAME).read_bytes(), tag)
    if tag != f'v{state.version.marketing}-{state.version.build}':
        raise SymbolError('recovery_tag_identity_differs')
    policy = json.loads((ROOT / 'release/diagnostics-policy.json').read_text(encoding='utf-8'))
    if state.version.build < policy['required_from_build']:
        return None
    wanted = [file_record(packages / entry.name, entry.name) for entry in state.artifacts]
    for path in sorted((root / tag).glob('*/index.json')):
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != path.parent.name:
            raise SymbolError('immutable_retention_index_changed')
        index = json.loads(data)
        if index.get('packages') != wanted:
            continue
        names = {f'GitLama-{state.version.marketing}-{state.version.build}-{unit}-diagnostics.tar.gz' for unit in UNITS}
        if {entry['file'] for entry in index['archives']} != names or len(index['archives']) != len(names):
            raise SymbolError('retained_archive_names_differ')
        archives = [path.parent / entry['file'] for entry in index['archives']]
        if any(file_record(p, p.name) != e for p, e in zip(archives, index['archives'])):
            raise SymbolError('retained_archive_digest_differs')
        actual = verify_set(archives, packages, state.version, index['source_commit'])
        if actual != index:
            raise SymbolError('retained_diagnostics_index_differs')
        return path.parent
    raise SymbolError('matching_private_diagnostics_retention_missing')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archives', type=Path)
    parser.add_argument('--packages', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source-commit')
    parser.add_argument('--verify-tag')
    args = parser.parse_args()
    if args.verify_tag:
        found = verify_retention(args.root, args.packages, args.verify_tag)
        print(found if found else 'Legacy build: diagnostics were not retained by its original pipeline.')
    else:
        if not args.archives or not args.source_commit:
            parser.error('--archives and --source-commit are required for collection')
        if not args.archives.is_dir():
            raise SymbolError('diagnostics_archive_directory_missing')
        archives = sorted(args.archives.rglob('*-diagnostics.tar.gz'))
        print(retain(archives, args.packages, args.root, Version.read(ROOT / 'VERSION'), args.source_commit))


if __name__ == '__main__':
    main()
