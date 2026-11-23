#!/usr/bin/env python3
"""Fail closed when a product command lacks a complete interaction contract.

The registry (rust-core/desktop/workbench/data/commands.json) is the one
source the toolbar, menus, palette, shortcuts and settings read. Each command
needs a unique id, a name in the English and German catalogs, an icon Meridian
draws, valid scopes, a remote classification, and a handler in the QML.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "rust-core/desktop/workbench/data/commands.json"
SCOPES = {"global", "changes", "history", "diff", "conflict", "rebase", "sidebar"}
GROUPS = {"commands", "repository", "settings"}
REMOTE = {
    "view", "read", "stage", "commit", "refs", "stash", "transfer", "discard",
    "history", "recovery", "extensions", "unsupported",
}


def icon_names() -> set[str]:
    icons = (ROOT / "qml/Meridian/IconData.qml").read_text(encoding="utf-8")
    names = set(json.loads(re.search(r"readonly property var names: (\[.*?\])", icons).group(1)))
    # GitLama's semantic names, installed as Meridian's icon aliases.
    aliases = (ROOT / "qml/GitLama/GitLamaIcons.qml").read_text(encoding="utf-8")
    for alias, target in re.findall(r'"([\w-]+)"\s*:\s*"([\w-]+)"', aliases):
        if target not in names:
            raise SystemExit(f"GitLamaIcons alias {alias} names the missing icon {target}")
        names.add(alias)
    return names


def main() -> int:
    commands = json.loads(REGISTRY.read_text(encoding="utf-8"))["commands"]
    catalogs = {
        locale: json.loads((ROOT / f"l10n/app_{locale}.arb").read_text(encoding="utf-8"))
        for locale in ("en", "de")
    }
    icons = icon_names()
    # Commands.qml and CommandMenus.qml name every command for availability
    # and menus; they run none.
    qml = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((ROOT / "qml/GitLama").glob("*.qml"))
        if path.name not in ("Commands.qml", "CommandMenus.qml")
    )
    errors: list[str] = []
    seen: set[str] = set()
    for command in commands:
        name = command["id"]
        if name in seen:
            errors.append(f"{name}: duplicate id")
        seen.add(name)
        for locale, catalog in catalogs.items():
            if command["label"] not in catalog:
                errors.append(f"{name}: label {command['label']} missing from app_{locale}.arb")
        if command["icon"] not in icons:
            errors.append(f"{name}: icon {command['icon']} is not a Meridian icon")
        if not command["scopes"] or set(command["scopes"]) - SCOPES:
            errors.append(f"{name}: invalid scopes {command['scopes']}")
        if command["group"] not in GROUPS:
            errors.append(f"{name}: unknown group {command['group']}")
        if command["remote"] not in REMOTE:
            errors.append(f"{name}: remote classification {command['remote']!r} is incomplete")
        # A handler dispatches on the id (`case "id":` or `=== "id"`); a
        # menu listing alone would fall through to the unknown-command path.
        handled = re.search(rf'case\s+"{re.escape(name)}"\s*:|===\s*"{re.escape(name)}"', qml)
        if command["available"] and not handled:
            errors.append(f"{name}: no QML handler runs this command")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Command inventory passed ({len(commands)} commands)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
