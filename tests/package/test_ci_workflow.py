import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ci.yml"
SPEC = importlib.util.spec_from_file_location("verify", ROOT / "scripts/verify.py")
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


def step(workflow: str, name: str) -> str:
    """The text of the desktop step called [name], up to the next step."""
    start = workflow.index(f"      - name: {name}\n")
    end = workflow.find("\n      - ", start + 1)
    return workflow[start:] if end < 0 else workflow[start:end]


class CiWorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_every_platform_restores_the_rust_build_cache_before_compiling(self) -> None:
        self.assertIn("CARGO_INCREMENTAL: '0'", self.workflow)
        cache = step(self.workflow, "Restore Rust build cache")
        # Flutter's hook runner hides CARGO_* from the build hook, so the
        # cache must restore the default target path itself.
        self.assertIn("workspaces: rust-core -> target", cache)
        self.assertIn("matrix.platform", cache)
        order = [
            self.workflow.index("      - name: Restore Rust build cache\n"),
            self.workflow.index("      - name: Resolve locked dependencies\n"),
            self.workflow.index("      - name: Validate source\n"),
            self.workflow.index("      - name: Build desktop bundle\n"),
        ]
        self.assertEqual(order, sorted(order))

    def test_only_linux_runs_the_full_gate(self) -> None:
        validate = step(self.workflow, "Validate source")
        self.assertIn("matrix.platform != 'linux' && '--platform' || ''", validate)
        self.assertIn("scripts/verify.py $LANE", validate)
        windows = step(self.workflow, "Validate source on Windows")
        self.assertIn("scripts/verify.py --platform", windows)

    def test_platform_lane_runs_only_the_rust_checks(self) -> None:
        commands = self._commands(["verify.py", "--platform"])
        self.assertTrue(commands)
        for command in commands:
            self.assertTrue(
                command[0] == "cargo" or command[1:] == ("scripts/shared_git_pin.py", "--check"),
                command,
            )
        self.assertIn(("cargo", "test"), {command[:2] for command in commands})
        self.assertIn(("cargo", "clippy"), {command[:2] for command in commands})

    def test_full_gate_keeps_the_platform_lane(self) -> None:
        full = self._commands(["verify.py"])
        for command in self._commands(["verify.py", "--platform"]):
            self.assertIn(command, full)
        self.assertIn(("flutter", "analyze", "--no-fatal-infos"), full)

    def _commands(self, argv: list[str]) -> list[tuple[str, ...]]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".fvmrc").write_text('{"flutter": "3.47.5"}\n', encoding="utf-8")
            with (
                mock.patch.object(verify, "ROOT", root),
                mock.patch.object(verify.os, "chdir"),
                mock.patch.object(
                    verify.subprocess,
                    "check_output",
                    return_value=json.dumps({"frameworkVersion": "3.47.5"}),
                ),
                mock.patch.object(verify, "run") as run,
                mock.patch.object(verify, "use_fvm_flutter"),
                mock.patch.object(verify, "admit_file_descriptors"),
                mock.patch.object(verify, "admit_inotify_instances"),
                mock.patch.object(verify.sys, "argv", argv),
            ):
                verify.main()
        return [
            tuple(str(part) for part in call.args)
            if call.args[0] != verify.sys.executable
            else ("python", *call.args[1:])
            for call in run.call_args_list
        ]


if __name__ == "__main__":
    unittest.main()
