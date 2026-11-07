import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import hashlib

spec = importlib.util.spec_from_file_location('overlay', 'scripts/prepare-macos-native-symbols.py')
overlay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(overlay)


class NativeSymbolOverlayTest(unittest.TestCase):
    def test_owned_copy_preserves_cache_and_is_idempotent(self):
        with tempfile.TemporaryDirectory(prefix='native symbols ') as directory:
            root = Path(directory)
            source = root / 'pub-cache/objective_c'
            hook = source / 'hook/build.dart'
            hook.parent.mkdir(parents=True)
            contents = b"    final cFlags = <String>[\n      '-isysroot',\n    ];\n"
            hook.write_bytes(contents)
            config = root / '.dart_tool/package_config.json'
            config.parent.mkdir()
            config.write_text(json.dumps({'packages': [{'name': 'objective_c', 'rootUri': source.as_uri()}]}))
            with patch.object(overlay, 'HOOK_SHA256', hashlib.sha256(contents).hexdigest()):
                overlay.prepare(root)
                overlay.prepare(root)
            self.assertEqual(hook.read_bytes(), contents)
            copied = root / '.dart_tool/gitlama-symbol-sources/objective_c/hook/build.dart'
            self.assertIn(b"'-g'", copied.read_bytes())
            self.assertEqual(json.loads(config.read_text())['packages'][0]['rootUri'], copied.parents[1].as_uri())
            receipt = json.loads((copied.parents[2] / 'receipt.json').read_text())
            self.assertEqual(receipt['patched_hook_sha256'], hashlib.sha256(copied.read_bytes()).hexdigest())
            copied.write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'overlay_changed'):
                overlay.prepare(root)

    def test_changed_dependency_hook_is_refused_before_config_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hook = root / 'cache/hook/build.dart'
            hook.parent.mkdir(parents=True)
            hook.write_text('unreviewed')
            config = root / '.dart_tool/package_config.json'
            config.parent.mkdir()
            config.write_text(json.dumps({'packages': [{'name': 'objective_c', 'rootUri': hook.parents[1].as_uri()}]}))
            original = config.read_bytes()
            with self.assertRaisesRegex(ValueError, 'requires_symbol_review'):
                overlay.prepare(root)
            self.assertEqual(config.read_bytes(), original)
