from __future__ import annotations

import ast
from datetime import date
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from scripts import verify
from scripts.lib.package_contract import Version
from scripts.lib.release_git import (
    create_annotated_tag,
    plan,
    require_clean,
)
from scripts.lib.release_prepare import (
    bumped,
    prepare_updates,
    promoted_document,
    released_notes,
    write_atomic,
)
from scripts.lib.release_recovery import build_state, parse_state, recover
from scripts.lib.package_contract import TARGETS, artifact_name


def command(root: Path, *arguments: str) -> str:
    return subprocess.check_output(arguments, cwd=root, text=True).strip()


def fixture(root: Path, version: Version = Version("1.2.3", 7)) -> None:
    (root / "rust-core").mkdir()
    (root / "VERSION").write_text(f"{version.marketing}\n{version.build}\n", encoding="utf-8")
    (root / "pubspec.yaml").write_text(
        f"name: gitlama\nversion: {version.marketing}+{version.build}\n",
        encoding="utf-8",
    )
    (root / "rust-core/Cargo.toml").write_text(
        f'[package]\nname = "gitlama_core"\nversion = "{version.marketing}"\nedition = "2021"\n',
        encoding="utf-8",
    )
    (root / "rust-core/Cargo.lock").write_text(
        f'[[package]]\nname = "gitlama_core"\nversion = "{version.marketing}"\n',
        encoding="utf-8",
    )
    document = "# Document\n\n## Unreleased Stable\n\n- Stable item.\n\n## Unreleased Beta\n\n- Beta item.\n"
    (root / "CHANGELOG.md").write_text(document, encoding="utf-8")
    (root / "RELEASE_NOTES.md").write_text(document, encoding="utf-8")


def initialize_git(root: Path) -> None:
    subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Release Test"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "release@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(["git", "commit", "--quiet", "-m", "fixture"], cwd=root, check=True)


