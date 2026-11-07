#!/usr/bin/env python3
"""Fail closed when a product command lacks a complete interaction contract."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "lib/models/app_command.dart"
SHELL = ROOT / "lib/app/workspace_shell.dart"
sys.path.insert(0, str(ROOT / "scripts"))
from meridian_package import available_icon_names  # noqa: E402

AVAILABLE_ICONS = available_icon_names(ROOT)


def read_workspace_shell() -> str:
    """The workspace shell library and its feature libraries."""
    paths = [SHELL, *sorted((SHELL.parent / "workspace").glob("*.dart"))]
    return "\n".join(path.read_text(encoding="utf-8") for path in paths)


def names_between(text: str, start: str, end: str) -> list[str]:
    body = text.split(start, 1)[1].split(end, 1)[0]
    return re.findall(r"^\s{2}([A-Za-z][A-Za-z0-9]*),$", body, re.MULTILINE)


model = MODEL.read_text(encoding="utf-8")
shell = read_workspace_shell()
commands = names_between(model, "enum AppCommandId {", "}")
definitions = re.findall(
    r"AppCommandDefinition\(\s*id: AppCommandId\.([A-Za-z0-9]+),(.+?)\n\s*\),",
    model,
    re.DOTALL,
)
defined = [name for name, _ in definitions]
executed = re.findall(r"case AppCommandId\.([A-Za-z0-9]+):", shell)
label_block = shell.split("String commandLabel", 1)[1].split("};", 1)[0]
labelled = re.findall(r"AppCommandId\.([A-Za-z0-9]+) =>", label_block)

errors: list[str] = []
expected = set(commands)
for title, values in {
    "registry": defined,
    "execution switch": executed,
    "localized label switch": labelled,
}.items():
    actual = set(values)
    if actual != expected:
        errors.append(
            f"{title}: missing={sorted(expected - actual)} extra={sorted(actual - expected)}"
        )
    duplicates = sorted({value for value in values if values.count(value) > 1})
    if duplicates:
        errors.append(f"{title}: duplicate={duplicates}")

menu_catalog = (ROOT / "lib/app/workspace/command_menus.dart").read_text(encoding="utf-8")
menu_body = menu_catalog.split("const workspaceCommandGroups", 1)[1].split("String commandMenuGroupLabel", 1)[0]
menu_commands = re.findall(r"AppCommandId\.([A-Za-z0-9]+)", menu_body)
if set(menu_commands) != expected or len(menu_commands) != len(expected):
    errors.append("native grouped menu must contain every registered command exactly once")
menu_groups = {
    command: group
    for group, body in re.findall(r"'([^']+)': \[(.*?)\]", menu_body, re.DOTALL)
    for command in re.findall(r"AppCommandId\.([A-Za-z0-9]+)", body)
}

local_ui = {
    "showChanges",
    "showHistory",
    "showActivity",
    "showCommandPalette",
    "showSettings",
    "showShortcutReference",
    "showLicenses",
    "inspectorBack",
    "inspectorForward",
    "inspectorLensDiff",
    "inspectorLensContents",
    "inspectorLensBlame",
    "inspectorLensHistory",
    "inspectorOpenInWindow",
    "inspectorToggleMaximize",
    "inspectorToggleFiles",
    "inspectorAllFiles",
}
shell_workflow = {
    "openRepository",
    "cloneRepository",
    "showOperations",
    "showSnapshots",
    "showIntegrations",
    "showPowerTools",
    "addWorktree",
    "trackLfsPattern",
    "addIntegration",
}
service_workflow = expected - local_ui - shell_workflow
classified = local_ui | shell_workflow | service_workflow
if classified != expected:
    errors.append(f"boundary classification incomplete: {sorted(expected - classified)}")

inventory = []
for name, body in definitions:
    shortcut = re.search(r"shortcut: '([^']+)'", body)
    icon = re.search(r"icon: '([^']+)'", body)
    requires_repository = "requiresRepository: true" in body
    if icon is None:
        errors.append(f"{name}: missing icon")
        icon_name = ""
    else:
        icon_name = icon.group(1)
        if icon_name not in AVAILABLE_ICONS:
            errors.append(f"{name}: missing icon asset {icon_name}")
    boundary = (
        "local UI state"
        if name in local_ui
        else "shell-owned typed workflow"
        if name in shell_workflow
        else "RepositorySessionService typed request/result"
    )
    inventory.append(
        {
            "command": name,
            "pointer": f"native More menu / {menu_groups[name]}; command palette; contextual surface where applicable",
            "keyboard": shortcut.group(1) if shortcut else "Ctrl/Cmd+P, search, Enter",
            "enabled_rule": "active ready repository required"
            if requires_repository
            else "always available",
            "typed_boundary": boundary,
            "failure_behavior": "localized typed failure; mutation success is never inferred"
            if name not in local_ui
            else "no native mutation; dialog/panel state remains explicit",
            "focus_restoration": "dialog/overlay returns focus to invoker; navigation moves focus only on explicit request",
            "icon": icon_name,
        }
    )

if errors:
    raise SystemExit("\n".join(errors))

document = {
    "schema": 1,
    "source": "lib/models/app_command.dart and lib/app/workspace_shell.dart with lib/app/workspace/",
    "count": len(inventory),
    "commands": inventory,
}
output = Path(sys.argv[1]) if len(sys.argv) > 1 else None
encoded = json.dumps(document, indent=2, sort_keys=True) + "\n"
if output:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(encoded)
else:
    print(encoded, end="")
print(f"Command inventory passed: {len(inventory)} complete commands.", file=sys.stderr)
