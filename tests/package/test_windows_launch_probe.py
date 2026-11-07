"""Exercise the real subprocess boundary; runs on Unix and Windows."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("launch_probe", "scripts/windows-launch-probe.py")
probe_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe_module)


class WindowsLaunchProbeTests(unittest.TestCase):
    def run_probe(self, source, *, settings=False, **options):
        with tempfile.TemporaryDirectory(prefix="launch probe ") as directory:
            root = Path(directory)
            script = root / "child with spaces.py"
            script.write_text(source, encoding="utf-8")
            report_path = root / "reports/launch.json"
            settings_path = root / "settings.json" if settings else None
            env = dict(os.environ, PROBE_SETTINGS=str(settings_path))
            accepted = probe_module.probe(
                [sys.executable, str(script)], env, settings_path,
                report_path, "test", **options,
            )
            return accepted, json.loads(report_path.read_text(encoding="utf-8"))

    def test_early_exit_retains_code_and_safe_output_without_pipe_deadlock(self):
        accepted, report = self.run_probe(
            'import sys\n'
            'sys.stdout.write("private content https://secret.invalid/ " * 100000)\n'
            'sys.stderr.write("private path and credentials " * 100000)\n'
            'sys.stderr.write("Could not prepare isolate")\n'
            'sys.exit(17)\n', survival=5,
        )
        self.assertFalse(accepted)
        self.assertEqual(report["failure"], "early_exit")
        self.assertEqual(report["exitCode"], 17)
        self.assertEqual(report["exitCodeHex"], "0x00000011")
        self.assertFalse(report["terminatedByProbe"])
        self.assertGreater(report["stdout"]["bytes"], 100000)
        self.assertIn("flutter_isolate_failed", report["stderr"]["signals"])
        self.assertNotIn("private", json.dumps(report))
        self.assertNotIn("secret.invalid", json.dumps(report))
        self.assertLess(len(json.dumps(report)), 5000)

    def test_settings_timeout_records_live_process_before_cleanup(self):
        accepted, report = self.run_probe('import time; time.sleep(20)', settings=True,
                                          survival=0.1, readiness=0.1)
        self.assertFalse(accepted)
        self.assertEqual(report["failure"], "settings_timeout")
        self.assertIsNone(report["exitCode"])
        self.assertTrue(report["terminatedByProbe"])
        self.assertNotIn("cleanupFailure", report)

    def test_ready_profile_and_executable_argument_with_spaces(self):
        accepted, report = self.run_probe(
            'import os,time\nfrom pathlib import Path\n'
            'Path(os.environ["PROBE_SETTINGS"]).touch()\ntime.sleep(20)',
            settings=True, survival=0.2, readiness=1,
        )
        self.assertTrue(accepted)
        self.assertEqual(report["stage"], "ready")
        self.assertNotIn("crashEvents", report)
        self.assertTrue(report["terminatedByProbe"])

    def test_process_start_failure_still_writes_report(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            self.assertFalse(probe_module.probe(
                [str(Path(directory) / "missing.exe")], os.environ.copy(), None,
                output, "test",
            ))
            report = json.loads(output.read_text())
            self.assertEqual(report["failure"], "process_start_failed")
            self.assertIsInstance(report["osError"], int)


    def test_exit_during_settings_wait_is_distinct_from_timeout(self):
        accepted, report = self.run_probe('import time; time.sleep(0.2)', settings=True,
                                          survival=0.05, readiness=5)
        self.assertFalse(accepted)
        self.assertEqual(report["stage"], "settings")
        self.assertEqual(report["failure"], "exit_before_settings")
        self.assertEqual(report["exitCode"], 0)

    def test_no_settings_gate_for_missing_git_probe(self):
        accepted, report = self.run_probe('import time; time.sleep(20)', survival=0.1)
        self.assertTrue(accepted)
        self.assertEqual(report["stage"], "ready")

    def test_forwarding_codes_are_safe_and_bounded(self):
        accepted, report = self.run_probe(
            'import sys\n'
            'sys.stderr.write("gitlama_forwarding_failure=transport\\n")\n'
            'sys.stderr.write("gitlama_windows_ipc=load_token:io_1312\\n")\n'
            'sys.stderr.write("gitlama_forwarding_failure=private_url\\n")\n'
            'sys.exit(2)\n', survival=5,
        )
        self.assertFalse(accepted)
        self.assertIn("gitlama_forwarding_failure=transport", report["stderr"]["signals"])
        self.assertIn("gitlama_windows_ipc=load_token:io_1312", report["stderr"]["signals"])
        self.assertNotIn("private_url", json.dumps(report))

    def test_cli_preserves_windows_account_paths_and_uses_product_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "profile with spaces"
            args = ["probe", "--executable", sys.executable, "--profile", str(profile),
                    "--repository", directory, "--name", "cold-profile-one",
                    "--output", str(Path(directory) / "report.json")]
            with patch.object(sys, "argv", args), \
                    patch.dict(os.environ, APPDATA="account-roaming", LOCALAPPDATA="account-local"), \
                    patch.object(probe_module, "probe", return_value=True) as run:
                self.assertEqual(probe_module.main(), 0)
            command, env, settings, *_ = run.call_args.args
            self.assertEqual(env["APPDATA"], "account-roaming")
            self.assertEqual(env["LOCALAPPDATA"], "account-local")
            self.assertEqual(env["GITLAMA_PROFILE_ROOT"], str(profile.resolve()))
            self.assertEqual(settings, profile / "settings.json")
            self.assertEqual(command[1], str(Path(directory).resolve()))
