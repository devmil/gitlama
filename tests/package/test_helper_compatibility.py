from pathlib import Path
import tempfile
import unittest

from scripts import check_helper_compatibility as compatibility


class HelperCompatibilityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        source = self.root / "rust-core" / "remote-helper" / "src"
        source.mkdir(parents=True)
        (source / "main.rs").write_text("fn main() {}\n", encoding="utf-8")
        (self.root / "rust-core" / "src").mkdir()
        (self.root / "rust-core" / "src" / "lib.rs").write_text("// core\n", encoding="utf-8")
        self.file = self.root / "rust-core" / "remote-helper" / "COMPATIBILITY"
        self.file.write_text("version 1\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def record(self) -> str:
        return compatibility.record(self.root, self.file)

    def check(self) -> str:
        return compatibility.check(self.root, self.file)

    def set_version(self, version: int) -> None:
        text = self.file.read_text(encoding="utf-8")
        lines = [f"version {version}" if line.startswith("version ") else line for line in text.splitlines()]
        self.file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_an_unchanged_contract_passes(self) -> None:
        self.record()
        self.assertIn("unchanged", self.check())

    def test_a_changed_contract_needs_a_new_version(self) -> None:
        self.record()
        (self.root / "rust-core" / "remote-helper" / "src" / "main.rs").write_text(
            "fn main() { serve(); }\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(compatibility.CompatibilityError, "Raise 'version'.* to 2"):
            self.check()
        # Recording cannot paper over the change.
        with self.assertRaisesRegex(compatibility.CompatibilityError, "raise 'version'"):
            self.record()
        self.set_version(2)
        with self.assertRaisesRegex(compatibility.CompatibilityError, "stale"):
            self.check()
        self.record()
        self.assertIn("compatibility 2", self.check())

    def test_a_behaviour_bump_without_contract_change_records(self) -> None:
        self.record()
        self.set_version(2)
        with self.assertRaisesRegex(compatibility.CompatibilityError, "stale"):
            self.check()
        self.record()
        self.check()

    def test_code_outside_the_contract_does_not_count(self) -> None:
        self.record()
        (self.root / "rust-core" / "src" / "lib.rs").write_text("// changed\n", encoding="utf-8")
        self.check()

    def test_the_application_and_contract_crates_count(self) -> None:
        sources = [self.root / "rust-core" / crate / "src" / "lib.rs" for crate in ("application", "contract")]
        for source in sources:
            source.parent.mkdir(parents=True)
            source.write_text("// first\n", encoding="utf-8")
        self.record()
        for source in sources:
            source.write_text("// changed\n", encoding="utf-8")
            with self.assertRaisesRegex(compatibility.CompatibilityError, "Raise 'version'"):
                self.check()
            self.set_version(compatibility.read(self.file)[0] + 1)
            self.record()
            self.check()

    def test_a_change_that_cannot_alter_the_helper_keeps_the_version_explicitly(self) -> None:
        self.record()
        (self.root / "rust-core" / "remote-helper" / "src" / "main.rs").write_text(
            "fn main() {}\n// a comment\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(compatibility.CompatibilityError, "--keep-version"):
            self.record()
        compatibility.record(self.root, self.file, keep_version=True)
        self.assertIn("compatibility 1: contract unchanged", self.check())

    def test_the_image_codecs_the_helper_builds_without_do_not_count(self) -> None:
        engine = self.root / "rust-core" / "application" / "src" / "image_decoder" / "engine.rs"
        engine.parent.mkdir(parents=True)
        engine.write_text("// codecs\n", encoding="utf-8")
        self.record()
        engine.write_text("// changed\n", encoding="utf-8")
        self.check()

    def test_line_endings_do_not_count(self) -> None:
        main = self.root / "rust-core" / "remote-helper" / "src" / "main.rs"
        # Exact bytes: write_text would already translate newlines on Windows.
        main.write_bytes(b"fn main() {}\n")
        self.record()
        main.write_bytes(b"fn main() {}\r\n")
        self.check()

    def test_invalid_versions_are_rejected(self) -> None:
        for version in ("0", "01", "x", "1000000"):
            self.file.write_text(f"version {version}\n", encoding="utf-8")
            with self.assertRaises(compatibility.CompatibilityError):
                self.check()

    def test_the_helper_id_pads_the_version(self) -> None:
        self.assertEqual(compatibility.helper_id(3), "0" * 39 + "3")

    def test_the_checkout_is_consistent(self) -> None:
        compatibility.check()

    def write_pin(self, revision: str) -> None:
        (self.root / "rust-core" / "Cargo.toml").write_text(
            "[workspace.dependencies]\n"
            f'devmil-git = {{ git = "https://example.test/devmil-git", rev = "{revision}", features = ["hosting"] }}\n',
            encoding="utf-8",
        )

    def test_a_moved_shared_git_pin_needs_a_decision(self) -> None:
        self.write_pin("a" * 40)
        self.record()
        self.assertIn("unchanged", self.check())
        self.write_pin("b" * 40)
        with self.assertRaisesRegex(compatibility.CompatibilityError, "devmil-git pin moved"):
            self.check()
        with self.assertRaisesRegex(compatibility.CompatibilityError, "--keep-shared-git"):
            self.record()
        # Keeping the version is an explicit choice.
        compatibility.record(self.root, self.file, keep_shared_git=True)
        self.assertIn("unchanged", self.check())
        self.assertIn("shared-git " + "b" * 40, self.file.read_text(encoding="utf-8"))

    def test_raising_the_version_accepts_a_moved_pin(self) -> None:
        self.write_pin("a" * 40)
        self.record()
        self.write_pin("b" * 40)
        self.set_version(2)
        self.record()
        self.assertIn("compatibility 2", self.check())



if __name__ == "__main__":
    unittest.main()
