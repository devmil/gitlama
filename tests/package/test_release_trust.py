import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.lib.package_contract import TARGETS, Version, artifact_name
from scripts.lib.release_manifest import build_manifest, encode, merge
from scripts.lib.release_signing import openssl_binary, sign_manifest, write_public_key
from scripts.lib.release_verification import (
    MAX_MANIFEST_BYTES,
    parse_manifest,
    select_asset,
    verify_artifact,
    verify_signature,
)


class ReleaseTrustTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.key = self.root / "release.pem"
        subprocess.run([openssl_binary(), "genpkey", "-algorithm", "ED25519", "-out", self.key],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.key.chmod(0o600)
        self.public = self.root / "northspline-release-ed25519.pub"
        write_public_key(self.public, key_file=self.key)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def candidate(self, version: Version = Version("1.2.3", 7)) -> Path:
        directory = self.root / f"candidate-{version.build}"
        directory.mkdir()
        for index, target in enumerate(sorted(TARGETS)):
            (directory / artifact_name(version, *target)).write_bytes(
                f"GitLama artifact {version.build} {index}".encode()
            )
        return directory

    def signed(self, document: dict, name: str = "metadata") -> tuple[Path, Path]:
        manifest = self.root / f"{name}.json"
        signature = self.root / f"{name}.json.sig"
        manifest.write_bytes(encode(document))
        sign_manifest(manifest, signature, key_file=self.key)
        return manifest, signature

    def test_exact_bytes_and_artifact_verify_offline(self) -> None:
        version = Version("1.2.3", 7)
        candidate = self.candidate(version)
        document = build_manifest(candidate, version,
                                  "https://github.com/devmil/gitlama/releases/download/v1.2.3-7",
                                  "stable")
        manifest, signature = self.signed(document)
        raw = verify_signature(manifest, signature, self.public)
        parsed, releases = parse_manifest(raw)
        self.assertEqual(parsed["latest"]["tag"], "v1.2.3-7")
        self.assertEqual(len(releases[0]), 6)
        asset = select_asset(raw, platform="macos", architecture="arm64", format_="dmg")
        verify_artifact(candidate / asset.file, asset)

    def test_wrong_key_changed_manifest_and_tampered_package_fail(self) -> None:
        version = Version("1.2.3", 7)
        candidate = self.candidate(version)
        manifest, signature = self.signed(build_manifest(
            candidate, version, "https://example.invalid/v1.2.3-7", "stable"))
        wrong_key = self.root / "wrong.pem"
        subprocess.run([openssl_binary(), "genpkey", "-algorithm", "ED25519", "-out", wrong_key], check=True)
        wrong_key.chmod(0o600)
        wrong_public = self.root / "wrong.pub"
        write_public_key(wrong_public, key_file=wrong_key)
        with self.assertRaisesRegex(ValueError, "signature is invalid"):
            verify_signature(manifest, signature, wrong_public)
        manifest.write_bytes(manifest.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "signature is invalid"):
            verify_signature(manifest, signature, self.public)
        manifest, signature = self.signed(build_manifest(
            candidate, version, "https://example.invalid/v1.2.3-7", "stable"), "fresh")
        raw = verify_signature(manifest, signature, self.public)
        asset = select_asset(raw, platform="macos", architecture="arm64", format_="dmg")
        (candidate / asset.file).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "size differs|digest differs"):
            verify_artifact(candidate / asset.file, asset)

    def test_signed_wrong_target_and_authenticated_url_fail(self) -> None:
        version = Version("1.2.3", 7)
        document = build_manifest(self.candidate(version), version,
                                  "https://example.invalid/v1.2.3-7", "stable")
        wrong_target = copy.deepcopy(document)
        wrong_target["latest"]["assets"][0]["platform"] = "plan9"
        manifest, signature = self.signed(wrong_target, "wrong-target")
        with self.assertRaisesRegex(ValueError, "unexpected or duplicate target"):
            parse_manifest(verify_signature(manifest, signature, self.public))
        authenticated = copy.deepcopy(document)
        authenticated["latest"]["assets"][0]["url"] = "https://user:pass@example.invalid/file"
        manifest, signature = self.signed(authenticated, "authenticated")
        with self.assertRaisesRegex(ValueError, "unauthenticated HTTPS"):
            parse_manifest(verify_signature(manifest, signature, self.public))

    def test_malformed_oversized_and_replayed_manifest_fail(self) -> None:
        malformed, signature = self.signed({"not": "a release"}, "malformed")
        with self.assertRaisesRegex(ValueError, "schema"):
            parse_manifest(verify_signature(malformed, signature, self.public))
        oversized = self.root / "oversized.json"
        oversized.write_bytes(b"x" * (MAX_MANIFEST_BYTES + 1))
        with self.assertRaisesRegex(ValueError, "exceeds"):
            verify_signature(oversized, signature, self.public)
        old_version = Version("1.2.3", 7)
        old = build_manifest(self.candidate(old_version), old_version,
                             "https://example.invalid/v1.2.3-7", "stable")
        newer_version = Version("1.2.4", 8)
        newer = build_manifest(self.candidate(newer_version), newer_version,
                               "https://example.invalid/v1.2.4-8", "stable")
        with self.assertRaisesRegex(ValueError, "replays"):
            merge(newer, old)
        manifest, signature = self.signed(old, "replay")
        raw = verify_signature(manifest, signature, self.public)
        with self.assertRaisesRegex(ValueError, "replays"):
            select_asset(raw, platform="linux", architecture="x86_64", format_="deb",
                         minimum_build=8)

    def test_retention_keeps_five_per_channel(self) -> None:
        history = None
        for build in range(1, 13):
            if build % 2:
                version, channel = Version(f"1.0.{build}", build), "stable"
            else:
                version, channel = Version(f"1.1.0-beta.{build // 2}", build), "beta"
            current = build_manifest(self.candidate(version), version,
                                     f"https://example.invalid/v{version.marketing}-{build}", channel)
            history = current if history is None else merge(history, current)
        assert history is not None
        self.assertEqual(len(history["releases"]), 10)
        self.assertEqual(
            {channel: sum(item["channel"] == channel for item in history["releases"])
             for channel in ("stable", "beta")},
            {"stable": 5, "beta": 5},
        )


if __name__ == "__main__":
    unittest.main()
