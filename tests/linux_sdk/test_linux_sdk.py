import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'scripts/linux' / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


sdk = module('sdk-package')
builder = module('prepare-toolchain')
command = module('flutter-command')
engine = module('verify-engine')


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = builder.validate_lock()
        self.identity = builder.identity(self.data, 'profile')
        output = self.data['modes']['profile']['output']
        self.files = {name: b'test artifact' for name in sdk.required('profile', output)}
        self.manifest = {'schema_version': 1, 'identity': self.identity, 'mode': 'profile',
                         'target': self.data['target'], 'engine': output,
                         'flutter_revision': self.data['flutter']['revision'], 'resize_vsync_abi': 1,
                         'producer': {'tests': {'flow': 'passed', 'linux_embedder': 'passed'}},
                         'files': {name: {'size': len(value), 'sha256': hashlib.sha256(value).hexdigest(),
                                          'executable': name.endswith('/dart')}
                                   for name, value in self.files.items()}}

    def archive(self, extra=None):
        output = self.root / 'sdk.tar.gz'
        with tarfile.open(output, 'w:gz') as out:
            for name, value in {**self.files, 'manifest.json': json.dumps(self.manifest).encode()}.items():
                info = tarfile.TarInfo(name)
                info.size = len(value)
                out.addfile(info, io.BytesIO(value))
            if extra:
                out.addfile(extra)
        return output

    def install(self, archive=None, mode='profile'):
        archive = archive or self.archive()
        return sdk.install(archive, sdk.sha(archive), self.root / 'installed', mode)

    def test_fresh_install_relocation_and_corrupt_file_refusal(self):
        self.install()
        old = self.root / 'installed'
        moved = self.root / 'other-host'
        old.rename(moved)
        sdk.verify(moved, self.data, 'profile', self.identity)
        victim = moved / next(iter(self.files))
        victim.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'corrupt'):
            sdk.verify(moved, self.data, 'profile', self.identity)

    def test_wrong_mode_refused(self):
        with self.assertRaisesRegex(ValueError, 'identity/mode'):
            self.install(mode='release')

    def test_missing_frontend_tool_refused(self):
        name = next(n for n in self.files if n.endswith('frontend_server_aot.dart.snapshot'))
        del self.files[name]
        del self.manifest['files'][name]
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            self.install()

    def test_missing_shader_include_refused(self):
        name = next(n for n in self.files if n.endswith('runtime_effect.glsl'))
        del self.files[name]
        del self.manifest['files'][name]
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            self.install()

    def test_changed_archive_checksum_refused(self):
        archive = self.archive()
        with self.assertRaisesRegex(ValueError, 'checksum'):
            sdk.install(archive, '0' * 64, self.root / 'installed', 'profile')

    def test_unowned_destination_preserved(self):
        target = self.root / 'installed'
        target.mkdir()
        (target / 'precious').write_text('keep')
        with self.assertRaises(OSError):
            self.install()
        self.assertEqual((target / 'precious').read_text(), 'keep')

    def test_links_escapes_and_duplicates_refused(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('link', tarfile.SYMTYPE),
                           (next(iter(self.files)), tarfile.REGTYPE)]:
            with self.subTest(name=name):
                info = tarfile.TarInfo(name)
                info.type = kind
                info.linkname = '/etc/passwd' if kind == tarfile.SYMTYPE else ''
                with self.assertRaises(ValueError):
                    self.install(self.archive(info))
                self.assertFalse((self.root / 'installed').exists())

    def test_expanded_budget_enforced(self):
        with patch.object(sdk, 'MAX_EXPANDED', 1):
            with self.assertRaisesRegex(ValueError, 'budget'):
                self.install()

    def test_executable_bit_corruption_refused(self):
        self.install()
        target = self.root / 'installed' / next(n for n in self.files if n.endswith('/dart'))
        target.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'corrupt'):
            sdk.verify(self.root / 'installed', self.data, 'profile', self.identity)


