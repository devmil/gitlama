#!/usr/bin/env python3
"""Version the website's mutable assets by content digest.

The site is served with plain file names, so a returning browser can keep a
cached stylesheet, script or image after a deployment changes it. Every local
asset reference in the pages and the stylesheet carries `?v=<digest>` of the
file's current bytes, so changed bytes always get a new URL.

Usage:
  python3 scripts/generate_webfront_versions.py          # rewrite references
  python3 scripts/generate_webfront_versions.py --check  # fail when stale
Run it after changing any file under webfront/ (scripts/generate-brand.py runs
it after copying brand derivatives).
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "webfront"
PAGES = ("index.html", "releases.html", "license.html", "privacy.html", "imprint.html",
         "de/privacy.html", "de/imprint.html")
STYLESHEET = "style.css"
PUBLIC_ORIGIN = "https://devmil.de/gitlama/"
VERSIONED = (".css", ".js", ".png", ".svg", ".woff2", ".ico", ".webp", ".jpg")
# A local reference in an attribute or url(), with an optional old version.
REFERENCE = re.compile(
    r'(?P<lead>(?:href|src|srcset|content)="|url\(\s*["\']?)'
    r'(?P<origin>' + re.escape(PUBLIC_ORIGIN) + r')?'
    r'(?P<up>(?:\.\./)*)'
    r'(?P<path>(?:assets/)?[A-Za-z0-9_./-]+?)'
    r'(?:\?v=[0-9a-f]*)?'
    r'(?=["\')\s])'
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def versioned(text: str, overrides: dict[str, bytes], page: str = "") -> str:
    """Version references in [text]; relative ones resolve from [page]'s directory."""
    directory = Path(page).parent

    def replace(match: re.Match[str]) -> str:
        path = match.group("path")
        up = match.group("up")
        if not path.endswith(VERSIONED) or path.startswith(("/", ".")):
            return match.group(0)
        if match.group("lead").startswith("content") and not match.group("origin"):
            return match.group(0)
        if match.group("origin") and up:
            return match.group(0)
        base = Path() if match.group("origin") else directory
        parts = list((base / up / path).parts)
        resolved: list[str] = []
        for part in parts:
            if part == "..":
                if not resolved:
                    return match.group(0)
                resolved.pop()
            else:
                resolved.append(part)
        key = "/".join(resolved)
        file = SITE / key
        data = overrides.get(key)
        if data is None:
            if not file.is_file():
                return match.group(0)
            data = file.read_bytes()
        return f'{match.group("lead")}{match.group("origin") or ""}{up}{path}?v={digest(data)}'

    return REFERENCE.sub(replace, text)


def expected() -> dict[Path, str]:
    """Every rewritten file and its content; the stylesheet first, then pages."""
    style = versioned((SITE / STYLESHEET).read_text(encoding="utf-8"), {})
    overrides = {STYLESHEET: style.encode("utf-8")}
    files = {SITE / STYLESHEET: style}
    for page in PAGES:
        files[SITE / page] = versioned((SITE / page).read_text(encoding="utf-8"), overrides, page)
    return files


def stale() -> list[str]:
    return [
        str(path.relative_to(ROOT))
        for path, text in expected().items()
        if path.read_text(encoding="utf-8") != text
    ]


def main() -> int:
    if "--check" in sys.argv:
        files = stale()
        if files:
            print(
                "Website asset versions are stale; run scripts/generate_webfront_versions.py: "
                + ", ".join(files),
                file=sys.stderr,
            )
            return 1
        print("Website asset versions match their content.")
        return 0
    for path, text in expected().items():
        if path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
