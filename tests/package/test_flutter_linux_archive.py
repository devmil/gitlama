"""SDK version changes must refresh the identity-bound archive checksum."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('flutter_linux_archive', ROOT / 'scripts/flutter_linux_archive.py')
archive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive)


class FlutterLinuxArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tooling').mkdir()
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.47.8'}))
        self.pin = self.root / 'tooling/flutter-linux.sha256'
        self.pin.write_text('a' * 64 + '  flutter_linux_3.47.8-stable.tar.xz\n')

    def test_matching_archive_returns_its_checksum(self):
        self.assertEqual(archive.read_checksum(self.root), 'a' * 64)

    def test_sdk_bump_rejects_previous_archive(self):
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.47.9'}))
        with self.assertRaisesRegex(ValueError, 'expected flutter_linux_3.47.9'):
            archive.read_checksum(self.root)

    def test_rejects_invalid_and_unbound_checksums(self):
        for content in ['a' * 64, 'not-a-hash  flutter_linux_3.47.8-stable.tar.xz',
                        'a' * 64 + '  ../flutter_linux_3.47.8-stable.tar.xz',
                        'a' * 64 + '  flutter_linux_3.47.8-stable.tar.xz extra']:
            with self.subTest(content=content):
                self.pin.write_text(content)
                with self.assertRaises(ValueError):
                    archive.read_checksum(self.root)

    def test_repository_checksum_matches_sdk_pin(self):
        archive.read_checksum(ROOT)

    def test_qualifier_rejects_mismatch_before_starting_container(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        for name in ['qualify-linux-local.sh', 'flutter_linux_archive.py']:
            (scripts / name).write_bytes((ROOT / 'scripts' / name).read_bytes())
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.47.9'}))
        result = subprocess.run(['bash', str(scripts / 'qualify-linux-local.sh'), '--remote-helper'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('expected flutter_linux_3.47.9', result.stderr)
        self.assertNotIn('container engine', result.stderr.lower())


if __name__ == '__main__':
    unittest.main()
