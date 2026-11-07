#!/usr/bin/env python3
"""Render and validate the checked-in GitLama brand derivatives."""

from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets" / "brand"
ICON_SIZES = (16, 32, 48, 64, 128, 256, 512, 1024)
TILE_SIZES = (64, 256)
WEB_SIZES = (32, 64, 512)
WEB_LAMAS = ("proud", "standing-nod", "standing", "resting", "nod", "signature", "proud-shades-up")
# The hero's antics script and styles, vendored unchanged.
WEB_ANTICS = ("lama-antics.js", "lama-antics.css")


def render(source: Path, destination: Path, width: int, height: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "rsvg-convert",
            str(source),
            "-o",
            str(destination),
            "-w",
            str(width),
            "-h",
            str(height),
        ],
        check=True,
    )


def png_header(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise RuntimeError(f"not a PNG: {path.relative_to(ROOT)}")
    width, height = struct.unpack(">II", data[16:24])
    return width, height, data[25]


def require_png(path: Path, width: int, height: int, color_type: int) -> None:
    observed = png_header(path)
    expected = (width, height, color_type)
    if observed != expected:
        raise RuntimeError(
            f"unexpected PNG header for {path.relative_to(ROOT)}: "
            f"expected {expected}, observed {observed}"
        )


# Copy on the brand ground, matching the website stage (--brand-ink and
# --brand-muted in webfront/style.css; both clear 4.5:1 on the ground).
CARD_TEXT = (
    '<text x="64" y="{y0}" font-family="Arial,sans-serif" font-size="64" font-weight="700" fill="#F4F7F8">GitLama</text>\n'
    '<text x="64" y="{y1}" font-family="Arial,sans-serif" font-size="28" fill="#A9BAC2">Your repository, in view.</text>\n'
    '<text x="64" y="{y2}" font-family="Arial,sans-serif" font-size="22" fill="#A9BAC2">by Devmil Solutions</text>'
)


def brand_ground() -> str:
    """The light brand ground (Meridian `brand`, GitLama's `fjord`).

    scripts/generate_meridian_theme.py --check keeps this reference equal to
    the pinned meridian_ui brand, so the card follows the brand, not a literal.
    """
    tokens = json.loads((ROOT / "docs/design-system/tokens/gitlama-tokens.json").read_text(encoding="utf-8"))
    return next(token["value"]["light"] for token in tokens["color"]["tokens"] if token["name"] == "fjord")


def write_card(target: Path, width: int, height: int, icon_x: int, icon_y: int, text_top: int) -> None:
    """Compose a social card: the vendored app icon as a rounded tile on the brand ground."""
    icon = (ROOT / "resources/brand/app-icon-gitlama.svg").read_text(encoding="utf-8")
    artwork = icon.split(">", 1)[1].rsplit("</svg>", 1)[0]
    target.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n'
        '<title>GitLama</title><desc>GitLama. Your repository, in view. By Devmil Solutions.</desc>\n'
        f'<rect width="{width}" height="{height}" fill="{brand_ground()}"/>\n'
        f'<svg x="{icon_x}" y="{icon_y}" width="320" height="320" viewBox="0 0 120 120">'
        '<clipPath id="tile"><rect width="120" height="120" rx="27"/></clipPath>'
        f'<g clip-path="url(#tile)">{artwork}</g></svg>\n'
        + CARD_TEXT.format(y0=text_top, y1=text_top + 70, y2=text_top + 120) + "</svg>\n",
        encoding="utf-8",
    )


