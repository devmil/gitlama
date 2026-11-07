import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class FoundationContractTest(unittest.TestCase):
    def test_macos_uses_the_renderer_fallback_for_every_engine(self) -> None:
        # FlutterDartProject reads the main app bundle even for child engines.
        # Require a plist boolean, not a string that an engine may interpret differently.
        with (ROOT / "macos/Runner/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertIs(info.get("FLTEnableImpeller"), False)

    def test_brand_hashes_survive_windows_line_ending_checkout(self) -> None:
        git = shutil.which("git")
        self.assertIsNotNone(git)
        manifest = json.loads(
            (ROOT / "assets/brand/manifest.json").read_text(encoding="utf-8")
        )

        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "repository"
            checkout = Path(directory) / "checkout"
            repository.mkdir()
            shutil.copyfile(ROOT / ".gitattributes", repository / ".gitattributes")
            for relative_path in manifest:
                destination = repository / relative_path
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative_path, destination)

            def run_git(*arguments: str) -> None:
                subprocess.run(
                    [git, *arguments], cwd=repository, check=True,
                    capture_output=True,
                )

            run_git("init")
            run_git("-c", "core.autocrlf=false", "add", "--all")
            run_git(
                "-c", "core.autocrlf=true", "checkout-index", "--all",
                f"--prefix={checkout.as_posix()}/",
            )
            for relative_path, digest in manifest.items():
                with self.subTest(path=relative_path):
                    self.assertEqual(
                        hashlib.sha256((checkout / relative_path).read_bytes()).hexdigest(),
                        digest,
                    )

    def test_flutter_generated_sources_stay_clean_with_windows_checkout(self) -> None:
        # Flutter generators emit LF even when the runner uses core.autocrlf=true.
        paths = sorted({
            *ROOT.glob("lib/l10n/app_localizations*.dart"),
            *ROOT.glob("linux/flutter/generated*"),
            *ROOT.glob("windows/flutter/generated*"),
            ROOT / "macos/Flutter/GeneratedPluginRegistrant.swift",
        })
        self.assertEqual(len(paths), 10)
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            shutil.copyfile(ROOT / ".gitattributes", repository / ".gitattributes")
            original = {}
            for path in paths:
                relative = path.relative_to(ROOT)
                original[relative] = path.read_bytes().replace(b"\r\n", b"\n")
                destination = repository / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(original[relative])

            def git(*arguments):
                return subprocess.check_output(
                    ["git", "-c", "core.autocrlf=true", *arguments],
                    cwd=repository, stderr=subprocess.PIPE,
                )

            git("init")
            git("add", "--all")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@gitlama.invalid",
                "commit", "--no-gpg-sign", "-m", "Fixture")
            for relative in original:
                (repository / relative).unlink()
            git("checkout-index", "--all")
            for relative, data in original.items():
                with self.subTest(path=relative):
                    self.assertEqual((repository / relative).read_bytes(), data)
                # Model a generator rewriting the same committed source as LF.
                (repository / relative).write_bytes(data)
            self.assertEqual(git("status", "--porcelain"), b"")


if __name__ == "__main__":
    unittest.main()
