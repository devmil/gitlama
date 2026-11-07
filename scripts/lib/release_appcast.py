"""Render the Sparkle appcast from a verified release manifest."""

from __future__ import annotations

from html import escape
from typing import Any
import xml.etree.ElementTree as ET

from .release_manifest import UPDATE_TARGETS


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SITE = "https://devmil.de/gitlama"
FEED_URL = f"{SITE}/appcast.xml"
RELEASES_URL = f"{SITE}/releases.html"


def _minimum_macos(asset: dict[str, Any]) -> str:
    # "macOS 13.0 and Git 2.39" -> "13.0"
    words = str(asset["minimum_system"]).split()
    if len(words) < 2 or words[0] != "macOS":
        raise ValueError("macOS release asset has no minimum system version")
    return words[1]


def build_appcast(document: dict[str, Any]) -> bytes:
    """Return deterministic appcast bytes for a parsed, verified manifest.

    A release enters the feed only with a signed update package. Beta items
    carry the beta channel, so stable subscribers never see them.
    """
    ET.register_namespace("sparkle", SPARKLE)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "GitLama"
    ET.SubElement(channel, "link").text = RELEASES_URL
    ET.SubElement(channel, "description").text = "GitLama updates for macOS"
    ET.SubElement(channel, "language").text = "en"
    releases = sorted(document["releases"], key=lambda item: item["build"], reverse=True)
    for release in releases:
        packages = [
            asset for asset in release["assets"]
            if (asset["platform"], asset["architecture"], asset["format"]) in UPDATE_TARGETS
            and asset.get("update_signature")
        ]
        if not packages:
            continue
        if len(packages) != 1:
            raise ValueError("release has more than one macOS update package")
        package = packages[0]
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = f"GitLama {release['version']}"
        ET.SubElement(item, "link").text = RELEASES_URL
        ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(release["build"])
        ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = release["version"]
        ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = _minimum_macos(package)
        if release["channel"] != "stable":
            ET.SubElement(item, f"{{{SPARKLE}}}channel").text = release["channel"]
        notes = release.get("notes") or []
        if notes:
            ET.SubElement(item, "description").text = (
                "<ul>" + "".join(f"<li>{escape(note)}</li>" for note in notes) + "</ul>"
            )
        ET.SubElement(item, "enclosure", {
            "url": package["url"],
            "length": str(package["bytes"]),
            "type": "application/octet-stream",
            f"{{{SPARKLE}}}edSignature": package["update_signature"],
        })
    ET.indent(rss, space="  ")
    return (b'<?xml version="1.0" encoding="utf-8"?>\n'
            + ET.tostring(rss, encoding="utf-8") + b"\n")
