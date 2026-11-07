"""Append-only GitHub release reconciliation with byte-for-byte verification."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Protocol

from .release_manifest import sha256
from .release_verification import MAX_MANIFEST_BYTES, parse_manifest, verify_signature


MAX_JSON_BYTES = 1024 * 1024
PUBLIC_KEY_NAME = "northspline-release-ed25519.pub"
SIDECARS = ("metadata.json", "metadata.json.sig", PUBLIC_KEY_NAME)
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


class ApiError(ValueError):
    """A deliberately redacted remote-host failure."""


class ReleaseApi(Protocol):
    def get_release(self, tag: str) -> dict[str, Any] | None: ...
    def create_draft(self, tag: str, source_sha: str, body: str) -> dict[str, Any]: ...
    def list_assets(self, release_id: int) -> list[dict[str, Any]]: ...
    def upload(self, release_id: int, path: Path) -> dict[str, Any]: ...
    def download(self, asset: dict[str, Any], path: Path, maximum: int) -> None: ...
    def publish(self, release_id: int, body: str) -> dict[str, Any]: ...


class GitHubReleases:
    """GitHub Releases of one repository: the authoritative, append-only release host.

    Drafts are invisible to ``/releases/tags/{tag}``, so a release is found in the
    repository's release list. Asset bytes are read through the API asset URL; GitHub
    redirects that to its storage host, and curl drops the token on that redirect.
    """

    API = "https://api.github.com"
    UPLOADS = "https://uploads.github.com"

    def __init__(self, repository: str, token: str) -> None:
        if REPOSITORY.fullmatch(repository) is None:
            raise ValueError("invalid GitHub release repository")
        if not token or len(token) > 8192 or any(ord(c) < 33 or ord(c) > 126 for c in token):
            raise ValueError("invalid GitHub release token")
        self.repository = repository
        self.base = f"{self.API}/repos/{repository}"
        self.token = token

    def _request(self, method: str, path: str, payload: Any = None,
                 *, optional: bool = False) -> Any:
        data = json.dumps(payload).encode() if payload is not None else None
        headers = {"Accept": "application/vnd.github+json",
                   "Authorization": f"Bearer {self.token}",
                   "User-Agent": "GitLama-release/1",
                   "X-GitHub-Api-Version": "2022-11-28"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        try:
            request = urllib.request.Request(self.base + path, data=data,
                                             headers=headers, method=method)
            with urllib.request.urlopen(request, timeout=120) as response:
                raw = response.read(MAX_JSON_BYTES + 1)
        except urllib.error.HTTPError as error:
            if optional and error.code == 404:
                return None
            raise ApiError(f"GitHub release API returned HTTP {error.code}") from None
        except (OSError, ValueError):
            raise ApiError("GitHub release API transport failed") from None
        if len(raw) > MAX_JSON_BYTES:
            raise ApiError("GitHub release API response is too large")
        try:
            return json.loads(raw)
        except (UnicodeError, ValueError):
            raise ApiError("GitHub release API returned invalid JSON") from None

    def get_release(self, tag: str) -> dict[str, Any] | None:
        for page in range(1, 11):
            values = self._request("GET", f"/releases?per_page=100&page={page}")
            if not isinstance(values, list) or any(not isinstance(item, dict) for item in values):
                raise ApiError("GitHub returned an invalid release list")
            matches = [item for item in values if item.get("tag_name") == tag]
            if len(matches) > 1:
                raise ApiError("GitHub has more than one release for the tag")
            if matches:
                return matches[0]
            if len(values) < 100:
                return None
        raise ApiError("GitHub release list is too long to search")

    def create_draft(self, tag: str, source_sha: str, body: str) -> dict[str, Any]:
        value = self._request("POST", "/releases", {
            "tag_name": tag, "target_commitish": source_sha,
            "name": f"GitLama {tag[1:]}", "body": body,
            "draft": True, "prerelease": "-beta." in tag or "-rc." in tag,
        })
        if not isinstance(value, dict):
            raise ApiError("GitHub did not return a release")
        return value

    def list_assets(self, release_id: int) -> list[dict[str, Any]]:
        value = self._request("GET", f"/releases/{release_id}/assets?per_page=100&page=1")
        if not isinstance(value, list) or len(value) >= 100 or any(not isinstance(item, dict) for item in value):
            raise ApiError("GitHub returned an invalid release asset list")
        return value

    def upload(self, release_id: int, path: Path) -> dict[str, Any]:
        url = (f"{self.UPLOADS}/repos/{self.repository}/releases/{release_id}/assets?"
               + urllib.parse.urlencode({"name": path.name}))
        config = f'header = "Authorization: Bearer {self.token}"\n'
        result = subprocess.run([
            "curl", "--fail-with-body", "--silent", "--show-error", "--no-location",
            "--request", "POST", "--config", "-", "--header", "Accept: application/vnd.github+json",
            "--header", "Content-Type: application/octet-stream", "--data-binary", f"@{path}", url,
        ], input=config, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
           timeout=1800, check=False)
        if result.returncode != 0:
            raise ApiError(f"GitHub release upload failed for {path.name}")
        if len(result.stdout.encode()) > MAX_JSON_BYTES:
            raise ApiError("GitHub upload response is too large")
        try:
            value = json.loads(result.stdout)
        except (UnicodeError, ValueError):
            raise ApiError("GitHub upload returned invalid JSON") from None
        if not isinstance(value, dict):
            raise ApiError("GitHub upload returned an invalid asset")
        return value

    def download(self, asset: dict[str, Any], path: Path, maximum: int) -> None:
        url = asset.get("url")
        if not isinstance(url, str) or not url.startswith(f"{self.base}/releases/assets/"):
            raise ApiError("GitHub release asset URL is outside the configured repository")
        config = f'header = "Authorization: Bearer {self.token}"\n'
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
        try:
            # curl sends the token only to the API host, not to the storage host
            # GitHub redirects to.
            result = subprocess.run([
                "curl", "--fail", "--silent", "--show-error", "--location",
                "--proto", "=https", "--proto-redir", "=https",
                "--max-filesize", str(maximum), "--config", "-",
                "--header", "Accept: application/octet-stream",
                "--output", str(temporary), url,
            ], input=config, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
               timeout=1800, check=False)
            if result.returncode != 0:
                raise ApiError("GitHub release asset download failed")
            if temporary.stat().st_size > maximum:
                raise ApiError("GitHub release asset exceeds its signed size")
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)

    def publish(self, release_id: int, body: str) -> dict[str, Any]:
        release = self._request("GET", f"/releases/{release_id}")
        if not isinstance(release, dict):
            raise ApiError("GitHub did not return the release")
        value = self._request("PATCH", f"/releases/{release_id}", {
            "draft": False, "body": body,
            # Only a stable release becomes the repository's latest release.
            "make_latest": "false" if release.get("prerelease") else "true",
        })
        if not isinstance(value, dict):
            raise ApiError("GitHub did not confirm release publication")
        return value


def _identity(path: Path) -> tuple[int, str]:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"release attachment is not a regular file: {path.name}")
    return path.stat().st_size, sha256(path)


def _signed_document(directory: Path, trusted_public_key: Path,
                     tag: str) -> tuple[dict[str, Any], list[Any]]:
    local_public = directory / PUBLIC_KEY_NAME
    if local_public.read_bytes() != trusted_public_key.read_bytes():
        raise ValueError("candidate public key differs from the versioned trust root")
    raw = verify_signature(directory / SIDECARS[0], directory / SIDECARS[1], trusted_public_key)
    document, releases = parse_manifest(raw)
    if document["latest"]["tag"] != tag:
        raise ValueError("signed metadata does not match the requested tag")
    return document, releases


def release_body(directory: Path, trusted_public_key: Path, tag: str) -> str:
    """The release page text: the signed notes, as the mirror and feed show them."""
    document, _ = _signed_document(directory, trusted_public_key, tag)
    notes = document["latest"].get("notes") or []
    return "\n".join(f"- {note}" for note in notes) or "Signed GitLama release."


def signed_file_identities(directory: Path, trusted_public_key: Path,
                           tag: str) -> dict[str, tuple[int, str]]:
    _, releases = _signed_document(directory, trusted_public_key, tag)
    expected = {asset.file: (asset.bytes, asset.sha256) for asset in releases[0]}
    expected.update({name: _identity(directory / name) for name in SIDECARS})
    return expected


def expected_files(directory: Path, trusted_public_key: Path, tag: str) -> dict[str, tuple[int, str]]:
    expected = signed_file_identities(directory, trusted_public_key, tag)
    actual = {path.name for path in directory.iterdir() if path.is_file()}
    if actual != set(expected):
        raise ValueError("candidate directory must contain exactly the signed release attachments")
    for name, identity in expected.items():
        if _identity(directory / name) != identity:
            raise ValueError(f"local release attachment bytes differ for {name}")
    return expected


def _release(api: ReleaseApi, tag: str, source_sha: str,
             body: str | None) -> dict[str, Any]:
    release = api.get_release(tag)
    if release is None:
        if body is None:
            raise ValueError("GitHub release does not exist")
        release = api.create_draft(tag, source_sha, body)
    if (type(release.get("id")) is not int or release.get("tag_name") != tag
            or release.get("target_commitish") != source_sha):
        raise ValueError("GitHub release identity differs from the immutable candidate")
    return release


def _assets(api: ReleaseApi, release_id: int) -> dict[str, dict[str, Any]]:
    values = api.list_assets(release_id)
    by_name = {item.get("name"): item for item in values}
    if len(by_name) != len(values) or any(not isinstance(name, str) for name in by_name):
        raise ValueError("GitHub release has duplicate or invalid attachment names")
    return by_name


def reconcile(api: ReleaseApi, command: str, tag: str, source_sha: str,
              directory: Path, trusted_public_key: Path) -> None:
    if command not in {"stage", "recover", "verify", "publish"}:
        raise ValueError("unsupported GitHub reconciliation command")
    body = release_body(directory, trusted_public_key, tag) if command == "stage" else None
    release = _release(api, tag, source_sha, body)
    release_id = release["id"]
    remote = _assets(api, release_id)
    directory.mkdir(parents=True, exist_ok=True)
    if command == "recover":
        with tempfile.TemporaryDirectory(dir=directory) as temporary_name:
            temporary = Path(temporary_name)
            for name, maximum in zip(SIDECARS,
                                     (MAX_MANIFEST_BYTES, 256, 256)):
                if name not in remote:
                    raise ValueError("GitHub draft lacks signed metadata required for recovery")
                api.download(remote[name], temporary / name, maximum)
            for name in SIDECARS:
                target = directory / name
                if target.exists() and target.read_bytes() != (temporary / name).read_bytes():
                    raise ValueError(f"retained sidecar differs for {name}")
                if not target.exists():
                    (temporary / name).replace(target)
        signed = signed_file_identities(directory, trusted_public_key, tag)
        if set(remote) - set(signed):
            raise ValueError("GitHub release contains unexpected attachments")
        for name, identity in signed.items():
            target = directory / name
            if target.exists():
                if _identity(target) != identity:
                    raise ValueError(f"retained attachment differs for {name}")
                continue
            asset = remote.get(name)
            if asset is None:
                raise ValueError("GitHub release is incomplete and original bytes are unavailable")
            api.download(asset, target, identity[0])
            if _identity(target) != identity:
                raise ValueError(f"recovered attachment bytes differ for {name}")
    expected = expected_files(directory, trusted_public_key, tag)
    if set(remote) - set(expected):
        raise ValueError("GitHub release contains unexpected attachments")
    missing = set(expected) - set(remote)
    if missing and command in {"verify", "publish"}:
        raise ValueError("GitHub release is incomplete")
    if missing and command == "stage" and release.get("draft") is not True:
        raise ValueError("published GitHub releases cannot receive missing attachments")
    with tempfile.TemporaryDirectory(dir=directory) as temporary_name:
        verification = Path(temporary_name)
        for name, identity in expected.items():
            asset = remote.get(name)
            if asset is None:
                if command == "recover":
                    raise ValueError("GitHub release is incomplete and original bytes are unavailable")
                asset = api.upload(release_id, directory / name)
                remote[name] = asset
            if asset.get("name") != name or asset.get("size") != identity[0]:
                raise ValueError(f"GitHub attachment identity differs for {name}")
            api.download(asset, verification / name, identity[0])
            if _identity(verification / name) != identity:
                raise ValueError(f"GitHub attachment bytes differ for {name}")
    confirmed = _assets(api, release_id)
    if set(confirmed) != set(expected):
        raise ValueError("GitHub attachment set changed during verification")
    if command == "publish":
        published = api.publish(release_id, release_body(directory, trusted_public_key, tag))
        if published.get("draft") is not False or published.get("tag_name") != tag:
            raise ValueError("GitHub did not confirm immutable publication")
