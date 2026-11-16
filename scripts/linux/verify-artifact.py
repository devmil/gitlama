#!/usr/bin/env python3
"""Inspect every ELF in an extracted Linux bundle and enforce numeric ABI limits.

A static scan does not establish toolkit loading, native helper startup, GPU
support or installed GUI acceptance. Those require a baseline runtime launch.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

DEFAULT_LIMITS = {'GLIBC': '2.35', 'GLIBCXX': '3.4.30', 'CXXABI': '1.3.13'}


class ArtifactError(Exception):
    pass


def version(value):
    if not re.fullmatch(r'\d+(\.\d+)*', value):
        raise ArtifactError(f'Invalid numeric ABI version: {value}')
    return tuple(int(part) for part in value.split('.'))


def requirements(output):
    # Only .gnu.version_r requirements count. Exported/provided symbol versions
    # from .gnu.version_d are not an application's runtime requirements.
    needs = output.split('Version needs section', 1)
    if len(needs) == 1:
        return {}
    text = needs[1].split('Version definition section', 1)[0]
    found = {}
    for family, number in re.findall(r'\bName:\s+(GLIBCXX|GLIBC|CXXABI)_([\d.]+)\b', text):
        if family not in found or version(number) > version(found[family]):
            found[family] = number
    return found


def inspect(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise ArtifactError(f'ELF inspection failed with exit {result.returncode}')
    return result.stdout


def elf_files(root):
    root = root.resolve()
    found = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            if not path.resolve().is_relative_to(root):
                raise ArtifactError(f'Bundle symlink leaves its owner: {path.relative_to(root)}')
            if not path.exists():
                raise ArtifactError(f'Broken bundle symlink: {path.relative_to(root)}')
            continue
        if path.is_file():
            try:
                with path.open('rb') as stream:
                    if stream.read(4) == b'\x7fELF':
                        found.append(path)
            except OSError as error:
                raise ArtifactError(f'Cannot read bundle file: {path.relative_to(root)}') from error
    if not found:
        raise ArtifactError('Bundle contains no ELF binaries')
    return found


def scan(root, limits=None, reader=inspect):
    root = root.resolve()
    limits = limits or DEFAULT_LIMITS
    report = []
    for path in elf_files(root):
        needed = requirements(reader(['readelf', '--version-info', '--wide', str(path)]))
        for family, number in needed.items():
            if family not in limits or version(number) > version(limits[family]):
                raise ArtifactError(f'{path.relative_to(root)} needs {family}_{number}, above runtime floor')
        dynamic = reader(['readelf', '--dynamic', '--wide', str(path)])
        dependencies = re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', dynamic)
        if any('/' in name for name in dependencies):
            raise ArtifactError(f'{path.relative_to(root)} has a nonrelocatable dependency name')
        rpaths = re.findall(r'\((?:RUNPATH|RPATH)\).*?\[([^\]]+)\]', dynamic)
        for rpath in rpaths:
            for element in rpath.split(':'):
                if not element:
                    continue
                origin = next((token for token in ('$ORIGIN', '${ORIGIN}')
                               if element == token or element.startswith(token + '/')), None)
                if origin is None:
                    raise ArtifactError(f'{path.relative_to(root)} has a nonrelocatable loader path')
                target = (path.parent / element[len(origin):].lstrip('/')).resolve()
                if not target.is_relative_to(root):
                    raise ArtifactError(f'{path.relative_to(root)} loader path leaves its bundle')
        sha = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                sha.update(block)
        report.append({'path': str(path.relative_to(root)), 'sha256': sha.hexdigest(),
                       'abi': needed, 'needed': dependencies, 'loader_paths': rpaths})
    return {'schema_version': 1, 'limits': limits, 'files': report,
            'baseline_runtime_launch': 'not-run'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path, help='Already extracted bundle directory')
    for family, limit in DEFAULT_LIMITS.items():
        parser.add_argument('--' + family.lower(), default=limit)
    args = parser.parse_args()
    try:
        if not args.bundle.is_dir():
            raise ArtifactError('Expected an extracted bundle directory')
        limits = {family: getattr(args, family.lower()) for family in DEFAULT_LIMITS}
        for limit in limits.values():
            version(limit)
        print(json.dumps(scan(args.bundle, limits), indent=2))
        return 0
    except (ArtifactError, OSError) as error:
        print(f'Linux artifact: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
