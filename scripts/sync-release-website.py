#!/usr/bin/env python3
"""Write the verified public release index and update feed."""

import argparse
import sys
from pathlib import Path

from lib.release_website import sync_index, write_receipt


def main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    receipt = commands.add_parser("receipt")
    receipt.add_argument("--manifest", type=Path, required=True)
    receipt.add_argument("--tag", required=True)
    receipt.add_argument("--output", type=Path, required=True)
    index = commands.add_parser("index")
    index.add_argument("--webfront", type=Path, required=True)
    index.add_argument("--manifest", type=Path, required=True)
    index.add_argument("--signature", type=Path, required=True)
    index.add_argument("--public-key-file", type=Path, required=True)
    index.add_argument("--receipt", type=Path, required=True)
    index.add_argument("--tag", required=True)
    options = parser.parse_args(arguments)
    if options.command == "receipt":
        write_receipt(options.output, options.manifest, options.tag)
    else:
        sync_index(options.webfront, options.manifest, options.signature,
                   options.public_key_file, options.receipt, options.tag)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        raise SystemExit(f"release website: {error}") from None