def main() -> None:
    outputs: list[Path] = []
    # The full-bleed master is vendored from the brand repository; never edit the copy.
    shutil.copyfile(ROOT / "resources/brand/app-icon-gitlama.svg", BRAND / "icon.svg")
    shutil.copyfile(BRAND / "icon.svg", ROOT / "docs/design-system/assets/brand/gitlama-mark.svg")
    shutil.copyfile(ROOT / "resources/marketing/feature-graphic.svg", BRAND / "feature-graphic.svg")
    write_card(BRAND / "social-card.svg", 1200, 630, 790, 155, 260)
    def raster(source: Path, target: Path, size: int) -> None:
        render(source, target, size, size)
        subprocess.run(["magick", str(target), "-define", "png:color-type=6", str(target)], check=True)
        require_png(target, size, size, 6)
        outputs.append(target)

    small = ROOT / "resources/brand/tile-gitlama-small.svg"
    # icon-*: full-bleed, for the website. desktop-icon-*: rounded with a margin,
    # for Linux, Windows and the macOS catalog, which apply no mask.
    # tile-*: rounded without a margin, for the app icon shown inside the app.
    for size in ICON_SIZES:
        raster(small if size <= 24 else BRAND / "icon.svg", BRAND / f"icon-{size}.png", size)
        raster(small if size <= 24 else ROOT / "resources/brand/app-icon-gitlama-desktop.svg",
               BRAND / f"desktop-icon-{size}.png", size)
    for size in TILE_SIZES:
        raster(ROOT / "resources/brand/tile-gitlama.svg", BRAND / f"tile-{size}.png", size)

    contents = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
    for entry in json.loads(contents.read_text(encoding="utf-8"))["images"]:
        size = int(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x"))
        target = contents.parent / entry["filename"]
        shutil.copyfile(BRAND / f"desktop-icon-{size}.png", target)
        outputs.append(target)

    ico = ROOT / "windows/runner/resources/app_icon.ico"
    subprocess.run(
        [
            "magick",
            str(BRAND / "desktop-icon-256.png"),
            "-strip",
            "-define",
            "icon:auto-resize=256,128,64,48,32,16",
            str(ico),
        ],
        check=True,
    )
    outputs.append(ico)

    feature = BRAND / "feature-graphic.png"
    render(BRAND / "feature-graphic.svg", feature, 1024, 500)
    require_png(feature, 1024, 500, 2)
    outputs.append(feature)

    social = BRAND / "social-card.png"
    render(BRAND / "social-card.svg", social, 1200, 630)
    require_png(social, 1200, 630, 2)
    outputs.append(social)

    for size in WEB_SIZES:
        target = ROOT / f"webfront/assets/icon-{size}.png"
        shutil.copyfile(BRAND / f"icon-{size}.png", target)
        outputs.append(target)
    social_target = ROOT / "webfront/assets/social-card.png"
    shutil.copyfile(social, social_target)
    outputs.append(social_target)
    feature_target = ROOT / "webfront/assets/feature-graphic.png"
    shutil.copyfile(feature, feature_target)
    outputs.append(feature_target)
    for pose in WEB_LAMAS:
        target = ROOT / f"webfront/assets/lama/lama-{pose}.svg"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / f"resources/brand/lama-{pose}.svg", target)
        outputs.append(target)
    for name in WEB_ANTICS:
        target = ROOT / f"webfront/assets/lama/{name}"
        shutil.copyfile(ROOT / f"resources/brand/web/{name}", target)
        outputs.append(target)

    sources = (
        BRAND / "icon.svg",
        BRAND / "feature-graphic.svg",
        BRAND / "social-card.svg",
        *sorted((ROOT / "resources/brand").rglob("*.*")),
    )
    records = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (*sources, *outputs)
    }
    (BRAND / "manifest.json").write_text(
        json.dumps(records, indent=2) + "\n", encoding="utf-8"
    )
    version_website()


def version_website() -> None:
    """Give changed website copies new asset URLs (see generate_webfront_versions.py)."""
    subprocess.run([sys.executable, str(ROOT / "scripts/generate_webfront_versions.py")], check=True)


if __name__ == "__main__":
    import sys
    if '--marketing-only' in sys.argv:
        shutil.copyfile(ROOT / "resources/marketing/feature-graphic.svg", BRAND / "feature-graphic.svg")
        render(BRAND / "feature-graphic.svg", BRAND / "feature-graphic.png", 1024, 500)
        require_png(BRAND / "feature-graphic.png", 1024, 500, 2)
        shutil.copyfile(BRAND / "feature-graphic.png", ROOT / "webfront/assets/feature-graphic.png")
        manifest = BRAND / "manifest.json"
        records = json.loads(manifest.read_text(encoding="utf-8"))
        for name in ["assets/brand/feature-graphic.svg", "assets/brand/feature-graphic.png", "webfront/assets/feature-graphic.png"]:
            records[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        manifest.write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
        version_website()
    else:
        main()
