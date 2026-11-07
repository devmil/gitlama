"""Exercise the CI dependency steps, including their lockfile recovery guard."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
STEP = WORKFLOW.split("      - name: Resolve locked dependencies\n", 1)[1]
STEP = STEP.split("      - name:", 1)[0].split("        run: |\n", 1)[1]
SCRIPT = textwrap.dedent(STEP)
WINDOWS_STEP = WORKFLOW.split("      - name: Resolve locked dependencies on Windows\n", 1)[1]
WINDOWS_STEP = WINDOWS_STEP.split("      - name:", 1)[0].split("        run: |\n", 1)[1]
# Indentation-free lines; the order checks below do not depend on nesting.
WINDOWS_SCRIPT = "\n".join(line.strip() for line in WINDOWS_STEP.splitlines())


class LockedDependenciesTest(unittest.TestCase):
    def run_step(self, scenario):
        with tempfile.TemporaryDirectory(prefix="gitlama-ci-lock-") as temporary:
            root = Path(temporary)
            tools = root / "bin"
            tools.mkdir()
            for name in ("flutter", "cargo"):
                executable = tools / name
                executable.write_text(
                    f"#!{sys.executable}\n" + textwrap.dedent('''\
                    import json
                    import os
                    from pathlib import Path
                    import sys
                    tool = Path(sys.argv[0]).name
                    args = sys.argv[1:]
                    calls = Path("calls.json")
                    history = json.loads(calls.read_text()) if calls.exists() else []
                    history.append([tool, *args])
                    calls.write_text(json.dumps(history))
                    scenario = os.environ["SCENARIO"]
                    if tool == "cargo":
                        sys.exit(1 if scenario == "cargo-failure" else 0)
                    if args == ["pub", "get"]:
                        if scenario == "drift":
                            Path("pubspec.lock").write_text("changed resolution\\n")
                        sys.exit(1 if scenario == "refresh-failure" else 0)
                    if args == ["pub", "get", "--enforce-lockfile"]:
                        attempts = history.count([tool, *args])
                        good = scenario in ("initial-success", "cargo-failure")
                        good |= attempts == 2 and scenario == "recover"
                        sys.exit(0 if good else 65)
                    '''),
                    encoding="utf-8",
                )
                executable.chmod(0o755)
            (root / "pubspec.lock").write_text("original resolution\n", encoding="utf-8")
            (root / ".dart_tool").mkdir()
            (root / ".dart_tool/package_config.json").write_text('{"packages": []}')
            for command in (
                ["git", "init", "--quiet"],
                ["git", "add", "pubspec.lock"],
                ["git", "-c", "user.name=CI fixture", "-c", "user.email=ci@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture"],
            ):
                subprocess.run(command, cwd=root, check=True, capture_output=True)
            result = subprocess.run(
                ["bash", "-c", SCRIPT], cwd=root,
                env={**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                     "SCENARIO": scenario},
                text=True, capture_output=True,
            )
            return result, json.loads((root / "calls.json").read_text())

    def test_initial_success_does_not_run_unlocked_resolution(self):
        result, calls = self.run_step("initial-success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(["flutter", "pub", "get"], calls)
        cargo = [call for call in calls if call[0] == "cargo"]
        # One fetch for every platform: the license inventory reads all
        # packages offline, including ones a single-target fetch skips.
        self.assertEqual(len(cargo), 1)
        self.assertNotIn("--target", cargo[0])

    def test_unchanged_lockfile_can_recover_with_one_locked_retry(self):
        result, calls = self.run_step("recover")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.count(["flutter", "pub", "get", "--enforce-lockfile"]), 2)
        self.assertEqual(calls.count(["flutter", "pub", "get"]), 1)

    def test_changed_lockfile_fails_before_retry_or_cargo(self):
        result, calls = self.run_step("drift")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls.count(["flutter", "pub", "get", "--enforce-lockfile"]), 1)
        self.assertFalse(any(call[0] == "cargo" for call in calls))

    def test_repeated_resolution_failure_is_not_accepted(self):
        for scenario in ("retry-failure", "refresh-failure"):
            with self.subTest(scenario=scenario):
                result, calls = self.run_step(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls.count(["flutter", "pub", "get", "--enforce-lockfile"]), 2)
                self.assertFalse(any(call[0] == "cargo" for call in calls))

    def test_first_cargo_fetch_failure_stops_the_step(self):
        result, calls = self.run_step("cargo-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sum(call[0] == "cargo" for call in calls), 1)


class WindowsLockedDependenciesTest(unittest.TestCase):
    """PowerShell is not available on every verifier, so check the step order."""

    def assert_in_order(self, *lines):
        start = 0
        for line in lines:
            index = WINDOWS_SCRIPT.find(line, start)
            self.assertNotEqual(index, -1, f"missing or out of order: {line}")
            start = index + len(line)

    def test_locked_failure_refreshes_guards_the_lockfile_and_retries_once(self):
        self.assert_in_order(
            "flutter pub get --enforce-lockfile\nif ($LASTEXITCODE -ne 0) {",
            "\nflutter pub get\n",
            "git diff --exit-code --quiet -- pubspec.lock\n"
            "if ($LASTEXITCODE -ne 0) { throw ",
            "\nflutter pub get --enforce-lockfile\n"
            "if ($LASTEXITCODE -ne 0) { throw ",
            "}\ncargo fetch",
        )
        self.assertEqual(WINDOWS_SCRIPT.count("flutter pub get --enforce-lockfile"), 2)

    def test_every_cargo_fetch_is_checked(self):
        fetches = WINDOWS_SCRIPT.count("cargo fetch ")
        self.assertEqual(fetches, 1)
        for chunk in WINDOWS_SCRIPT.split("cargo fetch ")[1:]:
            self.assertIn("if ($LASTEXITCODE -ne 0) { throw ", chunk.split("\n", 2)[1])
