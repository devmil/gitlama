#!/usr/bin/env python3
"""Prepare or inspect one immutable GitLama release identity."""

from __future__ import annotations

import argparse
from datetime import date
import json
from pathlib import Path
import sys

from lib.package_contract import Version
from lib.release_git import create_annotated_tag, plan, require_clean, require_version_sync
from lib.release_prepare import BUMPS, CHANNELS, prepare_updates, released_notes, write_atomic
from lib.release_manifest import build_manifest, encode, merge
from lib.release_signing import PRIVATE_KEY_ENV, sign_manifest, sign_update_archive, write_public_key
from lib.release_verification import (
    parse_manifest, select_asset, verify_artifact, verify_manifest, verify_signature,
    verify_update_signature,
)


ROOT = Path(__file__).resolve().parent.parent


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("version")
    for name in ("plan", "prepare"):
        command = commands.add_parser(name)
        command.add_argument("--bump", required=True, choices=sorted(BUMPS))
        command.add_argument("--channel", required=True, choices=sorted(CHANNELS))
        if name == "prepare":
            command.add_argument("--date", type=date.fromisoformat, default=date.today())
    check = commands.add_parser("check")
    check.add_argument("--channel", required=True, choices=sorted(CHANNELS))
    tag = commands.add_parser("tag")
    tag.add_argument("--channel", required=True, choices=sorted(CHANNELS))
    manifest = commands.add_parser("manifest")
    manifest.add_argument("--directory", type=Path, required=True)
    manifest.add_argument("--base-url", required=True)
    manifest.add_argument("--channel", required=True, choices=sorted(CHANNELS))
    manifest.add_argument("--output", type=Path, required=True)
    manifest.add_argument("--notes", type=Path)
    manifest.add_argument("--previous-manifest", type=Path)
    manifest.add_argument("--previous-signature", type=Path)
    manifest.add_argument("--public-key-file", type=Path)
    manifest.add_argument("--update-key-file", type=Path,
                          help="sign the packages the in-app updater installs")
    manifest.add_argument("--update-key-env",
                          help="environment variable holding the update signing key")
    sign = commands.add_parser("sign")
    sign.add_argument("--manifest", type=Path, required=True)
    sign.add_argument("--signature", type=Path, required=True)
    sign.add_argument("--key-file", type=Path)
    sign.add_argument("--key-env", default=PRIVATE_KEY_ENV)
    public = commands.add_parser("public-key")
    public.add_argument("--output", type=Path, required=True)
    public.add_argument("--key-file", type=Path)
    public.add_argument("--key-env", default=PRIVATE_KEY_ENV)
    verify = commands.add_parser("verify")
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--signature", type=Path, required=True)
    verify.add_argument("--public-key-file", type=Path, required=True)
    verify.add_argument("--artifact", type=Path)
    verify.add_argument("--platform")
    verify.add_argument("--architecture")
    verify.add_argument("--format")
    verify.add_argument("--minimum-build", type=int, default=0)
    verify.add_argument("--require-update-signature", action="store_true",
                        help="also verify the signature the in-app updater checks")
    return root


def key_source(options: argparse.Namespace) -> dict[str, object]:
    return {"key_file": options.key_file} if options.key_file else {"key_environment": options.key_env}


def main(arguments: list[str]) -> int:
    options = parser().parse_args(arguments)
    version = Version.read(ROOT / "VERSION")
    if options.command == "version":
        print(f"{version.marketing}+{version.build}")
        return 0
    if options.command == "manifest":
        notes = ()
        if options.notes:
            notes = released_notes(options.notes.read_text(encoding="utf-8"), version)
        if options.update_key_file and options.update_key_env:
            raise ValueError("choose exactly one update signing key source")
        sign_update = None
        if options.update_key_file:
            sign_update = lambda path: sign_update_archive(path, key_file=options.update_key_file)
        elif options.update_key_env:
            sign_update = lambda path: sign_update_archive(
                path, key_environment=options.update_key_env)
        document = build_manifest(options.directory, version, options.base_url,
                                  options.channel, notes=notes, sign_update=sign_update)
        previous = (options.previous_manifest, options.previous_signature, options.public_key_file)
        if any(previous):
            if not all(previous):
                raise ValueError("previous manifest, signature and public key must be supplied together")
            raw = verify_signature(*previous)
            verified_previous, _ = parse_manifest(raw)
            document = merge(verified_previous, document)
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_bytes(encode(document))
        print(options.output)
        return 0
    if options.command == "sign":
        public = sign_manifest(options.manifest, options.signature, **key_source(options))
        print(f"signed with Ed25519 public key {public}")
        return 0
    if options.command == "public-key":
        write_public_key(options.output, **key_source(options))
        print(options.output)
        return 0
    if options.command == "verify":
        raw = verify_signature(options.manifest, options.signature, options.public_key_file)
        document, _ = verify_manifest(options.manifest, options.signature, options.public_key_file)
        if options.artifact:
            if not all((options.platform, options.architecture, options.format)):
                raise ValueError("artifact verification requires platform, architecture and format")
            asset = select_asset(raw, platform=options.platform,
                                 architecture=options.architecture,
                                 format_=options.format,
                                 minimum_build=options.minimum_build)
            verify_artifact(options.artifact, asset)
            if options.require_update_signature:
                verify_update_signature(options.artifact, asset, options.public_key_file)
        elif options.require_update_signature:
            raise ValueError("update signature verification requires an artifact")
        print(json.dumps({"tag": document["latest"]["tag"], "verified": True}, sort_keys=True))
        return 0
    if options.command in {"plan", "prepare"}:
        require_clean(ROOT)
        release_plan = plan(ROOT, options.bump, options.channel)
        if options.command == "prepare":
            if release_plan.mode == "recover":
                raise ValueError("existing tag recovery must not rewrite release files")
            if release_plan.mode == "prepare":
                updates = prepare_updates(
                    ROOT,
                    version,
                    release_plan.version,
                    options.channel,
                    options.date,
                )
                write_atomic(updates)
        print(release_plan.as_json())
        return 0
    if options.command == "check":
        require_version_sync(ROOT, version)
        checked = plan(ROOT, "none", options.channel)
        print(checked.as_json())
        return 0
    print(create_annotated_tag(ROOT, version, options.channel))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        raise SystemExit(f"release: {error}") from error