class ReleasePrepareTest(unittest.TestCase):
    def test_manifest_notes_use_only_the_released_version(self) -> None:
        document = (
            "# Notes\n\n"
            "## Unreleased Beta\n\n- Not released yet.\n\n"
            "## [1.2.3-beta.2] - 2026-09-27\n\n- Current note.\n\n"
            "## [1.2.3-beta.1] - 2026-09-26\n\n"
            + "".join(f"- Old note {index}.\n" for index in range(70))
        )
        self.assertEqual(
            released_notes(document, Version("1.2.3-beta.2", 7)),
            ("Current note.",),
        )
        with self.assertRaisesRegex(ValueError, "no unique notes"):
            released_notes(document, Version("1.2.3-beta.3", 8))

    def test_signing_candidate_is_bash_32_safe(self) -> None:
        if os.name == "nt":
            self.skipTest("publish-candidate.sh runs on the macOS collection host")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_python = fake_bin / "python3"
            fake_python.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "command_name=\"$2\"\n"
                "output=\"\"\n"
                "signature=\"\"\n"
                "while [[ $# -gt 0 ]]; do\n"
                "  case \"$1\" in\n"
                "    --output) output=\"$2\"; shift 2 ;;\n"
                "    --signature) signature=\"$2\"; shift 2 ;;\n"
                "    *) shift ;;\n"
                "  esac\n"
                "done\n"
                "if [[ \"$command_name\" == public-key ]]; then\n"
                "  cp \"$GITLAMA_TEST_PUBLIC_KEY\" \"$output\"\n"
                "elif [[ \"$command_name\" == manifest ]]; then\n"
                "  printf '{}\\n' >\"$output\"\n"
                "elif [[ \"$command_name\" == sign ]]; then\n"
                "  printf 'signature\\n' >\"$signature\"\n"
                "fi\n",
                encoding="utf-8",
            )
            fake_python.chmod(0o755)
            candidate = root / "candidate"
            candidate.mkdir()
            # The macOS updater installs this package; signing verifies it.
            (candidate / "GitLama-0.1.0-beta.8-9-macos-arm64.dmg").write_bytes(b"update")
            key = root / "release-key.pem"
            key.write_text("test key\n", encoding="utf-8")
            key.chmod(0o600)
            repository = Path(__file__).resolve().parents[2]
            environment = {
                **os.environ,
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                "GITLAMA_RELEASE_PRIVATE_KEY_FILE": str(key),
                "GITLAMA_TEST_PUBLIC_KEY": str(
                    repository / "release/northspline-release-ed25519.pub"
                ),
                "PUBLIC_GITHUB_REPOSITORY": "devmil/gitlama",
            }

            completed = subprocess.run(
                [
                    "bash",
                    "scripts/publish-candidate.sh",
                    str(candidate),
                    "v0.1.0-beta.8-9",
                    "beta",
                ],
                cwd=repository,
                env=environment,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("Signed candidate prepared", completed.stdout)
            self.assertTrue((candidate / "metadata.json").is_file())
            self.assertTrue((candidate / "metadata.json.sig").is_file())

            (candidate / "GitLama-0.1.0-beta.8-9-macos-arm64.dmg").unlink()
            missing = subprocess.run(
                ["bash", "scripts/publish-candidate.sh", str(candidate),
                 "v0.1.0-beta.8-9", "beta"],
                cwd=repository, env=environment, capture_output=True, text=True,
            )
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("no macOS update package", missing.stderr)

    def test_publication_waits_for_collected_candidate(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        signing = Path("scripts/publish-candidate.sh").read_text(encoding="utf-8")
        publication = Path("scripts/publish-signed-candidate.sh").read_text(encoding="utf-8")
        recovery = Path("scripts/recover-publication.sh").read_text(encoding="utf-8")
        self.assertIn("  publish:\n", workflow)
        self.assertIn("needs: [prepare, collect]", workflow)
        self.assertIn("needs.collect.result == 'success'", workflow)
        self.assertIn("name: Stage, verify and publish the GitHub release", workflow)
        self.assertNotIn("RELEASE_PUBLICATION_ENABLED", workflow)
        self.assertNotIn("publish-release.py", signing)
        self.assertIn('publish-release.py" stage', publication)
        self.assertIn('publish-release.py" publish', publication)
        # Recovery only finishes what the release already holds; it never builds or signs.
        self.assertLess(recovery.index('publish-release.py" recover'),
                        recovery.index('publish-release.py" publish'))
        self.assertNotIn("package.py", recovery)
        self.assertNotIn("release.py\" sign", recovery)

    def test_source_verification_prepares_l10n_output_in_clean_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".fvmrc").write_text(
                '{"flutter": "3.47.5"}\n', encoding="utf-8"
            )
            with (
                mock.patch.object(verify, "ROOT", root),
                mock.patch.object(verify.os, "chdir"),
                mock.patch.object(
                    verify.subprocess,
                    "check_output",
                    return_value='{"frameworkVersion": "3.47.5"}',
                ),
                mock.patch.object(verify, "run") as run,
                mock.patch.object(verify, "use_fvm_flutter"),
                mock.patch.object(verify.sys, "argv", ["verify.py"]),
            ):
                verify.main()

            self.assertTrue((root / "build").is_dir())
            self.assertEqual(run.call_args_list[0], mock.call("flutter", "gen-l10n"))

    def _use_fvm_flutter(self, root: Path, which: str | None) -> tuple[str, mock.Mock]:
        (root / ".fvmrc").write_text('{"flutter": "3.47.5"}\n', encoding="utf-8")
        context = json.dumps({"context": {"versionsCachePath": str(root / "versions")}})
        with (
            mock.patch.object(verify, "ROOT", root),
            mock.patch.object(verify.shutil, "which", return_value=which),
            mock.patch.object(verify.subprocess, "check_output", return_value=context),
            mock.patch.object(verify.subprocess, "run") as run,
            mock.patch.dict(verify.os.environ, {"PATH": "/existing"}),
        ):
            verify.use_fvm_flutter()
            return verify.os.environ["PATH"], run

    def test_fvm_puts_installed_pinned_sdk_first_on_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk_bin = root / "versions" / "3.47.5" / "bin"
            sdk_bin.mkdir(parents=True)
            path, run = self._use_fvm_flutter(root, "/usr/bin/fvm")
            self.assertEqual(path, os.pathsep.join([str(sdk_bin), "/existing"]))
            run.assert_not_called()

    def test_fvm_installs_missing_pinned_sdk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, run = self._use_fvm_flutter(root, "/usr/bin/fvm")
            run.assert_called_once_with(
                ["/usr/bin/fvm", "install", "3.47.5", "--skip-pub-get"], check=True
            )
            self.assertTrue(path.startswith(str(root / "versions" / "3.47.5" / "bin")))

    def test_without_fvm_path_is_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, run = self._use_fvm_flutter(Path(directory), None)
            self.assertEqual(path, "/existing")
            run.assert_not_called()

    def test_verification_scripts_read_repository_text_as_utf8(self) -> None:
        missing_encoding: list[str] = []
        for path in Path("scripts").rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for node in ast.walk(tree):
                if not (
                    isinstance(node, ast.Call)
                    and isinstance(node.func, ast.Attribute)
                    and node.func.attr == "read_text"
                ):
                    continue
                if node.args or any(keyword.arg == "encoding" for keyword in node.keywords):
                    continue
                missing_encoding.append(f"{path}:{node.lineno}")
        self.assertEqual(missing_encoding, [])

    def test_failed_target_builds_keep_their_qualification_reports(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        for job, following in (("macos", "linux"), ("linux", "windows"), ("windows", "collect")):
            section = workflow.split(f"\n  {job}:\n", 1)[1].split(f"\n  {following}:\n", 1)[0]
            failure_upload = section.split("Keep qualification reports of a failed build", 1)[1]
            self.assertIn("if: ${{ failure() }}", failure_upload)
            self.assertIn(f"name: gitlama-{job}-failed-qualification", failure_upload)
            self.assertIn("path: dist/qualification/*.json", failure_upload)
        collect = workflow.split("\n  collect:\n", 1)[1].split("\n  publish:\n", 1)[0]
        self.assertNotIn("*.json", collect.split("mkdir candidate", 1)[1].split("release-state.py", 1)[0])
        script = Path("scripts/qualify-linux-local.sh").read_text(encoding="utf-8")
        cleanup = script.split("cleanup() {", 1)[1].split("\n}\n", 1)[0]
        self.assertLess(
            cleanup.index('"$STAGE"/Flutter/GitLama/dist/qualification/*.json'),
            cleanup.index('rm -rf -- "$STAGE"'),
        )

    def test_release_workflow_has_only_routine_inputs_and_separate_target_jobs(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        input_block = workflow.split("inputs:\n", 1)[1].split("\npermissions:\n", 1)[0]
        self.assertEqual(
            {line.strip()[:-1] for line in input_block.splitlines() if line.startswith("      ") and line.strip().endswith(":")},
            {"bump", "channel"},
        )
        for job in ("prepare", "helper", "helper-macos", "macos", "linux", "windows", "collect", "publish", "website"):
            self.assertIn(f"\n  {job}:\n", workflow)
        self.assertIn("needs.prepare.outputs.mode != 'recover'", workflow)
        self.assertIn("scripts/recover-publication.sh", workflow)
        self.assertIn("scripts/release-state.py", workflow)
        self.assertIn("scripts/qualify-linux-local.sh", workflow)
        self.assertIn("GITLAMA_SOAK_SECONDS: 600", workflow)
        self.assertIn("linux-soak-x86_64.json", workflow)
        self.assertIn("PUBLIC_GITHUB_REPOSITORY: ${{ github.repository }}", workflow)
        self.assertIn("GITHUB_RELEASE_TOKEN: ${{ github.token }}", workflow)
        prepare_job = workflow.split("\n  prepare:\n", 1)[1].split("\n  helper:\n", 1)[0]
        for variable in ("BW_SERVER", "BW_CLIENTID", "BW_CLIENTSECRET", "BW_PASSWORD", "BW_RELEASE_ITEM_ID"):
            self.assertIn(f"{variable}: ${{{{ secrets.{variable} }}}}", prepare_job)
        self.assertIn("gitlama_vault_attachment northspline-release-key.pem", prepare_job)
        for attachment in ("northspline-developer-id.p12", "northspline-notary-api-key.p8"):
            self.assertLess(
                prepare_job.index(f"gitlama_vault_attachment {attachment}"),
                prepare_job.index("python3 scripts/release.py prepare"),
            )
        self.assertIn('--key-file "$release_key"', prepare_job)
        self.assertNotIn("secrets.GITLAMA_RELEASE_PRIVATE_KEY", workflow)
        self.assertLess(
            prepare_job.index("release/northspline-release-ed25519.pub"),
            prepare_job.index("scripts/release.py prepare"),
        )
        self.assertNotIn("scripts/release.py tag", prepare_job)
        self.assertEqual(prepare_job.count("flutter pub get --enforce-lockfile"), 1)
        self.assertLess(prepare_job.index("flutter pub get --enforce-lockfile"),
                        prepare_job.index("scripts/release.py prepare"))
        self.assertLess(prepare_job.index("flutter pub get --enforce-lockfile"),
                        prepare_job.index("./scripts/verify.sh"))
        macos_job = workflow.split("\n  macos:\n", 1)[1].split("\n  linux:\n", 1)[0]
        self.assertIn('rustup target add --toolchain "$RUST_VERSION"', macos_job)
        self.assertIn("aarch64-apple-darwin x86_64-apple-darwin", macos_job)
        windows_job = workflow.split("\n  windows:\n", 1)[1].split("\n  collect:\n", 1)[0]
        self.assertIn("python scripts/package.py msi --skip-build", windows_job)
        self.assertIn("-SoakSeconds 600 -SoakAdvisory", windows_job)
        self.assertIn("windows_soak_policy_cases.ps1", windows_job)
        self.assertNotIn("python scripts/package.py msi\n", windows_job)
        for failure in (
            "WiX setup failed",
            "Flutter dependency resolution failed",
            "Windows release build failed",
            "Windows bundle signing failed",
            "MSI packaging failed",
            "MSI signing failed",
            "MSI qualification failed",
        ):
            self.assertIn(failure, windows_job)
        ci = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
        windows_checks = ci.split("- name: Validate source on Windows", 1)[1]
        self.assertIn('$ErrorActionPreference = "Stop"', windows_checks)
        self.assertIn("windows_soak_policy_cases.ps1", windows_checks)
        linux_job = workflow.split("\n  linux:\n", 1)[1].split("\n  windows:\n", 1)[0]
        self.assertIn("GITLAMA_SOAK_SECONDS: 600", linux_job)
        self.assertNotIn("continue-on-error", workflow)
        self.assertIn("windows-soak-x86_64.json", windows_job)
        # Five package/helper handoffs, five private diagnostics handoffs and the
        # collected private diagnostics.
        self.assertEqual(workflow.count("if-no-files-found: error"), 11)
        macos_helper_job = workflow.split("\n  helper-macos:\n", 1)[1].split("\n  macos:\n", 1)[0]
        self.assertIn("runs-on: macos-15", macos_helper_job)
        self.assertIn("for target in macos-arm64 macos-x86_64; do", macos_helper_job)
        self.assertIn("scripts/package_remote_helper.py --target", macos_helper_job)
        self.assertIn("name: gitlama-remote-helper-macos", macos_helper_job)
        helper_job = workflow.split("\n  helper:\n", 1)[1].split("\n  helper-macos:\n", 1)[0]
        self.assertIn("./scripts/qualify-linux-local.sh --remote-helper", helper_job)
        self.assertIn("GITLAMA_SOURCE_COMMIT: ${{ needs.prepare.outputs.revision }}", helper_job)
        for name in ("macos", "linux", "windows"):
            job = workflow.split(f"\n  {name}:\n", 1)[1]
            job = job[: job.index("retention-days")]
            self.assertIn("needs: [prepare, helper, helper-macos]", job)
            self.assertIn("name: gitlama-remote-helper\n", job)
            self.assertIn("name: gitlama-remote-helper-macos\n", job)
            self.assertIn('GITLAMA_REQUIRE_REMOTE_HELPER: "1"', job)
        self.assertIn("! -name 'gitlama-remote-helper-*'", workflow)
        publish_job = workflow.split("\n  publish:\n", 1)[1]
        self.assertIn("python3 scripts/release.py tag", publish_job)
        self.assertIn("git push origin 'refs/tags/", publish_job)
        collect_job = workflow.split("\n  collect:\n", 1)[1].split("\n  publish:\n", 1)[0]
        self.assertIn("gitlama_vault_attachment northspline-release-key.pem", collect_job)
        self.assertIn("GITLAMA_RELEASE_PRIVATE_KEY_FILE", collect_job)
        self.assertIn("./scripts/publish-candidate.sh publication", collect_job)
        self.assertIn("gitlama-signed-publication-candidate", collect_job)
        self.assertNotIn("publish-release.py", collect_job)
        self.assertEqual(workflow.count("actions/setup-python@v5"), 1)
        self.assertEqual(workflow.count("actions/setup-dotnet@v4"), 1)
        self.assertIn("dotnet-version: '8.0.414'", workflow)
        self.assertGreaterEqual(workflow.count("install-rustup-unix.sh"), 2)
        # The devmil-git pin lives in the manifest; no script repeats a revision.
        self.assertRegex(Path("rust-core/Cargo.toml").read_text(encoding="utf-8"),
                         r'devmil-git = \{ git = "[^"]+", rev = "[0-9a-f]{40}"')
        self.assertNotRegex(Path("scripts/qualify-linux-local.sh").read_text(encoding="utf-8"),
                            r"[0-9a-f]{40}")

    def test_linux_qualification_supports_docker_and_podman(self) -> None:
        harness = Path("scripts/qualify-linux-local.sh").read_text(encoding="utf-8")
        self.assertIn('GITLAMA_CONTAINER_ENGINE', harness)
        self.assertIn('command -v docker', harness)
        self.assertIn('command -v podman', harness)
        self.assertIn('*podman*) VOLUME_SUFFIX=":Z"', harness)
        self.assertIn("find /work -mindepth 1 -delete", harness)
        self.assertIn('--volume "$STAGE:/work$VOLUME_SUFFIX"', harness)
        self.assertIn('"$ROOT/.fvmrc"', harness)
        self.assertIn('--build-arg "FLUTTER_VERSION=$FLUTTER_VERSION"', harness)
        # Cargo fetches devmil-git at its pinned revision; no sibling checkout enters the stage.
        self.assertNotIn("SHARED_GIT", harness)
        # A sudo-wrapped engine drops inherited variables; the shared-dependency
        # rewrite must travel in an env file.
        self.assertIn('--env-file "$GIT_ENV_FILE"', harness)
        self.assertIn('chmod 0600 "$GIT_ENV_FILE"', harness)
        self.assertNotIn("--env GIT_CONFIG_", harness)

    def test_ci_uses_fvmrc_as_the_only_flutter_version_source(self) -> None:
        configured = json.loads(Path(".fvmrc").read_text(encoding="utf-8"))
        self.assertEqual(set(configured), {"flutter"})
        self.assertRegex(configured["flutter"], r"^\d+\.\d+\.\d+$")
        action = Path(".github/actions/flutter/action.yml").read_text(encoding="utf-8")
        self.assertIn('json.load(open(".fvmrc"))["flutter"]', action)
        self.assertIn("subosito/flutter-action@v2", action)
        for workflow_path in (
            Path(".github/workflows/ci.yml"),
            Path(".github/workflows/release.yml"),
        ):
            workflow = workflow_path.read_text(encoding="utf-8")
            self.assertIn("uses: ./.github/actions/flutter", workflow)
            self.assertNotIn("subosito/flutter-action", workflow)
            self.assertNotIn("FLUTTER_VERSION", workflow)
            self.assertNotIn(configured["flutter"], workflow)
        dockerfile = Path("tooling/linux-release/Dockerfile").read_text(
            encoding="utf-8"
        )
        self.assertIn("ARG FLUTTER_VERSION\n", dockerfile)
        self.assertNotIn(f"ARG FLUTTER_VERSION={configured['flutter']}", dockerfile)

    def test_ci_workflow_supports_the_linux_and_windows_hosts(self) -> None:
        workflow = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("matrix.platform == 'linux'", workflow)
        self.assertIn(
            "if: ${{ matrix.platform == 'windows' }}\n        uses: actions/setup-python@v5",
            workflow,
        )
        self.assertIn("pkg-config --exists gtk+-3.0", workflow)
        self.assertIn("python scripts/native-smoke.py", workflow)
        windows_smoke = workflow.split("- name: Load bundled Rust on Windows\n", 1)[1].split(
            "- name:", 1
        )[0]
        self.assertIn("GITLAMA_NATIVE_TEST_TIMEOUT_SECONDS: '180'", windows_smoke)
        self.assertIn("GITLAMA_NATIVE_TEST_WAIT_SECONDS: '30'", windows_smoke)
        self.assertIn("Resolve locked dependencies on Windows", workflow)
        self.assertIn("Build desktop bundle on Windows", workflow)
        self.assertIn("Archive debug bundle on Windows", workflow)
        self.assertIn("Compress-Archive -LiteralPath", workflow)
        self.assertIn('tar -C "$(dirname "${{ matrix.bundle }}")"', workflow)
        self.assertIn("path: ${{ matrix.artifact }}", workflow)
        self.assertIn("if-no-files-found: error", workflow)
        self.assertIn("install-rustup-unix.sh", workflow)
        self.assertIn("install-rustup-windows.ps1", workflow)

    def test_stable_and_beta_bumps_are_monotonic(self) -> None:
        stable = Version("1.2.3", 7)
        self.assertEqual(bumped(stable, "patch", "stable"), Version("1.2.4", 8))
        self.assertEqual(bumped(stable, "minor", "beta"), Version("1.3.0-beta.1", 8))
        self.assertEqual(bumped(stable, "beta", "beta"), Version("1.2.3-beta.1", 8))
        self.assertEqual(
            bumped(Version("1.2.3-beta.1", 8), "beta", "beta"),
            Version("1.2.3-beta.2", 9),
        )
        with self.assertRaises(ValueError):
            bumped(stable, "beta", "stable")
        with self.assertRaises(ValueError):
            bumped(Version("1.2.3-rc.1", 8), "beta", "beta")

    def test_document_promotion_preserves_history_and_falls_back_to_changelog(self) -> None:
        source = (
            "# Notes\n\n## Unreleased Stable\n\n\n## Unreleased Beta\n\n- New beta.\n\n"
            "## [1.0.0] - 2025-01-01\n\n- Existing.\n"
        )
        promoted = promoted_document(
            source,
            Version("1.1.0", 2),
            "stable",
            date(2026, 9, 19),
            fallback_items=["Generated fallback."],
        )
        self.assertIn("## [1.1.0] - 2026-09-19\n\n- Generated fallback.", promoted)
        self.assertIn("## [1.0.0] - 2025-01-01\n\n- Existing.", promoted)
        self.assertIn("## Unreleased Beta\n\n", promoted)

    def test_prepare_updates_all_canonical_versions_and_selected_documents(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            current = Version("1.2.3", 7)
            updated = Version("1.3.0-beta.1", 8)
            fixture(root, current)
            write_atomic(prepare_updates(root, current, updated, "beta", date(2026, 9, 19)))
            self.assertEqual(Version.read(root / "VERSION"), updated)
            self.assertIn("version: 1.3.0-beta.1+8", (root / "pubspec.yaml").read_text())
            self.assertIn('version = "1.3.0-beta.1"', (root / "rust-core/Cargo.toml").read_text())
            self.assertIn("## [1.3.0-beta.1] - 2026-09-19", (root / "CHANGELOG.md").read_text())
            self.assertIn("- Stable item.", (root / "CHANGELOG.md").read_text())

    def test_dirty_candidate_and_duplicate_preparation_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture(root)
            initialize_git(root)
            (root / "pubspec.yaml").write_text("dirty\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                require_clean(root)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture(root)
            initialize_git(root)
            first = plan(root, "patch", "stable")
            self.assertEqual(first.mode, "prepare")
            subprocess.run(
                ["git", "tag", "-a", first.tag, "-m", "occupied"],
                cwd=root,
                check=True,
            )
            with self.assertRaises(ValueError):
                plan(root, "patch", "stable")

    def test_none_recovers_only_an_annotated_matching_tag(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = Version("1.2.3", 7)
            fixture(root, version)
            for document in ("CHANGELOG.md", "RELEASE_NOTES.md"):
                path = root / document
                path.write_text(
                    path.read_text().rstrip() + "\n\n## [1.2.3] - 2026-09-19\n\n- Released.\n",
                    encoding="utf-8",
                )
            initialize_git(root)
            tag = create_annotated_tag(root, version, "stable")
            recovery = plan(root, "none", "stable")
            self.assertEqual(recovery.mode, "recover")
            self.assertEqual(recovery.tag, tag)
            self.assertEqual(recovery.revision, command(root, "git", "rev-parse", "HEAD"))

    def test_none_resumes_prepared_metadata_after_interruption_before_tag(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = Version("1.2.3", 7)
            fixture(root, version)
            for document in ("CHANGELOG.md", "RELEASE_NOTES.md"):
                path = root / document
                path.write_text(
                    path.read_text().rstrip() + "\n\n## [1.2.3] - 2026-09-19\n\n- Released.\n",
                    encoding="utf-8",
                )
            initialize_git(root)
            resumed = plan(root, "none", "stable")
            self.assertEqual(resumed.mode, "resume-prepared")

    def test_existing_tag_recovery_uses_only_hash_matching_original_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = Version("1.2.3", 7)
            candidates = root / "candidates"
            retained = root / "retained"
            candidates.mkdir()
            retained.mkdir()
            names = sorted(artifact_name(version, *target) for target in TARGETS)
            for index, name in enumerate(names):
                (candidates / name).write_bytes(f"artifact-{index}".encode())
            state_value = build_state(candidates, version)
            state = parse_state(json.dumps(state_value).encode(), "v1.2.3-7")
            for name in names[:3]:
                (retained / name).write_bytes((candidates / name).read_bytes())

            def fetch(name: str, destination: Path) -> bool:
                if name in names[3:]:
                    destination.write_bytes((candidates / name).read_bytes())
                    return True
                return False

            output = root / "recovered"
            recover(state, output, retained, fetch)
            self.assertEqual(
                {path.name for path in output.iterdir()},
                {*names, "release-state.json"},
            )
            for name in names:
                self.assertEqual((output / name).read_bytes(), (candidates / name).read_bytes())

    def test_recovery_rejects_changed_or_unavailable_original(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = Version("1.2.3", 7)
            candidates = root / "candidates"
            candidates.mkdir()
            for index, target in enumerate(TARGETS):
                (candidates / artifact_name(version, *target)).write_bytes(f"artifact-{index}".encode())
            state = parse_state(json.dumps(build_state(candidates, version)).encode(), "v1.2.3-7")

            def changed(name: str, destination: Path) -> bool:
                destination.write_bytes(b"changed")
                return True

            with self.assertRaisesRegex(ValueError, "bytes differ"):
                recover(state, root / "changed", None, changed)
            self.assertFalse((root / "changed").exists())
            with self.assertRaisesRegex(ValueError, "unavailable"):
                recover(state, root / "missing", None, lambda _name, _destination: False)
            self.assertFalse((root / "missing").exists())


if __name__ == "__main__":
    unittest.main()
