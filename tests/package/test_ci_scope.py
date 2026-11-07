import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ci_scope", ROOT / "scripts/ci_scope.py")
ci_scope = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci_scope)

PUBSPEC = "name: gitlama\nversion: {version}\n\ndependencies:\n  path: ^1.9.0\n"
MANIFEST = (
    '[package]\nname = "gitlama_core"\nversion = "{version}"\n\n'
    '[dependencies]\nserde = {{ version = "1.0" }}\n'
)
LOCK = (
    '[[package]]\nname = "anyhow"\nversion = "1.0.0"\n\n'
    '[[package]]\nname = "gitlama_core"\nversion = "{version}"\n'
    'dependencies = [\n "anyhow",\n]\n'
)


def reader(before: dict[str, str], after: dict[str, str]):
    return lambda side, path: (before if side == "before" else after).get(path)


class CiScopeTest(unittest.TestCase):
    def test_release_preparation_runs_the_source_lane(self) -> None:
        before = {
            "VERSION": "0.1.0-beta.19\n20\n",
            "pubspec.yaml": PUBSPEC.format(version="0.1.0-beta.19+20"),
            "rust-core/Cargo.toml": MANIFEST.format(version="0.1.0-beta.19"),
            "rust-core/Cargo.lock": LOCK.format(version="0.1.0-beta.19"),
        }
        after = {
            "VERSION": "0.1.0-beta.20\n21\n",
            "pubspec.yaml": PUBSPEC.format(version="0.1.0-beta.20+21"),
            "rust-core/Cargo.toml": MANIFEST.format(version="0.1.0-beta.20"),
            "rust-core/Cargo.lock": LOCK.format(version="0.1.0-beta.20"),
        }
        lane, _ = ci_scope.classify(
            [*before, "CHANGELOG.md", "RELEASE_NOTES.md"], reader(before, after)
        )
        self.assertEqual(lane, "source")

    def test_publication_and_website_run_the_source_lane(self) -> None:
        lane, _ = ci_scope.classify(
            [
                "release/metadata.json",
                "release/metadata.json.sig",
                "webfront/_data/releases.json",
                "webfront/appcast.xml",
                "docs/implementation/PROGRESS.md",
            ],
            reader({}, {}),
        )
        self.assertEqual(lane, "source")

    def test_a_dependency_change_beside_the_version_builds(self) -> None:
        for path, before, after in [
            (
                "pubspec.yaml",
                PUBSPEC.format(version="1.0.0+1"),
                PUBSPEC.format(version="1.0.1+2").replace("^1.9.0", "^1.9.1"),
            ),
            (
                "rust-core/Cargo.toml",
                MANIFEST.format(version="1.0.0"),
                MANIFEST.format(version="1.0.1").replace('"1.0"', '"1.1"'),
            ),
            (
                "rust-core/Cargo.lock",
                LOCK.format(version="1.0.0"),
                LOCK.format(version="1.0.1").replace('"1.0.0"', '"1.0.2"', 1),
            ),
        ]:
            with self.subTest(path=path):
                lane, reason = ci_scope.classify(
                    [path], reader({path: before}, {path: after})
                )
                self.assertEqual(lane, "desktop", reason)

    def test_application_paths_build(self) -> None:
        for path in [
            "lib/main.dart",
            "rust-core/src/api.rs",
            "scripts/ci_scope.py",
            ".github/workflows/ci.yml",
            "release/northspline-release-ed25519.pub",
            "THIRD_PARTY_NOTICES.md",
            "LICENSE",
            "docs/design-system/specs/motion.md",
            "assets/brand/icon-64.png",
        ]:
            with self.subTest(path=path):
                lane, _ = ci_scope.classify(["webfront/index.html", path], reader({}, {}))
                self.assertEqual(lane, "desktop")

    def test_an_added_or_removed_version_file_builds(self) -> None:
        lane, _ = ci_scope.classify(["VERSION"], reader({}, {"VERSION": "1.0.0\n1\n"}))
        self.assertEqual(lane, "desktop")

    def test_an_unknown_range_builds(self) -> None:
        zero = "0" * 40
        head = "a" * 40
        self.assertEqual(ci_scope.scope("workflow_dispatch", head, head)[0], "desktop")
        self.assertEqual(ci_scope.scope("push", zero, head)[0], "desktop")
        self.assertEqual(ci_scope.scope("push", "", head)[0], "desktop")
        # Neither commit exists in this repository.
        self.assertEqual(ci_scope.scope("push", "b" * 40, head)[0], "desktop")

    def test_workflow_gates_both_lanes_on_the_scope(self) -> None:
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("scripts/ci_scope.py", workflow)
        self.assertIn("needs.scope.outputs.lane == 'desktop'", workflow)
        self.assertIn("needs.scope.outputs.lane == 'source'", workflow)
        self.assertIn("scripts/verify.py --source", workflow)


if __name__ == "__main__":
    unittest.main()
