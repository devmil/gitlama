from importlib import util
from pathlib import Path
from unittest import mock
import unittest


def load_generator():
    path = Path("scripts/generate-license-notices.py")
    spec = util.spec_from_file_location("gitlama_license_notices", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LicenseNoticeTest(unittest.TestCase):
    def test_resolves_windows_command_shims_before_subprocess(self) -> None:
        generator = load_generator()
        cargo = r"C:\Users\runner\.cargo\bin\cargo.exe"
        with mock.patch.object(generator.shutil, "which", return_value=cargo):
            self.assertEqual(generator.executable("cargo"), cargo)

    def test_preserves_clear_missing_command_failure(self) -> None:
        generator = load_generator()
        with mock.patch.object(generator.shutil, "which", return_value=None):
            self.assertEqual(generator.executable("cargo"), "cargo")


if __name__ == "__main__":
    unittest.main()
