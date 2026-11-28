#!/usr/bin/env python3
"""Start a packaged GitLama offscreen and prove it renders its first window.

The executable must load Qt, its plugins and QML modules from the bundle
(qt.conf on Linux, the .app's Frameworks on macOS, windeployqt's layout on
Windows) and never a development fallback: the smoke clears the Qt search
variables a developer shell may set. The first window is saved as a PNG and
the application quits; a missing or empty image fails.
"""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("bundle", type=Path, help=".app on macOS, bundle directory on Linux/Windows")
parser.add_argument("--timeout", type=float, default=120)
args = parser.parse_args()
bundle = args.bundle.resolve()
relative = {
    "Darwin": "Contents/MacOS/GitLama",
    "Linux": "gitlama",
    "Windows": "gitlama.exe",
}[platform.system()]
executable = bundle / relative
if not executable.is_file():
    parser.error(f"packaged executable missing: {relative}")

with tempfile.TemporaryDirectory(prefix="gitlama-smoke-") as directory:
    temporary = Path(directory)
    shot = temporary / "first-window.png"
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("QT_", "QML_", "QML2_")) and key != "LD_LIBRARY_PATH"
    }
    environment.update(
        GITLAMA_PROFILE_ROOT=str(temporary / "profile"),
        GITLAMA_SCREENSHOT=f"{shot};size:1200x800;wait",
    )
    # Linux and Windows bundles carry the offscreen platform; a macOS app
    # renders through Cocoa in the runner's session.
    if any(bundle.glob("**/platforms/*qoffscreen*")) and platform.system() != "Darwin":
        environment["QT_QPA_PLATFORM"] = "offscreen"
    try:
        subprocess.run([str(executable)], cwd=temporary, env=environment, check=True,
                       timeout=args.timeout, stdout=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        sys.exit("packaged application did not render its first window in time")
    except subprocess.CalledProcessError as error:
        sys.exit(f"packaged application exited with status {error.returncode}")
    if not shot.is_file() or shot.stat().st_size == 0:
        sys.exit("packaged application rendered no first window")
print(f"native smoke passed: {relative}")
