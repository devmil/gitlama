import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.lib.package_contract import TARGETS, Version, artifact_name
from scripts.lib.release_hosts import PUBLIC_KEY_NAME, ApiError, GitHubReleases, reconcile
from scripts.lib.release_manifest import build_manifest, encode
from scripts.lib.release_signing import openssl_binary, sign_manifest, write_public_key


class MemoryReleaseApi:
    def __init__(self) -> None:
        self.release = None
        self.assets = {}
        self.fail_after = None
        self.uploads = 0

    def get_release(self, tag):
        return self.release if self.release and self.release["tag_name"] == tag else None

    def create_draft(self, tag, source_sha, body):
        self.release = {"id": 1, "tag_name": tag, "target_commitish": source_sha, "draft": True,
                        "body": body}
        return dict(self.release)

    def list_assets(self, release_id):
        return [{"name": name, "size": len(value), "memory": value}
                for name, value in self.assets.items()]

    def upload(self, release_id, path):
        if self.fail_after is not None and self.uploads >= self.fail_after:
            raise ValueError("simulated upload outage")
        value = path.read_bytes()
        self.assets[path.name] = value
        self.uploads += 1
        return {"name": path.name, "size": len(value), "memory": value}

    def download(self, asset, path, maximum):
        value = self.assets[asset["name"]]
        if len(value) > maximum:
            raise ValueError("download too large")
        path.write_bytes(value)

    def publish(self, release_id, body):
        self.release["draft"] = False
        self.release["body"] = body
        return dict(self.release)


class ReleaseHostsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.key = self.root / "key.pem"
        subprocess.run([openssl_binary(), "genpkey", "-algorithm", "ED25519", "-out", self.key], check=True)
        self.key.chmod(0o600)
        self.public = self.root / PUBLIC_KEY_NAME
        write_public_key(self.public, key_file=self.key)
        self.candidate = self.root / "candidate"
        self.candidate.mkdir()
        version = Version("1.2.3", 7)
        for index, target in enumerate(TARGETS):
            (self.candidate / artifact_name(version, *target)).write_bytes(f"package-{index}".encode())
        document = build_manifest(self.candidate, version,
                                  "https://github.com/devmil/gitlama/releases/download/v1.2.3-7",
                                  "stable", notes=("First change.", "Second change."))
        (self.candidate / "metadata.json").write_bytes(encode(document))
        sign_manifest(self.candidate / "metadata.json", self.candidate / "metadata.json.sig",
                      key_file=self.key)
        shutil.copyfile(self.public, self.candidate / PUBLIC_KEY_NAME)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_partial_stage_resumes_and_publish_requires_complete_verified_set(self) -> None:
        api = MemoryReleaseApi()
        api.fail_after = 3
        with self.assertRaisesRegex(ValueError, "simulated"):
            reconcile(api, "stage", "v1.2.3-7", "a" * 40, self.candidate, self.public)
        self.assertEqual(len(api.assets), 3)
        self.assertTrue(api.release["draft"])
        api.fail_after = None
        reconcile(api, "stage", "v1.2.3-7", "a" * 40, self.candidate, self.public)
        reconcile(api, "verify", "v1.2.3-7", "a" * 40, self.candidate, self.public)
        reconcile(api, "publish", "v1.2.3-7", "a" * 40, self.candidate, self.public)
        self.assertFalse(api.release["draft"])
        self.assertEqual(len(api.assets), 9)

    def test_release_page_shows_the_signed_notes(self) -> None:
        api = MemoryReleaseApi()
        reconcile(api, "stage", "v1.2.3-7", "e" * 40, self.candidate, self.public)
        self.assertEqual(api.release["body"], "- First change.\n- Second change.")
        api.release["body"] = "Signed GitLama release."
        reconcile(api, "publish", "v1.2.3-7", "e" * 40, self.candidate, self.public)
        self.assertEqual(api.release["body"], "- First change.\n- Second change.")

    def test_mismatch_and_unexpected_remote_asset_fail_without_site_change(self) -> None:
        api = MemoryReleaseApi()
        reconcile(api, "stage", "v1.2.3-7", "b" * 40, self.candidate, self.public)
        site = self.root / "site-index.json"
        site.write_text("unchanged", encoding="utf-8")
        before = site.read_bytes()
        first = next(iter(api.assets))
        api.assets[first] = b"changed"
        with self.assertRaisesRegex(ValueError, "identity differs|bytes differ"):
            reconcile(api, "verify", "v1.2.3-7", "b" * 40, self.candidate, self.public)
        self.assertEqual(site.read_bytes(), before)
        api.assets[first] = (self.candidate / first).read_bytes()
        api.assets["unexpected.bin"] = b"unexpected"
        with self.assertRaisesRegex(ValueError, "unexpected"):
            reconcile(api, "verify", "v1.2.3-7", "b" * 40, self.candidate, self.public)
        self.assertEqual(site.read_bytes(), before)

    def test_recovery_materializes_original_bytes_only(self) -> None:
        api = MemoryReleaseApi()
        reconcile(api, "stage", "v1.2.3-7", "c" * 40, self.candidate, self.public)
        recovered = self.root / "recovered"
        reconcile(api, "recover", "v1.2.3-7", "c" * 40, recovered, self.public)
        self.assertEqual({path.name for path in recovered.iterdir()}, set(api.assets))
        for name, value in api.assets.items():
            self.assertEqual((recovered / name).read_bytes(), value)

    def test_github_finds_draft_releases_by_tag_and_rejects_duplicates(self) -> None:
        api = GitHubReleases("owner/project", "token")
        pages = {1: [{"id": 4, "tag_name": "v1.2.2-6", "draft": False}],}
        api._request = lambda method, path, payload=None, optional=False: pages.get(
            int(path.rsplit("page=", 1)[1]), [])
        self.assertIsNone(api.get_release("v1.2.3-7"))
        pages[1].append({"id": 5, "tag_name": "v1.2.3-7", "draft": True})
        self.assertEqual(api.get_release("v1.2.3-7")["id"], 5)
        pages[1].append({"id": 6, "tag_name": "v1.2.3-7", "draft": True})
        with self.assertRaisesRegex(ApiError, "more than one"):
            api.get_release("v1.2.3-7")

    def test_github_downloads_only_assets_of_the_configured_repository(self) -> None:
        api = GitHubReleases("owner/project", "token")
        target = self.root / "asset"
        for url in ("https://api.github.com/repos/other/project/releases/assets/1",
                    "https://example.test/asset", None):
            with self.assertRaisesRegex(ApiError, "outside the configured repository"):
                api.download({"url": url}, target, 10)
        self.assertFalse(target.exists())

    def test_github_rejects_invalid_coordinates_and_tokens(self) -> None:
        for repository, token in (("owner", "token"), ("owner/project", ""),
                                  ("owner/project", "has space")):
            with self.assertRaises(ValueError):
                GitHubReleases(repository, token)

if __name__ == "__main__":
    unittest.main()
