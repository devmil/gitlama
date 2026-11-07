from importlib import util
from pathlib import Path
from tempfile import TemporaryDirectory
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
    def test_converts_windows_drive_file_uri_to_native_path(self) -> None:
        generator = load_generator()
        self.assertEqual(
            generator.file_uri_path_text(
                "file:///C:/WINDOWS/system32/config/systemprofile/"
                "AppData/Local/Pub/Cache/hosted/pub.dev/args-2.7.0",
                windows=True,
            ),
            r"C:\WINDOWS\system32\config\systemprofile\AppData\Local\Pub\Cache\hosted\pub.dev\args-2.7.0",
        )

    def test_converts_windows_unc_and_percent_encoded_file_uris(self) -> None:
        generator = load_generator()
        self.assertEqual(
            generator.file_uri_path_text(
                "file://runner/cache/package%20with%20spaces", windows=True
            ),
            r"\\runner\cache\package with spaces",
        )

    def test_resolves_windows_command_shims_before_subprocess(self) -> None:
        generator = load_generator()
        dart = r"C:\flutter\bin\dart.bat"
        with mock.patch.object(generator.shutil, "which", return_value=dart):
            self.assertEqual(generator.executable("dart"), dart)

    def test_preserves_clear_missing_command_failure(self) -> None:
        generator = load_generator()
        with mock.patch.object(generator.shutil, "which", return_value=None):
            self.assertEqual(generator.executable("dart"), "dart")

    def test_sdk_package_uses_canonical_license_not_platform_cache(self) -> None:
        generator = load_generator()
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / "bin" / "cache" / "pkg" / "sky_engine"
            package.mkdir(parents=True)
            platform_license = package / "LICENSE"
            platform_license.write_text("platform-specific", encoding="utf-8")
            sdk_license = root / "LICENSE"
            sdk_license.write_text("canonical", encoding="utf-8")

            self.assertEqual(
                generator.flutter_notice_files(
                    {"source": "sdk"}, package, sdk_license=sdk_license
                ),
                [sdk_license],
            )

    def test_hosted_package_keeps_its_own_license(self) -> None:
        generator = load_generator()
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / "hosted"
            package.mkdir()
            package_license = package / "LICENSE"
            package_license.write_text("package", encoding="utf-8")
            sdk_license = root / "LICENSE"
            sdk_license.write_text("canonical", encoding="utf-8")

            self.assertEqual(
                generator.flutter_notice_files(
                    {"source": "hosted"}, package, sdk_license=sdk_license
                ),
                [package_license],
            )


if __name__ == "__main__":
    unittest.main()
