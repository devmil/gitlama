from pathlib import Path
import json
import tempfile
import unittest

from scripts.lib.package_contract import (
    TARGETS,
    Version,
    artifact_name,
    fpm_source_date_epoch,
    leaked_build_path,
    source_date_epoch,
    without_allowed_flutter_build_metadata,
)
from scripts.package import (
    package_linux_tar,
    stage_linux_system,
)


class PackageContractTest(unittest.TestCase):
    def test_target_manifest_matches_packaging_contract(self) -> None:
        manifest = json.loads(Path("packaging/targets.json").read_text(encoding="utf-8"))
        targets = {
            (item["os"], item["arch"], item["format"])
            for item in manifest["targets"]
        }
        self.assertEqual(targets, TARGETS)
        self.assertEqual(manifest["identifier"], "de.devmil.gitlama")
        self.assertEqual(manifest["minimum_git"], "2.39.0")

    def test_windows_installer_rejects_same_version_replacement(self) -> None:
        wix = Path("packaging/windows/gitlama.wxs").read_text(encoding="utf-8")
        validator = Path("scripts/validate-windows-installer.ps1").read_text(encoding="utf-8")
        self.assertIn('AllowSameVersionUpgrades="no"', wix)
        self.assertIn("GITLAMA_MARKETING_VERSION", wix)
        self.assertIn("PreviousMsiPath", validator)
        self.assertIn("Downgrade unexpectedly succeeded", validator)
        self.assertIn(
            '$env:GITLAMA_NATIVE_TEST_TIMEOUT_SECONDS = "180"', validator
        )
        self.assertIn('$env:GITLAMA_NATIVE_TEST_WAIT_SECONDS = "30"', validator)
        self.assertIn("scripts/windows-launch-probe.py", validator)
        self.assertIn("windows-launch-$probeName.json", validator)
        self.assertIn("SoakSeconds", validator)
        self.assertIn("scripts/soak-windows.ps1", validator)
        self.assertIn("Prior qualification MSI uninstall failed", validator)
        self.assertIn("Refusing to overwrite an unrelated installation directory", validator)
        self.assertIn('[xml]$installerSource = Get-Content -Raw -LiteralPath (Join-Path $root "packaging/windows/gitlama.wxs")', validator)
        self.assertIn("[guid]$installerSource.Wix.Package.UpgradeCode", validator)
        self.assertIn("if ($upgradeCode -ne $expectedUpgradeCode)", validator)
        self.assertNotIn("10B18081-CE4C-49A4-B17B-9F7AD69616F4", validator)
        self.assertIn("MsiEnumRelatedProducts($upgradeCode", validator)
        self.assertIn("if ($relatedProducts.Count -ne 1)", validator)
        self.assertIn("Uninstall left the installation directory:", validator)

        soak = Path("scripts/soak-windows.ps1").read_text(encoding="utf-8")
        self.assertIn('GITLAMA_PROFILE_ROOT', soak)
        self.assertIn('Get-CimInstance Win32_Process', soak)
        self.assertIn('core.autocrlf false', soak)
        self.assertIn('repository.refresh', soak)
        self.assertIn('forwardingDeadline = [DateTime]::UtcNow.AddSeconds(45)', soak)
        self.assertIn('"readiness"', soak)
        self.assertIn('"repository open"', soak)
        self.assertIn('function Wait-RepositoryRefresh(', soak)
        self.assertIn('failure (precondition|busy), detail [a-z0-9_]+', soak)
        self.assertIn('busyRefreshRetries = $busyRetries', soak)
        self.assertIn('Wait-RepositoryRefresh $profileRoot $workRoot $application', soak)
        self.assertIn('if ($Application.HasExited)', soak)
        self.assertIn('repository refresh readiness timed out', soak)
        self.assertIn('maximumSteadyRssSlopeKiBPerSecond = 48.0', soak)
        self.assertIn('minimumQuiescentSamples = 5', soak)
        self.assertNotIn('$start.ArgumentList', soak)

    def test_dependency_checker_uses_portable_asset_paths(self) -> None:
        checker = Path("scripts/check_dependencies.py").read_text(encoding="utf-8")
        self.assertIn("path.relative_to(root).as_posix()", checker)

    def test_linux_runner_builds_against_release_image_glib(self) -> None:
        # The Ubuntu 22.04 release image ships GLib 2.72.
        for source in Path("linux/runner").glob("*.[ch]*"):
            self.assertNotIn("G_CONNECT_DEFAULT", source.read_text(encoding="utf-8"), source)

    def test_linux_release_image_installs_project_rust_components(self) -> None:
        dockerfile = Path("tooling/linux-release/Dockerfile").read_text(encoding="utf-8")
        toolchain = Path("rust-toolchain.toml").read_text(encoding="utf-8")
        self.assertIn('components = ["rustfmt", "clippy"]', toolchain)
        self.assertIn('rustup component add --toolchain "${RUST_VERSION}" rustfmt clippy', dockerfile)

    def test_platform_qualifiers_require_flutter_runtime_notices(self) -> None:
        for path in (
            Path("scripts/package.py"),
            Path("scripts/qualify-macos-package.py"),
            Path("scripts/qualify-linux-packages.py"),
            Path("scripts/validate-windows-installer.ps1"),
        ):
            with self.subTest(path=path):
                self.assertIn("NOTICES.Z", path.read_text(encoding="utf-8"))

    def test_reads_exact_version_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            version_file = Path(directory) / "VERSION"
            version_file.write_text("1.2.3-beta.4\n17\n", encoding="utf-8")
            self.assertEqual(Version.read(version_file), Version("1.2.3-beta.4", 17))
            version_file.write_text("1.2.3+local\n17\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                Version.read(version_file)

    def test_names_cover_the_exact_six_artifacts(self) -> None:
        version = Version("1.2.3-beta.4", 17)
        self.assertEqual(
            {artifact_name(version, *target) for target in TARGETS},
            {
                "GitLama-1.2.3-beta.4-17-macos-arm64.dmg",
                "GitLama-1.2.3-beta.4-17-windows-x86_64.msi",
                "GitLama-1.2.3-beta.4-17-linux-x86_64.AppImage",
                "GitLama-1.2.3-beta.4-17-linux-x86_64.tar.gz",
                "gitlama_1.2.3-beta.4-17_amd64.deb",
                "gitlama-1.2.3-beta.4-17.x86_64.rpm",
            },
        )

    def test_platform_versions_preserve_order_and_package_syntax(self) -> None:
        beta = Version("2.7.3-beta.4", 98)
        stable = Version("2.7.3", 99)
        self.assertEqual(beta.windows_msi(), "2.7.98")
        self.assertEqual(stable.windows_msi(), "2.7.99")
        self.assertEqual(beta.apple_bundle_short_version(), "2.7.3.4")
        self.assertEqual(stable.apple_bundle_short_version(), "2.7.3")
        self.assertEqual(
            Version("2.7.3-preview-12.alpha.5", 99).apple_bundle_short_version(),
            "2.7.312.5",
        )
        self.assertEqual(beta.debian_upstream(), "2.7.3~beta.4")
        self.assertEqual(stable.debian_upstream(), "2.7.3")
        self.assertEqual(beta.rpm_fields(), ("2.7.3", "0.beta.4.98"))
        self.assertEqual(stable.rpm_fields(), ("2.7.3", "99"))

    def test_windows_limits_and_reproducible_epoch_fail_closed(self) -> None:
        with self.assertRaises(ValueError):
            Version("256.0.0", 1).windows_msi()
        with self.assertRaises(ValueError):
            Version("1.0.0", 65_536).windows_msi()
        self.assertEqual(source_date_epoch({}), 0)
        self.assertEqual(source_date_epoch({"SOURCE_DATE_EPOCH": "123"}), 123)
        self.assertEqual(fpm_source_date_epoch(0), 1)
        self.assertEqual(fpm_source_date_epoch(123), 123)
        with self.assertRaises(ValueError):
            source_date_epoch({"SOURCE_DATE_EPOCH": "-1"})
        with self.assertRaises(ValueError):
            fpm_source_date_epoch(-1)

    def test_linux_system_stage_contains_launcher_identity_and_legal_inventory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gitlama package test ") as directory:
            temporary = Path(directory)
            source = temporary / "source bundle"
            (source / "lib").mkdir(parents=True)
            (source / "gitlama").write_bytes(b"executable")
            (source / "lib/libgitlama_core.so").write_bytes(b"native")
            stage = temporary / "stage with spaces"

            stage_linux_system(source, stage)

            self.assertEqual(
                (stage / "usr/bin/gitlama").read_text(encoding="utf-8"),
                '#!/bin/sh\nexec /usr/lib/gitlama/gitlama "$@"\n',
            )
            self.assertEqual(
                (stage / "usr/share/applications/de.devmil.gitlama.desktop").read_text(
                    encoding="utf-8"
                ),
                (Path("packaging/linux/de.devmil.gitlama.desktop")).read_text(
                    encoding="utf-8"
                ),
            )
            self.assertTrue((stage / "usr/share/doc/gitlama/LICENSE").is_file())
            self.assertTrue((stage / "usr/share/doc/gitlama/THIRD_PARTY_NOTICES.md").is_file())

    def test_linux_plugins_use_relocatable_runtime_lookup(self) -> None:
        cmake = Path("linux/CMakeLists.txt").read_text(encoding="utf-8")
        self.assertIn("foreach(plugin ${FLUTTER_PLUGIN_LIST})", cmake)
        self.assertIn("BUILD_WITH_INSTALL_RPATH TRUE", cmake)
        self.assertIn('INSTALL_RPATH "$ORIGIN"', cmake)

    def test_linux_qualification_checks_native_package_dependency_names(self) -> None:
        qualifier = Path("scripts/qualify-linux-packages.py").read_text(encoding="utf-8")
        self.assertIn('"deb": ("libgtk-3-0", "libstdc++6", "libc6", "git")', qualifier)
        self.assertIn('"rpm": ("gtk3", "libstdc++", "glibc", "git")', qualifier)
        soak = Path("scripts/soak-linux.py").read_text(encoding="utf-8")
        self.assertIn('GITLAMA_PROFILE_ROOT', soak)
        self.assertIn('GITLAMA_RUNTIME_DIR', soak)
        self.assertIn('core.autocrlf', soak)
        self.assertIn('repository.refresh', soak)
        self.assertIn('/proc', soak)

    def test_linux_path_scan_allows_only_flutter_generated_registrant_uri(self) -> None:
        root = (Path.cwd() / "fixture-source").resolve()
        root_bytes = root.as_posix().encode()
        allowed = (
            f"prefix {root.as_uri()}/.dart_tool/flutter_build/"
            "dart_plugin_registrant.dart suffix"
        ).encode()
        self.assertNotIn(
            root_bytes,
            without_allowed_flutter_build_metadata(allowed, "libapp.so", root),
        )
        self.assertIn(
            root_bytes,
            without_allowed_flutter_build_metadata(allowed, "other.so", root),
        )
        self.assertIn(
            root_bytes,
            without_allowed_flutter_build_metadata(
                f"{root.as_uri()}/lib/main.dart".encode(),
                "libapp.so",
                root,
            ),
        )

    def test_linux_path_scan_ignores_ci_root_names_inside_library_uris(self) -> None:
        root = (Path.cwd() / "fixture-source").resolve()
        uri = b"\x00package:gitlama/app/workspace/history_pane.dart\x00"
        self.assertIsNone(leaked_build_path(uri, root))
        for leaked in (b"/workspace/", b"/builds/", b"/home/runner/"):
            for prefix in (b"\x00", b"file://", b" ", b"="):
                self.assertEqual(
                    leaked_build_path(prefix + leaked + b"src/main.dart", root),
                    leaked.decode(),
                )
        self.assertEqual(
            leaked_build_path(str(root / "lib" / "main.dart").encode(), root),
            str(root),
        )

    def test_portable_tar_is_reproducible_and_has_legal_inventory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gitlama tar test ") as directory:
            temporary = Path(directory)
            source = temporary / "bundle with spaces"
            (source / "lib").mkdir(parents=True)
            executable = source / "gitlama"
            executable.write_bytes(b"executable")
            executable.chmod(0o755)
            (source / "lib/libgitlama_core.so").write_bytes(b"native")
            first = temporary / "first.tar.gz"
            second = temporary / "second.tar.gz"

            package_linux_tar(source, first, 1_700_000_000)
            package_linux_tar(source, second, 1_700_000_000)

            self.assertEqual(first.read_bytes(), second.read_bytes())
            import tarfile

            with tarfile.open(first, "r:gz") as archive:
                names = set(archive.getnames())
                executable_info = archive.getmember("gitlama/gitlama")
            self.assertIn("gitlama/licenses/LICENSE", names)
            self.assertIn("gitlama/licenses/THIRD_PARTY_NOTICES.md", names)
            self.assertEqual(executable_info.mode & 0o111, 0o111)
            self.assertEqual(executable_info.mtime, 1_700_000_000)


if __name__ == "__main__":
    unittest.main()
