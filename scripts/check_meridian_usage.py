#!/usr/bin/env python3
"""Fail when GitLama's QML bypasses the Meridian design system.

- Controls come from Meridian: Qt Quick Controls are used only for their
  attached scroll bars (filled with MeridianScrollBar) and enum constants;
  the few Templates bases GitLama builds on are listed below with a reason.
- No local copy of a Meridian component (a Meridian*.qml in qml/GitLama).
- Colours come from the theme: no colour literal outside the git-domain
  palette, no Qt.rgba of literal channels.
- Sizes come from Meridian's scales or GitLamaLayout: no literal geometry
  other than 0 and 1 outside the layout file.

Usage: check_meridian_usage.py [--report]
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
QML = ROOT / "qml/GitLama"

# Templates bases that have no Meridian component, each with its reason.
TEMPLATE_BASES = {
    ("CommandPalette.qml", "T.Popup"): "the command palette's own modal sheet",
    ("CommandPalette.qml", "T.Overlay"): "the command palette's scrim",
    ("RepositoryDetailsPanel.qml", "T.Popup"): "the repository details sheet",
    ("RepositoryDetailsPanel.qml", "T.Overlay"): "the repository details scrim",
    ("ConflictResultPane.qml", "T.TextArea"): "the conflict result editor's line-numbered text",
    ("SidebarSectionRow.qml", "T.Control"): "the sidebar's disclosure row base",
}
ALLOWED_CONTROLS = re.compile(r"\bC\.(ScrollBar\.(vertical|horizontal)|Popup\.[A-Z]\w*)\b")
CONTROLS = re.compile(r"\b([CT])\.([A-Z]\w*)")
# The git-domain palette (lane, status and decoration colours) and the
# generated string catalog may contain colour-like text.
COLOUR_FILES = {"GitColors.qml", "L10n.qml"}
COLOUR_LITERAL = re.compile(r"[\"']#[0-9a-fA-F]{3,8}[\"']|\bQt\.rgba\(\s*[0-9.]+\s*,|\bQt\.hsla?\(\s*[0-9.]+\s*,")
LAYOUT_FILES = {"GitLamaLayout.qml", "GitColors.qml", "L10n.qml"}
GEOMETRY = re.compile(
    r"^\s*(width|height|implicitWidth|implicitHeight|minimumWidth|minimumHeight|maximumWidth|maximumHeight|"
    r"spacing|radius|rowSpacing|columnSpacing|(left|right|top|bottom)?[mM]argins?|anchors\.\w*[mM]argins?|"
    r"font\.pixelSize|font\.pointSize|(left|right|top|bottom|horizontal|vertical)?[pP]adding)\s*:\s*"
    r"(?P<value>[0-9]+(\.[0-9]+)?)\s*$"
)


# Animations and timers take their durations from Meridian's Motion or GitLamaLayout.
LITERAL_TIME = re.compile(r"\b(duration|interval)\s*:\s*[0-9]+\s*(;|$)")


def violations():
    found = []
    for path in sorted(QML.glob("*.qml")):
        name = path.name
        if name.startswith("Meridian"):
            found.append(f"qml/GitLama/{name}: local copy of a Meridian component; add it to meridian_ui")
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("//", 1)[0]
            where = f"qml/GitLama/{name}:{number}"
            stripped = ALLOWED_CONTROLS.sub("", code)
            for module, element in CONTROLS.findall(stripped):
                base = f"{module}.{element}"
                if module == "T" and (name, base) in TEMPLATE_BASES:
                    continue
                found.append(f"{where}: {base} bypasses Meridian")
            if name not in COLOUR_FILES and COLOUR_LITERAL.search(code):
                found.append(f"{where}: literal colour; use a theme or GitColors token")
            if name not in LAYOUT_FILES and LITERAL_TIME.search(code):
                found.append(f"{where}: literal duration; use Motion or a GitLamaLayout constant")
            if name not in LAYOUT_FILES:
                match = GEOMETRY.match(code)
                if match and float(match.group("value")) not in (0.0, 1.0):
                    found.append(f"{where}: unnamed size; use a Meridian scale or GitLamaLayout")
    return found


def main():
    found = violations()
    if found:
        print("\n".join(found), file=sys.stderr)
        print(f"{len(found)} Meridian usage violation(s)", file=sys.stderr)
        return 1
    print("Meridian usage passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
