import importlib.util
from unittest.mock import Mock, patch
import unittest

spec = importlib.util.spec_from_file_location('credential_probe', 'scripts/windows-credential-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class CredentialProbeTest(unittest.TestCase):
    def check(self, written, deleted=True, error=0):
        api = Mock()
        api.CredWriteW.return_value = written
        api.CredDeleteW.return_value = deleted
        with patch.object(probe.os, 'name', 'nt'):
            report = probe.check(api, lambda: error)
        return api, report

    def test_writes_only_a_unique_synthetic_entry_then_deletes_it(self):
        api, report = self.check(True)
        credential = api.CredWriteW.call_args.args[0]._obj
        self.assertEqual(credential.Type, 1)
        self.assertEqual(credential.Persist, 2)
        self.assertEqual(credential.CredentialBlobSize, 32)
        self.assertTrue(credential.TargetName.startswith('GitLama/qualification-capability/'))
        api.CredDeleteW.assert_called_once_with(credential.TargetName, 1, 0)
        self.assertTrue(report['acceptance']['passed'])
        self.assertNotIn(credential.TargetName, str(report))

    def test_logon_failure_is_numeric_and_does_not_delete_anything(self):
        api, report = self.check(False, error=1312)
        self.assertFalse(report['acceptance']['passed'])
        self.assertEqual(report['writeError'], 1312)
        api.CredDeleteW.assert_not_called()
        self.assertEqual(report['acceptance']['failures'], ['credential_write_unavailable'])

    def test_cleanup_failure_does_not_pass_preflight(self):
        _, report = self.check(True, False, error=5)
        self.assertFalse(report['acceptance']['passed'])
        self.assertEqual(report['deleteError'], 5)
        self.assertEqual(report['acceptance']['failures'], ['credential_cleanup_failed'])

    def test_disabled_credential_storage_is_refused_without_a_write(self):
        api = Mock()
        with patch.object(probe.os, 'name', 'nt'):
            result = probe.check(api, lambda: 0, persistence=None)
        self.assertFalse(result['acceptance']['passed'])
        api.CredWriteW.assert_not_called()
        api.CredDeleteW.assert_not_called()
