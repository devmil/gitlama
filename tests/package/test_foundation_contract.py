import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class FoundationContractTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
