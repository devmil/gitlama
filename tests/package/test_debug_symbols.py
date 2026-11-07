import copy
import contextlib
import hashlib
import importlib.util
import io
import json
import re
import shlex
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path('scripts').resolve()))
from lib.debug_symbols import SymbolError, canonical, file_record, identity, matches
from lib.package_contract import TARGETS, Version, artifact_name
from lib.release_recovery import STATE_NAME, build_state


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path('scripts') / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


collector = load('symbol_collector', 'collect-debug-symbols.py')
retention = load('symbol_retention', 'retain-debug-symbols.py')
VERSION = Version('0.1.0-beta.54', 56)
COMMIT = 'a' * 40
GUID = uuid.UUID('12345678-1234-5678-9abc-def012345678')


def macho(arch='arm64', debug=False, uid=GUID):
    commands = struct.pack('<II', 0x1b, 24) + uid.bytes
    if debug:
        commands += (struct.pack('<II16s4Q4I', 0x19, 152, b'__DWARF', 0, 1, 0, 1, 0, 0, 1, 0)
                     + struct.pack('<16s16sQQ8I', b'__debug_info', b'__DWARF', 0, 1, 0, 0, 0, 0, 0, 0, 0, 0))
    return struct.pack('<8I', 0xfeedfacf, 0x100000c if arch == 'arm64' else 0x1000007,
                       0, 0xa if debug else 2, 2 if debug else 1, len(commands), 0, 0) + commands


def elf(arch='x86_64', debug=False, build=b'build-id-12345678'):
    # Minimal ELF64 section fixture; parser tests, not native execution proof.
    names = b'\0.shstrtab\0.note.gnu.build-id\0.debug_info\0'
    note = struct.pack('<III', 4, len(build), 3) + b'GNU\0' + build
    note += b'\0' * ((-len(note)) % 4)
    result = bytearray(512)
    result[:16] = b'\x7fELF\x02\x01\x01' + b'\0' * 9
    struct.pack_into('<HHIQQQIHHHHHH', result, 16, 3, 62 if arch == 'x86_64' else 183,
                     1, 0, 0, 256, 0, 64, 0, 0, 64, 4, 1)
    result[64:64 + len(names)] = names
    result[128:128 + len(note)] = note
    result[200] = 1
    for index, values in enumerate([
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        (1, 3, 0, 0, 64, len(names), 0, 0, 1, 0),
        (11, 7, 0, 0, 128, len(note), 0, 0, 4, 0),
        (30, 1, 0, 0, 200, 1 if debug else 0, 0, 0, 1, 0),
    ]):
        struct.pack_into('<IIQQQQIIQQ', result, 256 + 64 * index, *values)
    return bytes(result)


def pe(guid=GUID, age=2):
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<HH', data, 132, 0x8664, 1)
    struct.pack_into('<H', data, 148, 240)
    struct.pack_into('<H', data, 152, 0x20b)
    struct.pack_into('<II', data, 152 + 112 + 48, 0x1000, 28)
    struct.pack_into('<4I', data, 400, 512, 0x1000, 512, 512)
    struct.pack_into('<4I', data, 524, 2, 28, 0x1040, 576)
    data[576:600] = b'RSDS' + guid.bytes_le + struct.pack('<I', age)
    return bytes(data)


def pdb(guid=GUID, age=2):
    data = bytearray(4096 * 5)
    magic = b'Microsoft C/C++ MSF 7.00\r\n\x1aDS\0\0\0'
    data[:len(magic)] = magic
    struct.pack_into('<6I', data, 32, 4096, 1, 5, 16, 0, 2)
    struct.pack_into('<I', data, 8192, 3)
    struct.pack_into('<4I', data, 12288, 2, 0, 28, 4)
    struct.pack_into('<3I', data, 16384, 20000404, 0, age)
    data[16396:16412] = guid.bytes_le
    return bytes(data)


class DebugSymbolsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_macho_thin_fat_uuid_and_dwarf(self):
        binary = identity(self.write('runtime', macho()))
        dsym = identity(self.write('symbols', macho(debug=True)))
        self.assertTrue(matches(binary, dsym))
        self.assertTrue(dsym['debug'])
        self.assertFalse(matches(binary, identity(self.write('wrong', macho(uid=uuid.uuid4())))))
        arm, intel = macho(debug=True), macho('x86_64', True)
        fat = struct.pack('>II', 0xcafebabe, 2)
        fat += struct.pack('>5I', 0x100000c, 0, 48, len(arm), 0)
        fat += struct.pack('>5I', 0x1000007, 0, 48 + len(arm), len(intel), 0)
        symbols = identity(self.write('fat', fat + arm + intel))
        self.assertTrue(matches(binary, symbols))
        self.assertEqual(set(symbols['ids']), {'arm64', 'x86_64'})

    def test_pe_pdb_matches_guid_and_age_not_filename(self):
        binary = identity(self.write('app.exe', pe()))
        good = identity(self.write('unrelated-name.pdb', pdb()))
        self.assertTrue(matches(binary, good))
        self.assertFalse(matches(binary, identity(self.write('old.pdb', pdb(age=1)))))
        self.assertFalse(matches(binary, identity(self.write('other.pdb', pdb(uuid.uuid4())))))
        with self.assertRaises(SymbolError):
            identity(self.write('truncated.exe', pe()[:180]))

    def test_elf_ids_and_dwarf_are_separate_facts(self):
        runtime = identity(self.write('runtime', elf()))
        symbols = identity(self.write('debug', elf(debug=True)))
        self.assertFalse(runtime['debug'])
        self.assertTrue(symbols['debug'])
        self.assertTrue(matches(runtime, symbols))
        self.assertFalse(matches(runtime, identity(self.write('old', elf(build=b'old-build-id-1234')))))

    def test_locally_built_plugin_needs_matching_symbols(self):
        runtime = self.write('bundle/lib/libsuper_native_extensions.so', elf())
        maps = self.write('maps/app.symbols', b'Dart fixture map').parent
        with patch.object(collector, 'provenance', return_value={'source_commit': COMMIT}):
            with self.assertRaisesRegex(SymbolError, 'required_symbols_missing'):
                collector.collect(runtime.parent.parent, 'linux-x86_64', self.root / 'missing-plugin', [], maps, [])
            symbols = self.write('original/libsuper_native_extensions.so', elf(debug=True))
            # Format fixtures run on every host, including macOS without
            # objcopy. Exercise the collector and identity checks while
            # simulating only the external extraction tool. The Linux native
            # round-trip below exercises the actual tool and output.
            def extract_debug(args, *, check):
                self.assertTrue(check)
                self.assertEqual(args[:2], ['fixture-objcopy', '--only-keep-debug'])
                self.assertEqual(Path(args[2]), symbols)
                shutil.copyfile(args[2], args[3])

            with patch.object(collector.shutil, 'which', return_value='fixture-objcopy'), \
                    patch.object(collector.subprocess, 'run', side_effect=extract_debug) as extraction:
                archive = collector.collect(runtime.parent.parent, 'linux-x86_64', self.root / 'plugin', [symbols], maps, [])
            extraction.assert_called_once()
        packet = retention.unpack_verified(archive, self.root / 'plugin-packet')
        self.assertEqual(packet['binaries'][0]['coverage'], 'native_symbols')

    def test_objective_c_framework_uses_hook_symbols_and_refuses_a_gap(self):
        runtime = self.write('bundle/Contents/Frameworks/objective_c.framework/Versions/A/objective_c', macho())
        maps = self.write('maps/app.symbols', b'Dart fixture map').parent
        with patch.object(collector, 'provenance', return_value={'source_commit': COMMIT}):
            with self.assertRaisesRegex(SymbolError, 'required_symbols_missing'):
                collector.collect(self.root / 'bundle', 'macos-arm64', self.root / 'missing-objective', [], maps, [])
            symbols = self.write('hooks/objective_c.dSYM/Contents/Resources/DWARF/objective_c.dylib', macho(debug=True))
            archive = collector.collect(self.root / 'bundle', 'macos-arm64', self.root / 'objective', [self.root / 'hooks'], maps, [])
        packet = retention.unpack_verified(archive, self.root / 'objective-packet')
        record = packet['binaries'][0]
        self.assertEqual(record['coverage'], 'native_symbols')
        self.assertTrue(matches(identity(runtime), record['symbol_identity']))

    def test_linux_compiler_strip_archive_and_addr2line_round_trip(self):
        if sys.platform != 'linux':
            return  # Real Linux qualification; format fixtures above run on every host.
        source = self.write('fixture.c', b'int crash_fixture(void) { return 42; }\nint main(void) { return crash_fixture(); }\n')
        original = self.root / 'original' / 'gitlama-remote-helper'
        original.parent.mkdir()
        subprocess.run(['cc', '-g1', '-Wl,--build-id', str(source), '-o', str(original)], check=True)
        runtime = self.root / 'runtime' / original.name
        runtime.parent.mkdir()
        shutil.copyfile(original, runtime)
        subprocess.run(['strip', '--strip-unneeded', str(runtime)], check=True)
        self.assertTrue(identity(original)['debug'])
        self.assertFalse(identity(runtime)['debug'])
        self.assertTrue(matches(identity(runtime), identity(original)))
        with patch.object(collector, 'provenance', return_value={'source_commit': COMMIT, 'engine_revision': None}):
            archive = collector.collect(runtime, 'helper-linux-x86_64', self.root / 'output', [original], None, [], helper=True)
        unpacked = self.root / 'unpacked'
        manifest = retention.unpack_verified(archive, unpacked)
        retention.validate_unit(manifest, unpacked)
        symbol = unpacked / manifest['binaries'][0]['symbol_file']
        names = subprocess.check_output(['nm', str(original)], text=True)
        address = next(line.split()[0] for line in names.splitlines() if line.endswith(' crash_fixture'))
        mapped = subprocess.check_output(['addr2line', '-e', str(symbol), address], text=True)
        self.assertIn('fixture.c:1', mapped)
        with patch.object(collector, 'provenance', return_value={'source_commit': COMMIT}):
            with self.assertRaisesRegex(SymbolError, 'required_symbols_missing'):
                collector.collect(runtime, 'helper-linux-x86_64', self.root / 'missing', [], None, [], helper=True)

    def test_format_fixture_collection_preserves_dsym_bundles_and_excludes_pdb_payloads(self):
        for mac in (True, False):
            base = self.root / ('mac' if mac else 'windows')
            bundle = base / 'bundle'
            search = base / 'search'
            payload_names = ['GitLama', 'gitlama_core', 'FlutterMacOS'] if mac else ['gitlama.exe', 'gitlama_core.dll', 'flutter_windows.dll']
            for name in payload_names:
                self.write(str((bundle / name).relative_to(self.root)), macho() if mac else pe())
                if mac:
                    dsym = search / (name + '.framework.dSYM')
                    self.write(str((dsym / 'Contents/Resources/DWARF' / name).relative_to(self.root)), macho(debug=True))
                    self.write(str((dsym / 'Contents/Info.plist').relative_to(self.root)), b'fixture plist')
                else:
                    self.write(str((search / (name + '.pdb')).relative_to(self.root)), pdb())
                    self.write(str((bundle / (name + '.pdb')).relative_to(self.root)), pdb())
            dart_path = bundle / 'App.framework/Versions/A/App' if mac else bundle / 'data/app.so'
            self.write(str(dart_path.relative_to(self.root)), macho() if mac else elf())
            for unit in sorted(u for u in retention.UNITS if u.startswith('helper-')):
                arch = 'arm64' if unit.endswith('arm64') else 'x86_64'
                data = macho(arch) if 'macos' in unit else elf(arch)
                self.write(str((bundle / 'remote-helper' / unit[7:] / 'gitlama-remote-helper').relative_to(self.root)), data)
            dart = base / 'dart'
            self.write(str((dart / 'app.symbols').relative_to(self.root)), b'Dart map fixture')
            with patch.object(collector, 'provenance', return_value={'source_commit': COMMIT}):
                archive = collector.collect(bundle, 'macos-arm64' if mac else 'windows-x86_64', base / 'output', [search], dart, [])
            unpacked = base / 'unpacked'
            packet = retention.unpack_verified(archive, unpacked)
            retention.validate_unit(packet, unpacked)
            self.assertEqual(len(packet['binaries']), 8)
            if mac:
                symbol = unpacked / next(b['symbol_file'] for b in packet['binaries'] if b['coverage'] == 'native_symbols')
                self.assertTrue(symbol.parents[3].name.endswith('.dSYM'))
                self.assertTrue((symbol.parents[2] / 'Info.plist').is_file())
            else:
                self.assertFalse(any(b['file'].endswith('.pdb') for b in packet['binaries']))
                self.assertTrue(all(Path(b['symbol_file']).suffix == '.pdb' for b in packet['binaries'] if b['coverage'] == 'native_symbols'))

    def fixtures(self, *, wrong_symbol=False, wrong_helper=False, commit=COMMIT, omit_map=False, purpose='release'):
        packages = self.root / 'packages'
        packages.mkdir(exist_ok=True)
        for target in TARGETS:
            (packages / artifact_name(VERSION, *target)).write_bytes(str(target).encode())
        archives = []
        for unit in sorted(retention.UNITS):
            helper = unit.startswith('helper-')
            mac = 'macos' in unit
            win = 'windows' in unit
            arch = 'arm64' if unit.endswith('arm64') else 'x86_64'
            names = ['gitlama-remote-helper'] if helper else ['GitLama', 'gitlama_core', 'FlutterMacOS'] if mac else ['gitlama.exe', 'gitlama_core.dll', 'flutter_windows.dll'] if win else ['gitlama', 'libgitlama_core.so', 'libflutter_linux_gtk.so']
            runtime = macho(arch) if mac else pe() if win else elf(arch)
            debug = macho(arch, True, uuid.uuid4() if wrong_symbol else GUID) if mac else pdb() if win else elf(arch, True)
            content = {'symbols/native.pdb' if win else 'symbols/native.debug': debug}
            symbol_name = next(iter(content))
            binaries = []
            for name in names:
                relative = 'binaries/' + name
                content[relative] = runtime
                binary = self.write('temporary-runtime', runtime)
                symbols = self.write('temporary-symbols', debug)
                binaries.append({**file_record(binary, relative), 'identity': identity(binary),
                    'coverage': 'native_symbols', 'symbol_file': symbol_name, 'symbol_identity': identity(symbols)})
            if not helper:
                relative = 'binaries/App.framework/Versions/A/App' if mac else 'binaries/data/app.so'
                content[relative] = runtime
                binary = self.write('temporary-dart-runtime', runtime)
                binaries.append({**file_record(binary, relative), 'identity': identity(binary), 'coverage': 'dart_split_debug_info'})
                for target in sorted(u for u in retention.UNITS if u.startswith('helper-')):
                    host_arch = 'arm64' if target.endswith('arm64') else 'x86_64'
                    relative = f'binaries/remote-helper/{target[7:]}/gitlama-remote-helper'
                    data = macho(host_arch, uid=uuid.uuid4() if wrong_helper else GUID) if 'macos' in target else elf(host_arch)
                    content[relative] = data
                    binary = self.write('temporary-helper-runtime', data)
                    binaries.append({**file_record(binary, relative), 'identity': identity(binary), 'coverage': 'separate_helper_archive', 'helper_unit': target})
            if not helper and not omit_map:
                content['dart/app.symbols'] = b'Dart fixture map'
            records = [{'file': name, 'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest()} for name, value in content.items()]
            packet = {'schema': 1, 'unit': unit, 'version': VERSION.marketing, 'build': VERSION.build,
                'provenance': {'source_commit': commit, 'build_purpose': purpose, 'engine_revision': None if helper else 'e' * 40, 'flutter_version': '3.47.5', 'rustc': 'rustc fixture', 'shared_git_revision': 'f' * 40},
                'binaries': binaries, 'files': records,
                'packages': [file_record(packages / artifact_name(VERSION, *target), artifact_name(VERSION, *target))
                             for target in TARGETS if not helper and target[0] == ('macos' if mac else 'windows' if win else 'linux')]}
            content['manifest.json'] = canonical(packet)
            archive = self.root / 'archives' / f'GitLama-{VERSION.marketing}-{VERSION.build}-{unit}-diagnostics.tar.gz'
            archive.parent.mkdir(exist_ok=True)
            with tarfile.open(archive, 'w:gz') as output:
                for name, value in content.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(value)
                    output.addfile(info, io.BytesIO(value))
            archives.append(archive)
        return archives, packages

    def test_complete_private_retention_is_immutable_and_recoverable(self):
        archives, packages = self.fixtures()
        root = self.root / 'private'
        stored = retention.retain(archives, packages, root, VERSION, COMMIT)
        self.assertEqual(retention.retain(archives, packages, root, VERSION, COMMIT), stored)
        (packages / STATE_NAME).write_bytes(canonical(build_state(packages, VERSION)))
        self.assertEqual(retention.verify_retention(root, packages, f'v{VERSION.marketing}-{VERSION.build}'), stored)
        (stored / archives[0].name).write_bytes(b'corrupted')
        with self.assertRaises(SymbolError):
            retention.verify_retention(root, packages, f'v{VERSION.marketing}-{VERSION.build}')

    def test_missing_targets_stale_source_wrong_symbols_and_maps_are_refused(self):
        archives, packages = self.fixtures()
        with self.assertRaisesRegex(SymbolError, 'set_incomplete'):
            retention.verify_set(archives[:-1], packages, VERSION, COMMIT)
        with self.assertRaisesRegex(SymbolError, 'candidate_identity'):
            retention.verify_set(archives, packages, VERSION, 'b' * 40)
        archives, packages = self.fixtures(wrong_symbol=True)
        with self.assertRaisesRegex(SymbolError, 'symbol_identity'):
            retention.verify_set(archives, packages, VERSION, COMMIT)
        archives, packages = self.fixtures(wrong_helper=True)
        with self.assertRaisesRegex(SymbolError, 'bundled_helper_symbols_do_not_match'):
            retention.verify_set(archives, packages, VERSION, COMMIT)
        archives, packages = self.fixtures(purpose='development')
        with self.assertRaisesRegex(SymbolError, 'candidate_identity'):
            retention.verify_set(archives, packages, VERSION, COMMIT)
        archives, packages = self.fixtures(omit_map=True)
        with self.assertRaisesRegex(SymbolError, 'dart_maps_missing'):
            retention.verify_set(archives, packages, VERSION, COMMIT)

    def test_unsafe_archive_members_are_refused_before_extraction(self):
        archive = self.root / 'unsafe.tar.gz'
        with tarfile.open(archive, 'w:gz') as stream:
            for name, data in [('manifest.json', b'{}'), ('../escape', b'bad')]:
                info = tarfile.TarInfo(name)
                info.size = len(data)
                stream.addfile(info, io.BytesIO(data))
        with self.assertRaisesRegex(SymbolError, 'unsafe_diagnostics'):
            retention.unpack_verified(archive, self.root / 'output')
        self.assertFalse((self.root / 'escape').exists())

    def test_release_handoffs_are_private_and_required(self):
        workflow = Path('.github/workflows/release.yml').read_text(encoding='utf-8')
        self.assertEqual(workflow.count('name: Upload private diagnostics handoff'), 5)
        self.assertIn("! -name '*-diagnostics.tar.gz'", workflow)
        self.assertIn('scripts/retain-debug-symbols.py --archives', workflow)
        # The collected set stays a private workflow artifact, never a release asset.
        self.assertIn('name: gitlama-private-diagnostics-', workflow)
        self.assertIn('--dmg "dist/GitLama-', workflow)
        self.assertIn('Windows diagnostics collection failed', workflow)

    def test_collection_verifies_archives_in_the_workflow_download_directory(self):
        workflow = Path('.github/workflows/release.yml').read_text(encoding='utf-8')
        collect = workflow.split('\n  collect:\n', 1)[1].split('\n  publish:\n', 1)[0]
        download = re.search(r'uses: actions/download-artifact@v4\s+with:\s+path: (\S+)', collect).group(1)
        command = shlex.split(next(line.strip().rstrip('\\') for line in collect.splitlines()
                                  if 'python3 scripts/retain-debug-symbols.py --archives' in line))
        archive_input = command[command.index('--archives') + 1]
        archives, packages = self.fixtures()
        # download-artifact without a name creates one directory per handoff.
        for index, archive in enumerate(archives):
            target = self.root / download / f'handoff-{index}'
            target.mkdir(parents=True)
            shutil.move(archive, target / archive.name)
        private = self.root / 'private'
        argv = ['retain-debug-symbols.py', '--archives', str(self.root / archive_input),
                '--packages', str(packages), '--root', str(private), '--source-commit', COMMIT]
        with patch.object(sys, 'argv', argv), patch.object(retention.Version, 'read', return_value=VERSION), \
                contextlib.redirect_stdout(io.StringIO()):
            retention.main()
        index = json.loads(next(private.rglob('index.json')).read_text(encoding='utf-8'))
        self.assertEqual(len(index['archives']), len(retention.UNITS))

    def test_collection_reports_a_missing_archive_directory_before_verifying_the_set(self):
        argv = ['retain-debug-symbols.py', '--archives', str(self.root / 'missing'),
                '--packages', str(self.root / 'packages'), '--root', str(self.root / 'private'),
                '--source-commit', COMMIT]
        with patch.object(sys, 'argv', argv), self.assertRaisesRegex(SymbolError, 'archive_directory_missing'):
            retention.main()


if __name__ == '__main__':
    unittest.main()
