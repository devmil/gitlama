#!/usr/bin/env python3
"""Capture the static website at the canonical responsive widths."""

import argparse
import hashlib
import json
import struct
import subprocess
import tempfile
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
WIDTHS = (390, 768, 1280, 1440)


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, format, *args): return


def capture(chrome: Path, profile: str, url: str, width: int, path: Path) -> bytes:
    """Capture one complete PNG and reap browsers that linger after writing it."""
    process = subprocess.Popen([
        str(chrome), "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--no-first-run", "--disable-background-networking",
        "--force-device-scale-factor=1", f"--user-data-dir={profile}",
        f"--window-size={width},1100", f"--screenshot={path}",
        "--virtual-time-budget=1200", url,
    ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 40
    raw = b""
    try:
        while time.monotonic() < deadline:
            if path.is_file():
                raw = path.read_bytes()
                if raw.startswith(b"\x89PNG\r\n\x1a\n") and raw.endswith(b"IEND\xaeB`\x82"):
                    break
            if process.poll() is not None:
                break
            time.sleep(0.1)
        if not raw.endswith(b"IEND\xaeB`\x82"):
            output, _ = process.communicate(timeout=1)
            detail = output.decode("utf-8", errors="replace")[-1000:]
            raise ValueError(f"Chrome website capture failed at {width}px: {detail}")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
    return raw


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chrome", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "build/qualification/website")
    options = parser.parse_args(); options.output.mkdir(parents=True, exist_ok=True)
    handler = lambda *args, **kwargs: Quiet(*args, directory=str(ROOT / "webfront"), **kwargs)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    captures = []
    try:
        with tempfile.TemporaryDirectory(prefix="gitlama-site-chrome-") as profile:
            for width in WIDTHS:
                path = options.output / f"index-{width}.png"
                path.unlink(missing_ok=True)
                raw = capture(
                    options.chrome,
                    profile,
                    f"http://127.0.0.1:{server.server_port}/index.html",
                    width,
                    path,
                )
                if raw[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">I", raw[16:20])[0] != width:
                    raise ValueError("website capture has the wrong dimensions")
                captures.append({"viewport": width, "file": path.name, "bytes": len(raw),
                                 "sha256": hashlib.sha256(raw).hexdigest()})
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=5)
    report = {"schema": 1, "page": "webfront/index.html", "captures": captures}
    (options.output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(options.output / "report.json"); return 0


if __name__ == "__main__": raise SystemExit(main())
