#!/usr/bin/env python3
"""Stage, recover, verify, or publish an immutable GitHub release."""

import argparse
import os
import sys
from pathlib import Path

from lib.release_hosts import GitHubReleases, reconcile


def main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("stage", "recover", "verify", "publish"))
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--public-key-file", type=Path, required=True)
    parser.add_argument("--token-env", default="GITHUB_RELEASE_TOKEN")
    options = parser.parse_args(arguments)
    api = GitHubReleases(options.repository, os.environ.get(options.token_env, ""))
    reconcile(api, options.command, options.tag, options.source_sha,
              options.directory, options.public_key_file)
    print(f"GitHub release {options.command} completed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        raise SystemExit(f"release publication failed: {error}") from None
