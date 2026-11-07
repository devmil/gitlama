"""Check the separately pinned marketing master without raster tools."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def check(root=ROOT):
    source = root / 'resources/marketing'
    manifest = json.loads((source / 'manifest.json').read_text(encoding="utf-8"))
    assert len(manifest['source_commit']) == 40
    for name, digest in manifest['masters'].items():
        assert hashlib.sha256((source / name).read_bytes()).hexdigest() == digest, name


if __name__ == '__main__':
    check()
    print('Pinned marketing master matches.')
