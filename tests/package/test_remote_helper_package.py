import copy
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

from scripts import package_remote_helper as helper
from scripts.lib.package_contract import (
    REMOTE_HELPER_TARGETS,
    TARGETS,
    Version,
    artifact_name,
    remote_helper_archive_name,
    remote_helper_id,
    remote_helper_metadata_name,
)
from scripts.lib.release_manifest import artifact_paths, build_manifest, encode
from scripts.lib.release_signing import openssl_binary, sign_manifest, write_public_key
from scripts.lib.release_verification import parse_manifest, verify_signature

COMMIT = "0123456789abcdef0123456789abcdef01234567"
# The checkout's helper ID: its compatibility version, not the commit.
BUILD_ID = remote_helper_id(Path(__file__).resolve().parents[2])


class RemoteHelperPackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.version = Version("1.2.3-beta.4", 9)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def candidate(self, *, with_helper: bool, helpers: tuple[str, ...] = ("linux-x86_64",)) -> Path:
        directory = self.root / "candidate"
        directory.mkdir()
        for index, target in enumerate(sorted(TARGETS)):
            (directory / artifact_name(self.version, *target)).write_bytes(f"artifact {index}".encode())
        if with_helper:
            for name in helpers:
                target = next(item for item in REMOTE_HELPER_TARGETS if item.name == name)
                binary = f"helper bytes for {name}".encode()
                archive = helper.build_archive(binary, 1_700_000_000)
                (directory / remote_helper_archive_name(self.version, name)).write_bytes(archive)
                record = helper.metadata(
                    version=self.version,
                    build_id=BUILD_ID,
                    source_commit=COMMIT,
                    shared_revision="e" * 40,
                    archive=archive,
                    binary=binary,
                    glibc=(2, 34) if target.platform == "linux" else None,
                    target=target,
                )
                (directory / remote_helper_metadata_name(self.version, name)).write_text(
                    json.dumps(record), encoding="utf-8"
                )
        return directory

    def test_archive_is_reproducible_and_holds_only_the_executable_helper(self) -> None:
        first = helper.build_archive(b"helper", 1_700_000_000)
        self.assertEqual(first, helper.build_archive(b"helper", 1_700_000_000))
        self.assertNotEqual(first, helper.build_archive(b"helper", 1_700_000_001))
        with tarfile.open(fileobj=io.BytesIO(first), mode="r:gz") as archive:
            members = archive.getmembers()
            self.assertEqual([member.name for member in members], ["gitlama-remote-helper"])
            self.assertEqual(members[0].mode, 0o755)
            self.assertEqual((members[0].uid, members[0].gid, members[0].uname), (0, 0, ""))
            self.assertEqual(archive.extractfile(members[0]).read(), b"helper")

    def test_metadata_names_the_install_location_of_its_build(self) -> None:
        record = helper.metadata(
            version=self.version,
            build_id=BUILD_ID,
            source_commit=COMMIT,
            shared_revision="e" * 40,
            archive=b"archive",
            binary=b"binary",
            glibc=(2, 35),
        )
        self.assertEqual(record["install_path"], f"~/.local/lib/gitlama/remote/{BUILD_ID}/gitlama-remote-helper")
        self.assertEqual(record["file"], remote_helper_archive_name(self.version))
        self.assertEqual(record["glibc_requirement"], "2.35")
        self.assertEqual(record["protocol_major"], 1)
        self.assertEqual(record["source_commit"], COMMIT)

    def test_the_helper_id_is_the_padded_compatibility_version(self) -> None:
        (self.root / "rust-core" / "remote-helper").mkdir(parents=True)
        compatibility = self.root / "rust-core" / "remote-helper" / "COMPATIBILITY"
        compatibility.write_text("# note\nversion 12\ncontract " + "a" * 64 + "\n", encoding="utf-8")
        self.assertEqual(remote_helper_id(self.root), "0" * 38 + "12")
        compatibility.write_text("version 012\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            remote_helper_id(self.root)

    def test_release_without_a_helper_is_unchanged(self) -> None:
        candidate = self.candidate(with_helper=False)
        document = build_manifest(candidate, self.version, "https://example.invalid/r", "beta")
        self.assertNotIn("remote_helpers", document["latest"])

    def test_signed_manifest_carries_and_verifies_the_helper(self) -> None:
        candidate = self.candidate(with_helper=True)
        self.assertEqual(len(artifact_paths(candidate, self.version)), len(TARGETS))
        document = build_manifest(candidate, self.version, "https://example.invalid/r", "beta")
        record = document["latest"]["remote_helpers"][0]
        self.assertEqual(record["build_id"], BUILD_ID)
        self.assertEqual(record["file"], remote_helper_archive_name(self.version))
        key = self.root / "release.pem"
        subprocess.run([openssl_binary(), "genpkey", "-algorithm", "ED25519", "-out", key],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        key.chmod(0o600)
        public = self.root / "release.pub"
        write_public_key(public, key_file=key)
        manifest = self.root / "metadata.json"
        signature = self.root / "metadata.json.sig"
        manifest.write_bytes(encode(document))
        sign_manifest(manifest, signature, key_file=key)
        parse_manifest(verify_signature(manifest, signature, public))

    def test_signed_manifest_carries_one_helper_per_host_platform(self) -> None:
        names = tuple(target.name for target in REMOTE_HELPER_TARGETS)
        candidate = self.candidate(with_helper=True, helpers=names)
        self.assertEqual(len(artifact_paths(candidate, self.version)), len(TARGETS))
        document = build_manifest(candidate, self.version, "https://example.invalid/r", "beta")
        records = document["latest"]["remote_helpers"]
        self.assertEqual(
            [(record["platform"], record["architecture"], record["target"]) for record in records],
            [("linux", "x86_64", "x86_64-unknown-linux-gnu"),
             ("linux", "arm64", "aarch64-unknown-linux-gnu"),
             ("macos", "arm64", "aarch64-apple-darwin"),
             ("macos", "x86_64", "x86_64-apple-darwin")],
        )
        self.assertEqual(records[1]["file"], remote_helper_archive_name(self.version, "linux-arm64"))
        self.assertIn("Raspberry Pi", records[1]["minimum_system"])
        self.assertEqual(records[2]["file"], remote_helper_archive_name(self.version, "macos-arm64"))
        self.assertIn("macOS 13", records[2]["minimum_system"])
        parse_manifest(encode(document))
        # One record per platform: a duplicate, or a file named for another platform, is forged.
        for forge in (
            lambda helpers: helpers.append(copy.deepcopy(helpers[1])),
            lambda helpers: helpers[2].update(file=helpers[3]["file"]),
            lambda helpers: helpers[2].update(architecture="x86_64"),
            lambda helpers: helpers[1].update(platform="macos"),
        ):
            forged = copy.deepcopy(document)
            for release in (forged["latest"], forged["releases"][0]):
                forge(release["remote_helpers"])
            with self.assertRaises(ValueError):
                parse_manifest(encode(forged))

    def test_tampered_or_incomplete_helpers_are_rejected(self) -> None:
        candidate = self.candidate(with_helper=True)
        archive = candidate / remote_helper_archive_name(self.version)
        archive.write_bytes(archive.read_bytes() + b"x")
        with self.assertRaisesRegex(ValueError, "does not match the archive"):
            build_manifest(candidate, self.version, "https://example.invalid/r", "beta")
        (candidate / remote_helper_metadata_name(self.version)).unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            artifact_paths(candidate, self.version)

    def test_verification_rejects_a_forged_helper_record(self) -> None:
        candidate = self.candidate(with_helper=True)
        document = build_manifest(candidate, self.version, "https://example.invalid/r", "beta")
        for field, value in (
            ("build_id", "not-a-build"),
            ("file", "other.tar.gz"),
            ("url", "http://example.invalid/r/other.tar.gz"),
            ("protocol_major", 2),
            ("extra", True),
        ):
            forged = copy.deepcopy(document)
            for release in (forged["latest"], forged["releases"][0]):
                release["remote_helpers"][0][field] = value
            with self.assertRaises(ValueError, msg=field):
                parse_manifest(encode(forged))


if __name__ == "__main__":
    unittest.main()


class RemoteHelperBundlingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.version = Version.read(Path("VERSION"))
        self.inputs = self.root / "helper"
        self.inputs.mkdir()
        self.binary = b"\x7fELF bundled helper"
        self.add_helper("linux-x86_64", self.binary)

    def add_helper(self, name: str, binary: bytes) -> None:
        target = next(item for item in REMOTE_HELPER_TARGETS if item.name == name)
        archive = helper.build_archive(binary, 0)
        (self.inputs / remote_helper_archive_name(self.version, name)).write_bytes(archive)
        (self.inputs / remote_helper_metadata_name(self.version, name)).write_text(
            json.dumps(
                helper.metadata(
                    version=self.version,
                    build_id=BUILD_ID,
                    source_commit=COMMIT,
                    shared_revision="e" * 40,
                    archive=archive,
                    binary=binary,
                    glibc=(2, 35) if target.platform == "linux" else None,
                    target=target,
                )
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def environment(self, **extra: str) -> dict[str, str]:
        return {
            "GITLAMA_REMOTE_HELPER_DIR": str(self.inputs),
            "GITLAMA_SOURCE_COMMIT": COMMIT,
            **extra,
        }

    def test_each_platform_bundles_the_verified_helper_where_the_app_looks(self) -> None:
        from scripts import package

        expected = {
            "linux": "lib/remote-helper/linux-x86_64",
            "macos": "Contents/Resources/remote-helper/linux-x86_64",
            "windows": "remote-helper/linux-x86_64",
        }
        for platform_name, relative in expected.items():
            bundle = self.root / platform_name
            self.assertTrue(package.bundle_remote_helper(bundle, platform_name, self.environment()))
            executable = bundle / relative / "gitlama-remote-helper"
            self.assertEqual(executable.read_bytes(), self.binary)
            if os.name != "nt":
                # Windows file modes carry no execute bits.
                self.assertTrue(executable.stat().st_mode & 0o111)
            descriptor = json.loads((bundle / relative / "gitlama-remote-helper.json").read_text(encoding="utf-8"))
            self.assertEqual(descriptor["build_id"], BUILD_ID)
            self.assertEqual(descriptor["bytes"], len(self.binary))

    def test_every_host_platform_gets_its_own_directory(self) -> None:
        from scripts import package

        mac = b"\xcf\xfa\xed\xfe mac helper"
        self.add_helper("macos-arm64", mac)
        bundle = self.root / "linux-bundle"
        self.assertTrue(package.bundle_remote_helper(bundle, "linux", self.environment()))
        self.assertEqual(
            (bundle / "lib/remote-helper/macos-arm64/gitlama-remote-helper").read_bytes(), mac
        )
        descriptor = json.loads(
            (bundle / "lib/remote-helper/macos-arm64/gitlama-remote-helper.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(descriptor["target"], "aarch64-apple-darwin")
        # Optional for local candidates, but a release needs every platform.
        self.assertFalse((bundle / "lib/remote-helper/macos-x86_64").exists())
        pi = b"\x7fELF arm64 helper"
        self.add_helper("linux-arm64", pi)
        self.assertTrue(package.bundle_remote_helper(bundle, "linux", self.environment()))
        self.assertEqual(
            (bundle / "lib/remote-helper/linux-arm64/gitlama-remote-helper").read_bytes(), pi
        )
        with self.assertRaisesRegex(RuntimeError, "macos-x86_64 is missing"):
            package.bundle_remote_helper(
                self.root / "release", "linux",
                self.environment(GITLAMA_REQUIRE_REMOTE_HELPER="1"),
            )

    def test_a_helper_of_another_commit_or_a_missing_required_helper_fails(self) -> None:
        from scripts import package

        with self.assertRaisesRegex(RuntimeError, "different source commit"):
            package.bundle_remote_helper(
                self.root / "bundle", "linux", self.environment(GITLAMA_SOURCE_COMMIT="f" * 40)
            )
        with self.assertRaisesRegex(RuntimeError, "requires the remote helper"):
            package.bundle_remote_helper(self.root / "bundle", "linux", {"GITLAMA_REQUIRE_REMOTE_HELPER": "1"})
        metadata_file = self.inputs / remote_helper_metadata_name(self.version)
        record = json.loads(metadata_file.read_text(encoding="utf-8"))
        record["build_id"] = "9" * 40
        metadata_file.write_text(json.dumps(record), encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "another compatibility version"):
            package.bundle_remote_helper(self.root / "bundle", "linux", self.environment())
        self.assertFalse(package.bundle_remote_helper(self.root / "bundle", "linux", {}))

    def test_tampered_archives_are_refused(self) -> None:
        from scripts import package

        archive = self.inputs / remote_helper_archive_name(self.version)
        archive.write_bytes(archive.read_bytes() + b"x")
        with self.assertRaisesRegex(RuntimeError, "does not describe"):
            package.bundle_remote_helper(self.root / "bundle", "linux", self.environment())
