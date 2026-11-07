import base64
import copy
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from scripts.lib.package_contract import TARGETS, Version, artifact_name
from scripts.lib.release_appcast import FEED_URL, RELEASES_URL, SPARKLE, build_appcast
from scripts.lib.release_manifest import build_manifest, encode
from scripts.lib.release_signing import (
    openssl_binary, sign_manifest, sign_update_archive, write_public_key,
)
from scripts.lib.release_verification import (
    parse_manifest, select_asset, verify_manifest, verify_update_signature,
)
from scripts.lib.release_website import sync_index, write_receipt


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "test/fixtures"
NAMESPACE = {"sparkle": SPARKLE}
SIGNATURE = f"{{{SPARKLE}}}edSignature"


def fixture_artifact(version: str, build: int) -> bytes:
    return f"GitLama fixture {version}+{build} macos/arm64/dmg\n".encode()


class ReleaseUpdatesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.key = self.root / "release.pem"
        subprocess.run([openssl_binary(), "genpkey", "-algorithm", "ED25519", "-out", self.key],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.key.chmod(0o600)
        self.public = self.root / "release.pub"
        write_public_key(self.public, key_file=self.key)
        self.version = Version("1.2.3", 7)
        self.candidate = self.root / "candidate"
        self.candidate.mkdir()
        for index, target in enumerate(sorted(TARGETS)):
            (self.candidate / artifact_name(self.version, *target)).write_bytes(
                f"update artifact {index}".encode())
        self.dmg = self.candidate / artifact_name(self.version, "macos", "arm64", "dmg")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def manifest(self, *, signed: bool = True, channel: str = "stable") -> dict:
        return build_manifest(
            self.candidate, self.version,
            "https://github.com/devmil/gitlama/releases/download/v1.2.3-7", channel,
            notes=("One <b>note</b> & more",),
            sign_update=(lambda path: sign_update_archive(path, key_file=self.key))
            if signed else None,
        )

    def test_only_the_update_package_is_signed_and_the_signature_verifies(self) -> None:
        document = self.manifest()
        signed = [asset for asset in document["latest"]["assets"] if "update_signature" in asset]
        self.assertEqual([asset["file"] for asset in signed], [self.dmg.name])
        asset = select_asset(encode(document), platform="macos", architecture="arm64", format_="dmg")
        verify_update_signature(self.dmg, asset, self.public)
        self.dmg.write_bytes(self.dmg.read_bytes() + b"tampered")
        with self.assertRaisesRegex(ValueError, "update signature is invalid"):
            verify_update_signature(self.dmg, asset, self.public)

    def test_missing_malformed_and_misplaced_update_signatures_fail(self) -> None:
        unsigned = self.manifest(signed=False)
        asset = select_asset(encode(unsigned), platform="macos", architecture="arm64", format_="dmg")
        self.assertIsNone(asset.update_signature)
        with self.assertRaisesRegex(ValueError, "no update signature"):
            verify_update_signature(self.dmg, asset, self.public)
        signed = self.manifest()
        for mutate, message in (
            (lambda asset: asset.update(update_signature="not base64!"), "not valid base64"),
            (lambda asset: asset.update(update_signature=base64.b64encode(b"x" * 63).decode()),
             "invalid length"),
            (lambda asset: asset.update(update_signature=7), "update signature is invalid"),
        ):
            changed = copy.deepcopy(signed)
            for record in (changed["latest"], changed["releases"][0]):
                mutate(next(item for item in record["assets"] if item["format"] == "dmg"))
            with self.assertRaisesRegex(ValueError, message):
                parse_manifest(encode(changed))
        misplaced = copy.deepcopy(signed)
        for record in (misplaced["latest"], misplaced["releases"][0]):
            source = next(item for item in record["assets"] if item["format"] == "dmg")
            next(item for item in record["assets"] if item["format"] == "msi")[
                "update_signature"] = source["update_signature"]
        with self.assertRaisesRegex(ValueError, "must not carry an update signature"):
            parse_manifest(encode(misplaced))

    def test_appcast_lists_signed_packages_and_marks_beta(self) -> None:
        feed = ET.fromstring(build_appcast(self.manifest()))
        items = feed.findall("channel/item")
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertEqual(item.findtext("sparkle:version", namespaces=NAMESPACE), "7")
        self.assertEqual(item.findtext("sparkle:shortVersionString", namespaces=NAMESPACE), "1.2.3")
        self.assertEqual(item.findtext("sparkle:minimumSystemVersion", namespaces=NAMESPACE), "13.0")
        self.assertIsNone(item.find("sparkle:channel", NAMESPACE))
        self.assertEqual(item.findtext("description"),
                         "<ul><li>One &lt;b&gt;note&lt;/b&gt; &amp; more</li></ul>")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("length"), str(self.dmg.stat().st_size))
        self.assertTrue(enclosure.get("url").endswith("/" + self.dmg.name))
        self.assertTrue(enclosure.get("url").startswith("https://github.com/"))
        self.assertEqual(len(base64.b64decode(enclosure.get(SIGNATURE), validate=True)), 64)

        self.version = Version("1.3.0-beta.1", 8)
        for index, target in enumerate(sorted(TARGETS)):
            (self.candidate / artifact_name(Version("1.2.3", 7), *target)).unlink()
            (self.candidate / artifact_name(self.version, *target)).write_bytes(b"beta")
        beta = ET.fromstring(build_appcast(self.manifest(channel="beta")))
        self.assertEqual(
            beta.findtext("channel/item/sparkle:channel", namespaces=NAMESPACE), "beta")

    def test_unsigned_releases_never_enter_the_appcast(self) -> None:
        feed = ET.fromstring(build_appcast(self.manifest(signed=False)))
        self.assertEqual(feed.findall("channel/item"), [])

    def test_website_index_publishes_the_appcast_before_the_pointer(self) -> None:
        manifest = self.root / "metadata.json"
        manifest.write_bytes(encode(self.manifest()))
        signature = self.root / "metadata.json.sig"
        sign_manifest(manifest, signature, key_file=self.key)
        receipt = self.root / "receipt.json"
        write_receipt(receipt, manifest, "v1.2.3-7")
        site = self.root / "site"
        (site / "_data").mkdir(parents=True)
        sync_index(site, manifest, signature, self.public, receipt, "v1.2.3-7")
        document, _ = verify_manifest(manifest, signature, self.public)
        self.assertEqual((site / "appcast.xml").read_bytes(), build_appcast(document))
        source = (ROOT / "scripts/lib/release_website.py").read_text(encoding="utf-8")
        self.assertLess(source.index("webfront / APPCAST_FILE"),
                        source.index('_atomic(data / "releases.json", manifest.read_bytes())'))

    def test_checked_in_appcast_matches_the_checked_in_signed_index(self) -> None:
        index = ROOT / "webfront/_data/releases.json"
        if not index.exists():
            # The unreleased hard transition advertises no old-product packages.
            self.assertFalse((ROOT / "release/metadata.json").exists())
            feed = ET.fromstring((ROOT / "webfront/appcast.xml").read_bytes())
            self.assertEqual(feed.findall("channel/item"), [])
            return
        document, _ = verify_manifest(
            index, ROOT / "webfront/_data/releases.json.sig",
            ROOT / "release/northspline-release-ed25519.pub")
        self.assertEqual((ROOT / "webfront/appcast.xml").read_bytes(), build_appcast(document))

    def test_shared_fixtures_are_fresh_and_verify_with_the_real_verifier(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/generate-release-fixture.py"), "--check"],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        raw = (FIXTURES / "release_index.json").read_bytes()
        self.assertNotIn(b"\r", raw)
        document, releases = parse_manifest(raw)
        self.assertEqual([release[0].build for release in releases], [42, 41, 40])
        public = FIXTURES / "release_test_only.pub"
        self.assertNotEqual(public.read_bytes(),
                            (ROOT / "release/northspline-release-ed25519.pub").read_bytes())
        feed = ET.fromstring((FIXTURES / "appcast.xml").read_bytes())
        items = feed.findall("channel/item")
        self.assertEqual([item.findtext("sparkle:version", namespaces=NAMESPACE) for item in items],
                         ["42", "41"])
        for item, release in zip(items, releases):
            asset = next(value for value in release if value.format == "dmg")
            self.assertEqual(item.find("enclosure").get(SIGNATURE), asset.update_signature)
            artifact = self.root / asset.file
            artifact.write_bytes(fixture_artifact(asset.version, asset.build))
            self.assertEqual(artifact.stat().st_size, asset.bytes)
            verify_update_signature(artifact, asset, public)

    def test_application_pins_the_feed_and_the_release_trust_root(self) -> None:
        with (ROOT / "macos/Runner/Info.plist").open("rb") as stream:
            plist = plistlib.load(stream)
        trust_root = (ROOT / "release/northspline-release-ed25519.pub").read_text(
            encoding="utf-8").strip()
        self.assertEqual(plist["SUPublicEDKey"], trust_root)
        self.assertEqual(plist["SUFeedURL"], FEED_URL)
        updater = (ROOT / "lib/repositories/impl/native_app_updater_repository.dart").read_text(
            encoding="utf-8")
        self.assertIn(f"'{FEED_URL}'", updater)
        index = (ROOT / "lib/repositories/impl/native_release_index_repository.dart").read_text(
            encoding="utf-8")
        self.assertIn(f"'{RELEASES_URL}'", index)
        self.assertIn("'https://devmil.de/gitlama/_data/releases.json'", index)
        qualifier = (ROOT / "scripts/qualify-macos-package.py").read_text(encoding="utf-8")
        self.assertIn('"SUPublicEDKey"', qualifier)
        self.assertIn('"SUFeedURL"', qualifier)

    def test_sparkle_is_pinned_to_one_resolved_revision(self) -> None:
        project = (ROOT / "macos/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        requirement = re.search(
            r'repositoryURL = "https://github.com/sparkle-project/Sparkle";\s*'
            r"requirement = \{\s*kind = exactVersion;\s*version = ([0-9.]+);", project)
        self.assertIsNotNone(requirement)
        for location in ("macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                         "macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"):
            pins = json.loads((ROOT / location).read_text(encoding="utf-8"))["pins"]
            sparkle = [pin for pin in pins if pin["identity"] == "sparkle"]
            self.assertEqual(len(sparkle), 1, location)
            self.assertEqual(sparkle[0]["state"]["version"], requirement.group(1))
            self.assertRegex(sparkle[0]["state"]["revision"], r"^[0-9a-f]{40}$")
        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        self.assertIn(f"## Sparkle {requirement.group(1)}", notices)
        self.assertIn("Copyright (c) 2006-2013 Andy Matuschak.", notices)

    def test_release_workflow_signs_verifies_and_commits_the_feed(self) -> None:
        publisher = (ROOT / "scripts/publish-candidate.sh").read_text(encoding="utf-8")
        self.assertIn('--update-key-file "$GITLAMA_RELEASE_PRIVATE_KEY_FILE"', publisher)
        self.assertIn("--require-update-signature", publisher)
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("webfront/_data webfront/appcast.xml", workflow)
        self.assertNotIn("sign_update", workflow)


if __name__ == "__main__":
    unittest.main()
