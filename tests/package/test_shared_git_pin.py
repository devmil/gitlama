import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import shared_git_pin  # noqa: E402

URL = "https://example.test/devmil-git"
PIN = "a" * 40


class SharedGitPinTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.manifest = root / "Cargo.toml"
        self.lockfile = root / "Cargo.lock"
        self.manifest.write_text(
            f'devmil-git = {{ git = "{URL}", rev = "{PIN}", features = ["hosting"] }}\n',
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def lock(self, url: str = URL, revision: str = PIN) -> None:
        self.lockfile.write_text(
            '[[package]]\nname = "devmil-git"\nversion = "0.1.0"\n'
            f'source = "git+{url}?rev={revision}#{revision}"\n',
            encoding="utf-8",
        )

    def test_the_manifest_names_the_pin(self) -> None:
        self.assertEqual(shared_git_pin.pin(self.manifest), (URL, PIN))
        self.assertEqual(shared_git_pin.revision(self.manifest), PIN)

    def test_a_lockfile_at_the_pin_passes(self) -> None:
        self.lock()
        self.assertEqual(shared_git_pin.check(self.manifest, self.lockfile), [])

    def test_a_lockfile_at_another_revision_fails(self) -> None:
        self.lock(revision="b" * 40)
        problems = shared_git_pin.check(self.manifest, self.lockfile)
        self.assertTrue(any("pins aaaaaaaaaaaa" in problem for problem in problems), problems)

    def test_a_lockfile_from_another_repository_fails(self) -> None:
        self.lock(url="https://example.test/other")
        self.assertTrue(shared_git_pin.check(self.manifest, self.lockfile))

    def test_a_path_dependency_is_not_a_pin(self) -> None:
        self.manifest.write_text('devmil-git = { path = "../devmil-git" }\n', encoding="utf-8")
        with self.assertRaises(shared_git_pin.PinError):
            shared_git_pin.revision(self.manifest)

    def test_the_checkout_is_consistent(self) -> None:
        self.assertEqual(shared_git_pin.check(), [])


if __name__ == "__main__":
    unittest.main()
