from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path('scripts/prepare-linux-diagnostics-handoff.sh').resolve()


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux container handoff')
class LinuxDiagnosticsHandoffTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / 'diagnostics'
        self.directory.mkdir()

    def run_handoff(self):
        return subprocess.run(['bash', str(SCRIPT), str(self.root), str(self.directory)],
                              capture_output=True, text=True, encoding='utf-8')

    def test_private_modes_content_and_reference_owner_are_preserved(self):
        payloads = {}
        for name in ('helper-linux-x86_64', 'helper-linux-arm64'):
            archive = self.directory / f'{name}-diagnostics.tar.gz'
            archive.write_bytes(name.encode())
            archive.chmod(0o644)
            payloads[archive] = archive.read_bytes()
        sentinel = self.root / 'unrelated'
        sentinel.write_bytes(b'unchanged')
        sentinel.chmod(0o640)
        result = self.run_handoff()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        for archive, data in payloads.items():
            self.assertEqual(archive.read_bytes(), data)
            self.assertEqual(stat.S_IMODE(archive.stat().st_mode), 0o600)
            self.assertEqual((archive.stat().st_uid, archive.stat().st_gid),
                             (self.root.stat().st_uid, self.root.stat().st_gid))
        self.assertEqual(sentinel.read_bytes(), b'unchanged')
        self.assertEqual(stat.S_IMODE(sentinel.stat().st_mode), 0o640)

    def test_missing_archives_refuse_handoff(self):
        result = self.run_handoff()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('diagnostics_handoff_archives_missing', result.stderr)

    def test_symlink_archive_is_refused_before_mutating_target(self):
        target = self.root / 'unrelated'
        target.write_bytes(b'unchanged')
        target.chmod(0o640)
        (self.directory / 'fake-diagnostics.tar.gz').symlink_to(target)
        result = self.run_handoff()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('diagnostics_handoff_archive_invalid', result.stderr)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)

    def test_symlink_directory_is_refused(self):
        self.directory.rmdir()
        self.directory.symlink_to(self.root, target_is_directory=True)
        result = self.run_handoff()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('diagnostics_handoff_directory_invalid', result.stderr)

    def test_both_container_lanes_handoff_before_the_host_copy(self):
        wrapper = Path('scripts/qualify-linux-local.sh').read_text(encoding='utf-8')
        call = 'bash scripts/prepare-linux-diagnostics-handoff.sh /work dist/diagnostics'
        self.assertEqual(wrapper.count(call), 2)
        self.assertEqual(wrapper.count('install -d -m 0700 -- "$ROOT/dist/diagnostics"'), 2)
        # Both calls are within the container command, before host enumeration.
        for section in wrapper.split(call)[1:]:
            self.assertIn('for diagnostic in "$STAGE/Flutter/GitLama/dist/diagnostics/"', section)


if __name__ == '__main__':
    unittest.main()
