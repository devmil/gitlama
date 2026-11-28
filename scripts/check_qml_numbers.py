#!/usr/bin/env python3
"""QML hands every number to Rust as a float: 3 arrives as 3.0, which `as_u64`
and integer fields of serde types reject. Every slot that takes a JSON `Value`
from QML must pass it through `crate::json::integral_numbers` first."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SLOT = re.compile(r'#\[qslot\]\s*\n\s*(?:pub\s+)?fn\s+(\w+)\s*\((.*?)\)\s*(?:->\s*[^{]+)?\{', re.S)


def main() -> int:
    failures = []
    for path in sorted((ROOT / 'rust-core/desktop').glob('*/src/*.rs')):
        source = path.read_text(encoding='utf-8')
        for match in SLOT.finditer(source):
            body = source[match.end():match.end() + 400]
            for name in re.findall(r'(\w+)\s*:\s*Value\b', match.group(2)):
                if f'let {name} = crate::json::integral_numbers({name});' not in body:
                    failures.append(f'{path.relative_to(ROOT)}: {match.group(1)}({name})')
    for failure in failures:
        print(f'slot takes a QML value without integral_numbers: {failure}', file=sys.stderr)
    if failures:
        return 1
    print('QML number decoding passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
