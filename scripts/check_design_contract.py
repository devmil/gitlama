#!/usr/bin/env python3
"""Validate the Meridian design system package and the QML contracts that depend on it.

Usage:
  python3 scripts/check_design_contract.py              # validate
  python3 scripts/check_design_contract.py --write-css  # regenerate tokens/gitlama-tokens.css, then validate
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
design = root / "docs/design-system"
manifest = json.loads((design / "MANIFEST.json").read_text(encoding="utf-8"))
errors: list[str] = []


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_sha256(path: Path) -> str:
    # Git on Windows may check dependency text files out with CRLF endings.
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


# --- Package inventory -------------------------------------------------------
sys.path.insert(0, str(root / "scripts"))
from meridian_package import gitlama_icon_aliases, meridian_icon_names  # noqa: E402

git_tokens = root / "qml/GitLama/GitColors.qml"
if not git_tokens.is_file():
    errors.append("missing generated GitLama git colour tokens")
if subprocess.run(
    [sys.executable, str(root / "scripts/generate_meridian_theme.py"), "--check"],
    cwd=root,
    check=False,
    capture_output=True,
).returncode != 0:
    errors.append(
        "GitLama git colours are stale or the shared tokens drifted from meridian_ui"
    )
if manifest.get("schema") != "gitlama.design-manifest.v1":
    errors.append("MANIFEST.json schema must be gitlama.design-manifest.v1")
listed = set(manifest["sourceFiles"])
present = {
    p.relative_to(design).as_posix()
    for p in design.rglob("*")
    if p.is_file() and p.name != ".DS_Store"
}
for missing in sorted(listed - present):
    errors.append(f"missing design source: {missing}")
for unlisted in sorted(present - listed):
    errors.append(f"design file not listed in MANIFEST.json sourceFiles: {unlisted}")

expected_viewports = [
    (900, 600, 1.0),
    (1280, 720, 1.0),
    (1440, 900, 1.0),
    (1920, 1080, 1.0),
    (1440, 900, 1.3),
]
actual_viewports = [
    (item["width"], item["height"], item["fontScale"])
    for item in manifest["viewports"]
]
if actual_viewports != expected_viewports:
    errors.append("viewport contract changed")
if manifest["themes"] != ["light", "dark"]:
    errors.append("theme contract changed")
if manifest["densities"] != {"compact": 24, "regular": 28, "comfortable": 32}:
    errors.append("density contract changed")

# --- Tokens --------------------------------------------------------------------
tokens = json.loads((design / manifest["contracts"]["tokens"]).read_text(encoding="utf-8"))
if [t["id"] for t in tokens["color"]["themes"]] != manifest["themes"]:
    errors.append("token themes differ from the manifest")
colors = {t["name"]: t["value"] for t in tokens["color"]["tokens"]}
hex_re = re.compile(r"^#[0-9a-fA-F]{6}$")
names: set[str] = set()
for family in ("color", "spacing", "radius", "shadow", "size"):
    for token in tokens[family]["tokens"]:
        if token["name"] in names:
            errors.append(f"duplicate token name: {token['name']}")
        names.add(token["name"])
        if not token.get("usage"):
            errors.append(f"token without usage note: {token['name']}")
for name, value in colors.items():
    if not isinstance(value, dict) or set(value) != {"light", "dark"}:
        errors.append(f"colour token must define light and dark: {name}")
for required in ("ground", "pane", "pane-alt", "raised", "ink", "ink-muted", "polar", "on-polar",
                 "polar-soft", "focus", "added", "deleted", "modified", "conflict", "danger"):
    if required not in colors:
        errors.append(f"required colour token missing: {required}")
for lane in range(1, 9):
    if f"lane-{lane}" not in colors:
        errors.append(f"lane token missing: lane-{lane}")
if manifest["densities"] != {
    "compact": int(next(t["value"] for t in tokens["size"]["tokens"] if t["name"] == "size-row-compact")[:-2]),
    "regular": int(next(t["value"] for t in tokens["size"]["tokens"] if t["name"] == "size-row")[:-2]),
    "comfortable": int(next(t["value"] for t in tokens["size"]["tokens"] if t["name"] == "size-row-comfortable")[:-2]),
}:
    errors.append("density tokens differ from the manifest")


def luminance(value: str) -> float:
    channels = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(a: str, b: str) -> float:
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


for pair in manifest["contrastPairs"]:
    for theme in manifest["themes"]:
        fg, bg = colors[pair["fg"]][theme], colors[pair["bg"]][theme]
        if not (hex_re.match(fg) and hex_re.match(bg)):
            errors.append(f"contrast pair uses a non-hex colour: {pair['fg']} on {pair['bg']}")
            continue
        ratio = contrast(fg, bg)
        if ratio < pair["min"]:
            errors.append(
                f"contrast {pair['fg']} on {pair['bg']} ({theme}) is {ratio:.2f}, needs {pair['min']}"
            )
for lane in range(1, 9):
    for theme in manifest["themes"]:
        if contrast(colors[f"lane-{lane}"][theme], colors["pane"][theme]) < 3:
            errors.append(f"lane-{lane} is below 3:1 on pane ({theme})")


def compiled_css() -> str:
    light, dark = [], []
    for token in tokens["color"]["tokens"] + tokens["shadow"]["tokens"]:
        light.append(f"  --{token['name']}: {token['value']['light']};")
        dark.append(f"  --{token['name']}: {token['value']['dark']};")
    other = [
        f"  --{token['name']}: {token['value']};"
        for family in ("spacing", "radius", "size")
        for token in tokens[family]["tokens"]
    ] + [f"  --font-{key}: {value};" for key, value in tokens["type"]["families"].items()]
    classes = []
    for group in tokens["type"]["groups"]:
        for style in group["styles"]:
            family = style.get("family", group["family"])
            decl = (
                f"font-family: var(--font-{family}); font-size: {style['fontSize']}; "
                f"line-height: {style['lineHeight']}; font-weight: {style['fontWeight']};"
            )
            if "letterSpacing" in style:
                decl += f" letter-spacing: {style['letterSpacing']};"
            if style["name"] == "overline":
                decl += " text-transform: uppercase;"
            classes.append(f".{style['name']} {{ {decl} }}")
    return (
        "/* GENERATED from gitlama-tokens.json by scripts/check_design_contract.py --write-css. Do not edit by hand. */\n"
        "@font-face { font-family: 'JetBrains Mono'; src: url('../assets/fonts/JetBrainsMono-Regular.ttf') format('truetype'); font-weight: 400; font-style: normal; }\n"
        ":root, [data-theme=\"light\"] {\n" + "\n".join(light) + "\n}\n"
        "[data-theme=\"dark\"] {\n" + "\n".join(dark) + "\n}\n"
        "@media (prefers-color-scheme: dark) {\n  :root:not([data-theme=\"light\"]) {\n"
        + "\n".join("  " + line for line in dark) + "\n  }\n}\n"
        ":root {\n" + "\n".join(other) + "\n}\n" + "\n".join(classes) + "\n"
    )


css_path = design / manifest["contracts"]["tokensCss"]
if "--write-css" in sys.argv:
    css_path.write_text(compiled_css(), encoding="utf-8")
if css_path.read_text(encoding="utf-8") != compiled_css():
    errors.append("tokens CSS is stale: run scripts/check_design_contract.py --write-css")

# --- Oracles -------------------------------------------------------------------
for name, oracle in manifest["fixtureOracles"].items():
    payload = json.loads((design / oracle["file"]).read_text(encoding="utf-8"))
    if payload.get("schema") != oracle["schema"]:
        errors.append(f"{name} oracle schema does not match the manifest")
graph_oracle = json.loads((design / manifest["fixtureOracles"]["graph"]["file"]).read_text(encoding="utf-8"))
if graph_oracle.get("algorithm") != "G-LANE-01" or len(graph_oracle.get("fixtures", [])) != 23:
    errors.append("graph oracle must carry the 23 G-LANE-01 fixtures")
graph_source = (root / "rust-core/application/src/graph.rs").read_text(encoding="utf-8")
for oracle_file in (manifest["fixtureOracles"]["graph"]["file"], manifest["fixtureOracles"]["graph"]["layoutFile"]):
    if f"docs/design-system/{oracle_file}" not in graph_source:
        errors.append(f"rust-core graph tests no longer read {oracle_file}")

# --- Assets --------------------------------------------------------------------
icons = json.loads((design / manifest["contracts"]["icons"]).read_text(encoding="utf-8"))
if icons["pinnedVersion"] != "1.37.0":
    errors.append("Lucide version changed without a design review")
# GitLama draws Meridian's Lucide set; its semantic names are aliases.
meridian_icons = meridian_icon_names()
aliases = gitlama_icon_aliases()
inventory = {item["file"][: -len(".svg")]: item for item in icons["icons"]}
for name, item in inventory.items():
    lucide = item["lucide"]
    if name != lucide and aliases.get(name) != lucide:
        errors.append(f"icon {name} is neither a Meridian icon nor an alias of {lucide}")
    if lucide not in meridian_icons:
        errors.append(f"Meridian has no Lucide icon {lucide}")
    copy = design / "assets/icons" / item["file"]
    if not copy.is_file() or "@license lucide-static v1.37.0 - ISC" not in copy.read_text(encoding="utf-8"):
        errors.append(f"design icon copy is missing or lost its license header: {item['file']}")
for alias in aliases:
    if alias not in inventory:
        errors.append(f"icon alias missing from inventory.json: {alias}")
for design_rel, app_rel in manifest["mirroredAssets"].items():
    if not (root / app_rel).is_file() or sha256(design / design_rel) != sha256(root / app_rel):
        errors.append(f"design asset copy differs from the app asset: {design_rel}")
if "SIL OPEN FONT LICENSE Version 1.1" not in (root / "assets/fonts/OFL.txt").read_text(encoding="utf-8"):
    errors.append("JetBrains Mono OFL text is missing")

adaptation = design / manifest["contracts"]["qml"]
if "No design decision blocks the port" not in adaptation.read_text(encoding="utf-8"):
    errors.append("QML adaptation contract is missing or incomplete")

# --- QML contracts ---------------------------------------------------------------
qml = root / "qml/GitLama"
# Every application dialog is a Meridian dialog.
for path in sorted(qml.glob("*Dialog.qml")):
    if not re.search(r"^(MeridianDialog|MeridianSettingsDialog)\s*\{", path.read_text(encoding="utf-8"), re.M):
        errors.append(f"{path.relative_to(root)}: an application dialog must be a MeridianDialog")
# Text a person edits or selects offers the native text menu.
for path in sorted(qml.glob("*.qml")):
    text = path.read_text(encoding="utf-8")
    if re.search(r"^\s*(T\.TextArea|T\.TextField|TextEdit|TextInput)\s*\{", text, re.M):
        # TextLayoutProbe is an invisible, disabled layout copy that nobody edits or selects.
        if "MeridianTextMenu" not in text and path.name not in ("Actions.qml", "TextLayoutProbe.qml"):
            errors.append(f"{path.relative_to(root)}: an editable text lacks MeridianTextMenu")
# The history graph is drawn natively and fed by the G-LANE-01 rows.
history_row = (qml / "HistoryRow.qml").read_text(encoding="utf-8")
if "GraphRow {" not in history_row:
    errors.append("HistoryRow lost the native graph row")
# Both theme modes and the three densities stay bound to the appearance settings.
main = (qml / "Main.qml").read_text(encoding="utf-8")
for contract in ('property: "density"', 'property: "mode"', 'property: "iconAliases"', 'property: "textMenuLabels"'):
    if contract not in main:
        errors.append(f"Main.qml lost the theme binding {contract}")

if errors:
    raise SystemExit("\n".join(errors))
print("Meridian design package, oracles, assets and QML contracts passed")
