from pathlib import Path
import shutil
import subprocess
import unittest


class MacosSigningTest(unittest.TestCase):
    def test_keychain_search_list_normalizes_indented_paths(self) -> None:
        bash = shutil.which("bash")
        if bash is None:
            git = shutil.which("git")
            self.assertIsNotNone(git, "Git is required for release validation")
            git_directory = Path(git).parent
            bash = next(
                (
                    str(candidate)
                    for candidate in (
                        git_directory / "bash.exe",
                        git_directory.parent / "bin" / "bash.exe",
                    )
                    if candidate.is_file()
                ),
                None,
            )
        self.assertIsNotNone(bash, "Bash is required for release validation")

        result = subprocess.run(
            [
                bash,
                "-uc",
                r"""
                source scripts/lib/macos-keychains.sh
                directory="$(mktemp -d)"
                trap 'rm -rf -- "$directory"' EXIT
                keychain="$directory/Login Keychain.keychain-db"
                : > "$keychain"
                actual="$(
                    {
                        printf '    "%s"\n' "$keychain" "$keychain"
                        printf '    "%s/    "%s""\n' "$keychain" "$keychain"
                    } | gitlama_existing_keychains
                )"
                [[ "$actual" == "$keychain" ]]
                """,
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_signer_accepts_api_key_credentials_without_weakening_notarization(self) -> None:
        script = Path("scripts/sign-macos-candidate.sh").read_text(encoding="utf-8")

        self.assertIn("APPLE_API_KEY_FILE", script)
        self.assertIn("APPLE_API_KEY_ID", script)
        self.assertIn("APPLE_API_ISSUER_ID", script)
        self.assertIn('--key "$APPLE_API_KEY_FILE"', script)
        self.assertLess(
            script.index("APPLE_API_KEY_FILE"), script.index("NOTARY_PROFILE")
        )
        self.assertIn('echo "sign-macos-candidate: notarization credentials are required"', script)
        self.assertIn('xcrun stapler validate "$candidate"', script)

    def test_release_uses_the_cocoapods_version_of_the_lock_file(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        macos_job = workflow.split("\n  macos:\n", 1)[1].split("\n  linux:\n", 1)[0]
        lock = Path("macos/Podfile.lock").read_text(encoding="utf-8")

        self.assertRegex(lock, r"\nCOCOAPODS: \d+\.\d+\.\d+\n")
        self.assertIn("sed -n 's/^COCOAPODS: //p' macos/Podfile.lock", macos_job)
        self.assertIn('gem install cocoapods --version "$version"', macos_job)
        self.assertLess(macos_job.index("Install the CocoaPods version of the lock file"),
                        macos_job.index("python3 scripts/package.py dmg"))

    def test_stapling_retries_a_dropped_ticket_lookup(self) -> None:
        import os
        import subprocess
        import tempfile

        script = Path("scripts/sign-macos-candidate.sh").read_text(encoding="utf-8")
        function = script.split("staple_with_retry() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('staple_with_retry "$candidate"', script)
        self.assertLess(script.index('staple_with_retry "$candidate"'),
                        script.index('xcrun stapler validate "$candidate"'))
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "xcrun"
            count = Path(directory) / "count"
            # Fails twice like a dropped CloudKit connection, then staples.
            fake.write_text(
                f'#!/bin/bash\nn=$(( $(cat {count} 2>/dev/null || echo 0) + 1 ))\n'
                f'echo $n > {count}\n(( n >= 3 ))\n'
            )
            fake.chmod(0o755)
            environment = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}",
                               GITLAMA_STAPLE_RETRY_SECONDS="0")
            program = "staple_with_retry() {" + function + "\n}\nstaple_with_retry candidate.dmg"
            result = subprocess.run(["bash", "-c", program], env=environment,
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(count.read_text().strip(), "3")

            count.write_text("-10")
            result = subprocess.run(["bash", "-c", program], env=environment,
                                    capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stapling failed after 5 attempts", result.stderr)

    def test_release_uses_disposable_secret_backed_keychain(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        macos_job = workflow.split("\n  macos:\n", 1)[1].split("\n  linux:\n", 1)[0]

        for variable in (
            "MACOS_DEVELOPER_ID_P12_BASE64",
            "MACOS_DEVELOPER_ID_P12_PASSWORD",
            "MACOS_CODESIGN_IDENTITY",
            "APPLE_NOTARY_KEY_BASE64",
            "APPLE_NOTARY_KEY_ID",
            "APPLE_NOTARY_ISSUER_ID",
        ):
            self.assertIn(f"{variable}: ${{{{ secrets.{variable} }}}}", macos_job)
        self.assertIn("source scripts/lib/release-secrets.sh", macos_job)
        self.assertIn(
            'gitlama_secret_file MACOS_DEVELOPER_ID_P12_BASE64 "$release_tmp/developer-id.p12"',
            macos_job,
        )
        self.assertIn(
            'gitlama_secret_file APPLE_NOTARY_KEY_BASE64 "$release_tmp/notary-api-key.p8"',
            macos_job,
        )
        self.assertIn("security create-keychain", macos_job)
        self.assertIn("security delete-keychain", macos_job)
        self.assertIn('rm -rf -- "$release_tmp"', macos_job)

    def test_secret_helper_never_prints_values(self) -> None:
        helper = Path("scripts/lib/release-secrets.sh").read_text(encoding="utf-8")

        self.assertNotIn("set -x", helper)
        self.assertIn("umask 077", helper)
        self.assertIn('chmod 600 "$output"', helper)
        self.assertIn(">/dev/null", helper.replace('>"$output" 2>/dev/null', ">/dev/null"))
        for line in helper.splitlines():
            if "echo" in line:
                self.assertNotRegex(line, r"\$\{?!|\$data|\$text")

    def test_secret_helper_decodes_and_rejects_values(self) -> None:
        import base64
        import os
        import subprocess
        import tempfile

        payload = b"-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----\n"
        encoded = base64.encodebytes(payload).decode("ascii")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "key.pem"

            def decode(value: str | None) -> subprocess.CompletedProcess[str]:
                environment = {k: v for k, v in os.environ.items() if k != "TEST_SECRET"}
                if value is not None:
                    environment["TEST_SECRET"] = value
                return subprocess.run(
                    ["bash", "-c", 'source scripts/lib/release-secrets.sh && gitlama_secret_file TEST_SECRET "$1"', "-", str(output)],
                    env=environment, capture_output=True, text=True, check=False,
                )

            result = decode(encoded)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_bytes(), payload)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(result.stdout, "")

            for value, message in ((None, "missing TEST_SECRET"), ("not*base64!", "TEST_SECRET is not valid base64")):
                output.write_bytes(b"stale")
                result = decode(value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertNotIn("not*base64", result.stderr)
                self.assertFalse(output.exists())

    def test_manifest_signing_uses_the_secret_key_as_a_file(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        publisher = Path("scripts/publish-candidate.sh").read_text(encoding="utf-8")

        self.assertEqual(workflow.count("gitlama_secret_file RELEASE_SIGNING_KEY_BASE64"), 2)
        self.assertNotIn("BW_", workflow)
        self.assertIn("GITLAMA_RELEASE_PRIVATE_KEY_FILE", publisher)
        self.assertIn('--key-file "$GITLAMA_RELEASE_PRIVATE_KEY_FILE"', publisher)
        self.assertIn('--key-env GITLAMA_RELEASE_PRIVATE_KEY', publisher)

if __name__ == "__main__":
    unittest.main()