class ContractTest(unittest.TestCase):
    def test_lock_matches_version_and_patch_series(self):
        data = builder.validate_lock()
        self.assertEqual(data['flutter']['version_tag']['expected_version'], json.loads((ROOT / '.fvmrc').read_text())['flutter'])
        self.assertEqual(len(data['patches']['flutter-linux-embedder']), 3)

    def test_framework_pin_drift_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            import shutil
            for name in ['tooling', 'patches']:
                shutil.copytree(ROOT / name, root / name)
            (root / 'pubspec.lock').write_text('')
            (root / '.fvmrc').write_text('{"flutter":"0.0.0"}')
            with self.assertRaisesRegex(builder.ToolchainError, '.fvmrc'):
                builder.validate_lock(root, root / 'tooling/linux/flutter.lock.json')

    def test_wrappers_own_engine_flags_and_match_host(self):
        paths = {'sdk': '/framework', 'engine_src': '/overlay/engine/src', 'engine': 'host_release'}
        args = command.command(paths, ['build', 'linux', '--release'])
        self.assertIn('--local-engine=host_release', args)
        self.assertIn('--local-engine-host=host_release', args)
        self.assertEqual(command.command(paths, ['pub', 'get']), ['/framework/bin/flutter', 'pub', 'get'])
        with self.assertRaisesRegex(ValueError, 'owns'):
            command.command(paths, ['build', 'linux', '--local-engine=stock'])

    def test_replaced_runtime_refused_before_symbol_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = root / 'producer/out/host_profile'
            output.mkdir(parents=True)
            (output / 'libflutter_linux_gtk.so').write_bytes(b'patched')
            bundle = root / 'bundle'
            (bundle / 'lib').mkdir(parents=True)
            (bundle / 'lib/libflutter_linux_gtk.so').write_bytes(b'stock')
            with self.assertRaisesRegex(ValueError, 'does not match'):
                engine.verify(bundle, {'engine_src': str(root / 'producer'), 'engine': 'host_profile'}, 'profile')

    def test_ci_cache_saves_verified_overlay_before_app_tests(self):
        import yaml
        steps = yaml.safe_load((ROOT / '.github/actions/flutter-linux/action.yml').read_text())['runs']['steps']
        restore = next(x for x in steps if x.get('uses') == 'actions/cache/restore@v4')
        save = next(x for x in steps if x.get('uses') == 'actions/cache/save@v4')
        self.assertEqual(restore['with']['key'], save['with']['key'])
        self.assertEqual(save['with']['path'].splitlines(), ['build/linux-sdk', 'build/linux-sdk-symbols'])
        build = next(x for x in steps if x.get('name') == 'Build and test exact engine in pinned builder')
        self.assertEqual(build['if'], "steps.cache.outputs.cache-hit != 'true'")
        self.assertLess(steps.index(next(x for x in steps if x.get('name') == 'Verify portable consumer in fresh directory')), steps.index(save))

    def test_linux_workflows_select_matching_engine_modes(self):
        import yaml
        ci = yaml.safe_load((ROOT / '.github/workflows/ci.yml').read_text())['jobs']
        release = yaml.safe_load((ROOT / '.github/workflows/release.yml').read_text())['jobs']
        for jobs, job, mode in [(ci, 'desktop', 'debug'), (release, 'linux', 'release')]:
            setup = [x for x in jobs[job]['steps'] if x.get('uses') == './.github/actions/flutter-linux']
            self.assertEqual([x['with']['mode'] for x in setup], [mode])
        self.assertEqual(setup[0]['with']['mode'], 'release')


class ElfTest(unittest.TestCase):
    def test_numeric_runtime_floor_and_loader_boundary(self):
        elf = module('verify-artifact')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'lib').mkdir()
            (root / 'lib/engine.so').write_bytes(b'\x7fELFtest')
            def scan(version, loader):
                def reader(args):
                    if '--version-info' in args:
                        return 'Version needs section: Name: GLIBC_' + version
                    return '(RUNPATH) Library runpath: [' + loader + ']'
                return elf.scan(root, reader=reader)
            self.assertEqual(scan('2.9', '$ORIGIN/..')['files'][0]['abi'], {'GLIBC': '2.9'})
            for version, loader in [('2.40', '$ORIGIN'), ('2.9', '/producer/lib'),
                                    ('2.9', '$ORIGIN/../..'), ('2.9', '$ORIGINbad')]:
                with self.subTest(version=version, loader=loader), self.assertRaises(elf.ArtifactError):
                    scan(version, loader)
