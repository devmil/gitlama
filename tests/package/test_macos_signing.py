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

    def test_release_uses_disposable_vault_backed_keychain(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        macos_job = workflow.split("\n  macos:\n", 1)[1].split("\n  linux:\n", 1)[0]

        for variable in (
            "BW_SERVER",
            "BW_CLIENTID",
            "BW_CLIENTSECRET",
            "BW_PASSWORD",
            "BW_RELEASE_ITEM_ID",
        ):
            self.assertIn(f"{variable}: ${{{{ secrets.{variable} }}}}", macos_job)
        self.assertIn("source scripts/lib/vaultwarden-release.sh", macos_job)
        self.assertIn(
            "gitlama_vault_attachment northspline-developer-id.p12",
            macos_job,
        )
        self.assertIn(
            "gitlama_vault_attachment northspline-notary-api-key.p8",
            macos_job,
        )
        self.assertIn("security create-keychain", macos_job)
        self.assertIn("security delete-keychain", macos_job)
        self.assertIn('echo "::add-mask::$p12_password"', macos_job)

    def test_vault_helper_never_prints_field_values(self) -> None:
        helper = Path("scripts/lib/vaultwarden-release.sh").read_text(encoding="utf-8")

        self.assertIn("--passwordenv BW_PASSWORD", helper)
        self.assertNotIn("set -x", helper)
        self.assertNotIn("echo \"$value\"", helper)
        self.assertIn("chmod 600", helper)

    def test_vault_server_is_a_masked_secret_without_a_default(self) -> None:
        helper = Path("scripts/lib/vaultwarden-release.sh").read_text(encoding="utf-8")
        self.assertIn("for variable in BW_SERVER ", helper)
        self.assertIn('echo "::add-mask::$BW_SERVER"', helper)
        self.assertIn('bw config server "$BW_SERVER" >/dev/null 2>&1', helper)
        self.assertNotIn("${BW_SERVER:-", helper)
        # Bitwarden CLI errors can name the server, so none reaches the log.
        for line in helper.replace("\\\n", " ").splitlines():
            if line.strip().startswith("bw ") or "$(bw " in line:
                self.assertTrue("2>/dev/null" in line or ">/dev/null 2>&1" in line, line)
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertNotRegex(workflow, r"BW_SERVER: (?!\$\{\{ secrets\.BW_SERVER \}\})")

    def test_manifest_signing_uses_the_vault_attachment_as_a_file(self) -> None:
        workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        publisher = Path("scripts/publish-candidate.sh").read_text(encoding="utf-8")

        self.assertGreaterEqual(
            workflow.count(
                "gitlama_vault_attachment northspline-release-key.pem"
            ),
            2,
        )
        self.assertIn("GITLAMA_RELEASE_PRIVATE_KEY_FILE", publisher)
        self.assertIn('--key-file "$GITLAMA_RELEASE_PRIVATE_KEY_FILE"', publisher)
        self.assertIn('--key-env GITLAMA_RELEASE_PRIVATE_KEY', publisher)

if __name__ == "__main__":
    unittest.main()
