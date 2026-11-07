#!/usr/bin/env python3
"""Create the immutable byte inventory for one complete candidate set."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from lib.package_contract import Version
from lib.release_recovery import build_state, STATE_NAME


ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    directory = arguments.directory.resolve()
    state = build_state(directory, Version.read(ROOT / "VERSION"))
    output = arguments.output.resolve() if arguments.output else directory / STATE_NAME
    if output.exists():
        raise RuntimeError("release state already exists")
    output.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
