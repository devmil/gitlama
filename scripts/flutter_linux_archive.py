#!/usr/bin/env python3
"""Validate the pinned Linux SDK archive identity before building an image."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parent.parent


def read_checksum(root: Path) -> str:
    version = json.loads((root / '.fvmrc').read_text(encoding='utf-8'))['flutter']
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid Flutter version in .fvmrc')
    fields = (root / 'tooling/flutter-linux.sha256').read_text(encoding='utf-8').split()
    if len(fields) != 2 or not re.fullmatch(r'[0-9a-f]{64}', fields[0]):
        raise ValueError('Flutter Linux checksum must contain SHA-256 and archive filename')
    expected = f'flutter_linux_{version}-stable.tar.xz'
    if fields[1] != expected:
        raise ValueError(
            f'Flutter Linux checksum is for {fields[1]}, expected {expected}; '
            'refresh tooling/flutter-linux.sha256 from the official Flutter release manifest'
        )
    return fields[0]


def main() -> int:
    try:
        print(read_checksum(ROOT))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
