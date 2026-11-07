from pathlib import Path
import unittest

from scripts.lib.windows_signing import require_signing_results, signing_configuration


class WindowsSigningTest(unittest.TestCase):
    def test_unconfigured_signing_is_explicitly_optional(self) -> None:
        self.assertIsNone(signing_configuration(None, None))

    def test_configured_signing_requires_complete_valid_configuration(self) -> None:
        configured = signing_configuration("a" * 40, "https://timestamp.example.invalid")
        self.assertEqual(configured, ("a" * 40, "https://timestamp.example.invalid"))
        with self.assertRaisesRegex(ValueError, "configured together"):
            signing_configuration("a" * 40, None)
        with self.assertRaisesRegex(ValueError, "unauthenticated HTTPS"):
            signing_configuration("a" * 40, "http://timestamp.example.invalid")

    def test_configured_signing_failure_has_no_unsigned_fallback(self) -> None:
        configured = signing_configuration("a" * 40, "https://timestamp.example.invalid")
        with self.assertRaisesRegex(ValueError, "configured Windows signing"):
            require_signing_results(configured, [True, False])
        self.assertEqual(require_signing_results(configured, [True, True]), "passed")
        self.assertEqual(require_signing_results(None, []), "not-configured")

    def test_workflow_has_no_configured_signing_fallback(self) -> None:
        script = Path("scripts/sign-windows-candidate.ps1").read_text(encoding="utf-8")
        self.assertIn('throw "Configured Windows signing failed"', script)
        self.assertIn('throw "Configured Windows signature verification failed"', script)
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("WINDOWS_CERTIFICATE_THUMBPRINT", workflow)
        self.assertIn("-RequireSignature", workflow)


if __name__ == "__main__":
    unittest.main()
