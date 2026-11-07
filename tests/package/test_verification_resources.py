import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location('verify_resources', Path('scripts/verify.py'))
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


@unittest.skipUnless(os.name == 'posix', 'POSIX resource admission')
class VerificationResourcesTest(unittest.TestCase):
    def check_limits(self, limits, error=None, expected=None):
        import resource
        with (mock.patch.object(resource, 'getrlimit', side_effect=limits),
              mock.patch.object(resource, 'setrlimit', side_effect=error) as setter):
            if expected:
                with self.assertRaisesRegex(SystemExit, expected):
                    verify.admit_file_descriptors()
            else:
                verify.admit_file_descriptors()
            return setter.call_args_list

    def test_low_soft_limit_is_raised_without_changing_hard_limit(self):
        import resource
        calls = self.check_limits([(256, 8192), (4096, 8192)])
        self.assertEqual(calls, [mock.call(resource.RLIMIT_NOFILE, (4096, 8192))])

    def test_sufficient_and_unlimited_limits_are_untouched(self):
        import resource
        for limits in [(4096, 8192), (8192, 8192), (resource.RLIM_INFINITY, resource.RLIM_INFINITY)]:
            self.assertEqual(self.check_limits([limits]), [])

    def test_unlimited_hard_limit_allows_adjustment(self):
        import resource
        self.check_limits([(256, resource.RLIM_INFINITY), (4096, resource.RLIM_INFINITY)])

    def test_low_hard_limit_is_refused_before_launch(self):
        self.assertEqual(self.check_limits([(256, 1024)], expected='hard_limit_too_low'), [])

    def test_denied_and_unacknowledged_adjustments_are_refused(self):
        self.check_limits([(256, 8192)], error=PermissionError(), expected='adjustment_denied')
        self.check_limits([(256, 8192), (256, 8192)], expected='adjustment_unacknowledged')
        self.check_limits([(256, 8192), (4096, 4096)], expected='adjustment_unacknowledged')

    def test_real_child_inherits_admitted_limit(self):
        code = '''
import resource, subprocess, sys
sys.path.insert(0, 'scripts')
from verify import admit_file_descriptors
soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
resource.setrlimit(resource.RLIMIT_NOFILE, (256, hard))
admit_file_descriptors()
subprocess.run([sys.executable, '-c', 'import resource; assert resource.getrlimit(resource.RLIMIT_NOFILE)[0] >= 4096'], check=True)
assert resource.getrlimit(resource.RLIMIT_NOFILE)[1] == hard
'''
        subprocess.run([sys.executable, '-c', code], check=True)

    def test_windows_does_not_import_posix_resources(self):
        with mock.patch.object(verify.os, 'name', 'nt'):
            verify.admit_file_descriptors()


class InotifyAdmissionTest(unittest.TestCase):
    def test_success_closes_all_probe_instances(self):
        import ctypes
        libc = mock.Mock()
        libc.inotify_init1.side_effect = [10, 11, 12]
        with (mock.patch.object(verify.sys, 'platform', 'linux'),
              mock.patch.object(ctypes, 'CDLL', return_value=libc),
              mock.patch.object(verify.os, 'close') as close):
            verify.admit_inotify_instances(3)
            self.assertEqual(close.call_args_list, [mock.call(10), mock.call(11), mock.call(12)])

    def test_exhaustion_is_distinct_and_closes_partial_probe(self):
        import ctypes
        libc = mock.Mock()
        libc.inotify_init1.side_effect = [10, 11, -1]
        with (mock.patch.object(verify.sys, 'platform', 'linux'),
              mock.patch.object(ctypes, 'CDLL', return_value=libc),
              mock.patch.object(ctypes, 'get_errno', return_value=24),
              mock.patch.object(verify.os, 'close') as close):
            with self.assertRaisesRegex(SystemExit, 'verification_inotify_unavailable errno=24 admitted=2 required=3'):
                verify.admit_inotify_instances(3)
            self.assertEqual(close.call_args_list, [mock.call(10), mock.call(11)])

    def test_other_platforms_do_not_load_libc(self):
        import ctypes
        for platform in ('darwin', 'win32'):
            with (mock.patch.object(verify.sys, 'platform', platform),
                  mock.patch.object(ctypes, 'CDLL') as load):
                verify.admit_inotify_instances()
                load.assert_not_called()

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux inotify boundary')
    def test_real_probe_releases_its_descriptors(self):
        before = len(list(Path('/proc/self/fd').iterdir()))
        verify.admit_inotify_instances(2)
        self.assertEqual(len(list(Path('/proc/self/fd').iterdir())), before)
