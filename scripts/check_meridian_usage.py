#!/usr/bin/env python3
"""Fail when Flutter UI code bypasses the Meridian design system.

Usage:
  python3 scripts/check_meridian_usage.py                    # enforce zero violations
  python3 scripts/check_meridian_usage.py --report           # print every violation with file:line
  python3 scripts/check_meridian_usage.py --write-baseline   # ONLY allowed in package M01 (see the migration plan)

The migration baseline is gone; every rule must report zero violations.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "scripts/meridian_usage_baseline.json"
GENERATED = "lib/app/gitlama_tokens.g.dart"
LAYOUT = "lib/app/gitlama_layout.dart"
# The theme defines GitLama's micro text styles on top of Meridian's.
THEME = "lib/app/app_theme.dart"
# Files that are allowed to wrap a Material primitive. Meridian's components
# live in meridian_ui; GitLama has none of its own left.
COMPONENT_FILES = {THEME}
SKIP_PREFIXES = ("lib/rust/", "lib/l10n/")
SHARED = (
    "Button|IconButton|ToolbarButton|TextField|TextArea|Dialog|ListRow|Island|Banner|"
    "Disclosure|DisclosureController|Checkbox|CheckboxIndicator|Switch|Segmented|Select|"
    "Icon|IconSize|Interaction|InteractionState|Spinner|ProgressRule|Kbd|Count|"
    "SettingsRow|SettingsGroup|FloatingPanel|Range|Scrollbar|MenuButton|"
    "SuggestionSurface|SuggestionRow|SuggestionGroupHeader|Theme|Density|IslandScope"
)

RULES = [
    # (id, regex, files the rule does NOT apply to, explanation)
    ("material-icons", r"\bIcons\.[a-zA-Z_]", set(), "Use MeridianIcon('<name>') with a Lucide name or a GitLama alias."),
    ("material-icon-widget", r"(?<![A-Za-z_])Icon\(", set(), "Use MeridianIcon."),
    ("color-literal", r"\bColor\(0x", {GENERATED}, "Colours come from context.colors.<token> or context.git.<token>."),
    ("colors-constant", r"\bColors\.(?!transparent\b)", set(), "Only Colors.transparent is allowed."),
    ("transparent-compare", r"[!=]=\s*Colors\.transparent\b|\bColors\.transparent\s*[!=]=", set(), "Compare alpha (color.a == 0): Meridian fades fills from the target colour at zero alpha."),
    ("material-button", r"\b(TextButton|FilledButton|OutlinedButton|ElevatedButton)\b", set(), "Use MeridianButton(variant: ...)."),
    ("material-icon-button", r"(?<![A-Za-z_])IconButton\(", set(), "Use MeridianIconButton."),
    ("material-theme", r"\b(IconButtonTheme|TextButtonTheme|FilledButtonTheme|OutlinedButtonTheme|ElevatedButtonTheme|ButtonStyle)\b|\.styleFrom\(", {THEME}, "Meridian components paint themselves; Material button themes style nothing."),
    ("material-selector", r"\b(SegmentedButton|DropdownButton|DropdownButtonFormField|DropdownMenu|Radio|RadioListTile|Slider)\b", set(), "Use MeridianSegmented / MeridianSelect / MeridianSlider."),
    ("material-toggle", r"(?<![A-Za-z_])(Checkbox|Switch|CheckboxListTile|SwitchListTile)\(", set(), "Use MeridianCheckbox / MeridianSwitch."),
    ("material-surface", r"(?<![A-Za-z_])(Card|ListTile|ExpansionTile|AppBar|Chip|ActionChip|FilterChip|InputChip|Badge|Divider|VerticalDivider|Material)\(", COMPONENT_FILES, "Use MeridianIsland / MeridianListRow / MeridianDisclosure / MeridianCount / MeridianHairline."),
    ("material-progress", r"\b(CircularProgressIndicator|LinearProgressIndicator)\b", COMPONENT_FILES, "Use MeridianSpinner / MeridianProgressBar."),
    ("raw-text-field", r"(?<![A-Za-z_])(TextField|TextFormField)\(", COMPONENT_FILES, "Use MeridianTextField."),
    ("input-decoration", r"\bInputDecoration\(", COMPONENT_FILES, "Field chrome belongs to MeridianTextField."),
    ("painted-menu", r"\b(PopupMenuButton|showMenu|MeridianMenuSurface)\b|(?<![A-Za-z_])MenuAnchor\(", set(), "Menus are OS-native: MeridianMenuAnchor and MeridianSelect go through NativeMenus.scope at each app root; context menus through GitLamaContextMenuWidget."),
    ("super-context-menu-import", r"""\b(import|export)\s+['"]package:super_(context_menu|native_extensions)/""", set(), "GitLama does not talk to the menu plugin: meridian_native_menus does. Build NativeMenuItem / NativeMenuAction lists and show them with GitLamaContextMenuWidget, NativeMenuButton or showNativeMenuItems."),
    ("native-menus-import", r"""\b(import|export)\s+['"]package:meridian_native_menus/""", {"lib/widgets/native_menu.dart"}, "Only lib/widgets/native_menu.dart uses meridian_native_menus; install it with NativeMenus.scope and show menus through the native_menu.dart API."),
    ("local-component", r"\bGitLama(" + SHARED + r")\b", set(), "This component lives in meridian_ui: use the Meridian widget."),
    ("font-size-literal", r"\bfontSize:\s*[0-9]", {GENERATED, LAYOUT, THEME}, "Use a context.text style (GitLama micro styles are in app_theme.dart)."),
    ("font-weight-literal", r"\bfontWeight:\s*FontWeight\.", {GENERATED, LAYOUT, THEME}, "Use context.text.bodyStrong etc."),
    ("font-family-literal", r"fontFamily:\s*'", {GENERATED, LAYOUT, THEME}, "Use context.text.code / context.text.codeSm."),
    ("text-theme", r"\btextTheme\.", {THEME}, "Use context.text (Meridian styles + colour)."),
    ("radius-literal", r"\bBorderRadius\.(circular|all)\(\s*[0-9]|Radius\.circular\(\s*[0-9]", {GENERATED, LAYOUT}, "Use context.meridian.radius.*."),
    ("edge-insets-literal", r"\bEdgeInsets(Directional)?\.(all|symmetric|only|fromLTRB|fromSTEB)\([^)]*?\b[1-9][0-9]*(\.[0-9]+)?\b", {GENERATED, LAYOUT}, "Use MeridianSpace.* (or MeridianLayout / GitLamaLayout for component constants)."),
    ("size-literal", r"\b(width|height|dimension|size|extent|maxWidth|minWidth|maxHeight|minHeight)\s*:\s*[1-9][0-9]*(\.[0-9]+)?\b", {GENERATED, LAYOUT, THEME}, "Name the dimension: MeridianSize / MeridianLayout / GitLamaLayout."),
    ("offset-literal", r"\b(top|bottom|start|end|left|right)\s*:\s*[1-9][0-9]*(\.[0-9]+)?\b", {GENERATED, LAYOUT, THEME}, "Position with MeridianSpace / MeridianSize / GitLamaLayout."),
    ("sized-box-literal", r"\bSizedBox(\.square)?\(\s*(width|height|dimension):\s*[1-9]", {GENERATED, LAYOUT}, "Use MeridianSpace / MeridianSize / MeridianLayout / GitLamaLayout."),
    ("alpha-literal", r"\.withValues\(\s*alpha:\s*[0-9.]", {LAYOUT, THEME}, "Use a MeridianOpacity or GitLamaOpacity constant."),
    ("old-theme-field", r"\.(surfaceRaised|accentForeground|focusRing|addedBackground|deletedBackground|addedHighlight|deletedHighlight|conflictCurrent|conflictIncoming|polar|polarSoft|polarInk|onPolar|fjord)\b(?!\s*\()", set(), "Removed theme field: use Meridian's accent family (accent, accentSoft, accentInk, onAccent, brand)."),
    ("old-app-token", r"\bAppTokens\.", set(), "AppTokens is removed; use MeridianSpace/MeridianSize/MeridianLayout."),
    ("raw-dialog", r"\b(showDialog|showGeneralDialog|AlertDialog|SimpleDialog|SimpleDialogOption)\b", set(), "Use MeridianDialog / MeridianDialogSurface with showMeridianDialog."),
    # Motion (docs/design-system/specs/motion.md): named durations, curves and springs only.
    ("curve-literal", r"\bCurves\.(?!linear\b)", {GENERATED}, "Use MeridianCurves or a MeridianDurations …Curve (specs/motion.md)."),
    ("animation-duration-literal", r"\b(duration|reverseDuration|transitionDuration|reverseTransitionDuration)\s*:\s*(const\s+)?Duration\(", {GENERATED, LAYOUT}, "Use MeridianDurations or GitLamaMotion (specs/motion.md)."),
    ("spring-literal", r"SpringDescription\(", {GENERATED}, "Use MeridianSprings."),
]


_LEXEMES = re.compile(
    r"//[^\n]*|/\*.*?\*/"
    r"|r?'\'\'.*?'\'\'|r?\"\"\".*?\"\"\""
    r"|r?'(?:\\.|[^'\\\n])*'|r?\"(?:\\.|[^\"\\\n])*\"",
    re.S,
)


def _blank_comments_and_strings(text):
    """Blanks comments and string literals, keeping offsets and lines."""
    return _LEXEMES.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)


def _closing(text, start):
    """Index of the bracket that closes the one opened at text[start]."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] in "([{":
            depth += 1
        elif text[index] in ")]}":
            depth -= 1
            if depth == 0:
                return index
    return None


def _top_level(text):
    """Splits the inner text of a bracket on its top-level commas."""
    parts, depth, start = [], 0, 0
    for index, char in enumerate(text):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    parts.append(text[start:].strip())
    return [part for part in parts if part]


def _arguments(code, open_at):
    """The named arguments of the call whose parenthesis opens at open_at."""
    close_at = _closing(code, open_at)
    if close_at is None:
        return {}
    named = {}
    for part in _top_level(code[open_at + 1 : close_at]):
        match = re.match(r"([A-Za-z_]\w*)\s*:\s*(.*)\Z", part, re.S)
        if match:
            named[match.group(1)] = match.group(2).strip()
    return named


def hand_built_confirmations(text):
    """Lines of MeridianDialogs that re-implement showMeridianConfirm.

    A hand-built confirmation's actions are exactly a quiet Cancel
    (context.l10n.cancel) and one other button, and it has no content or only
    plain text as its content. Forms, lists, previews, option dialogs and
    dialogs with other actions are left alone.
    """
    code = _blank_comments_and_strings(text)
    lines = []
    for match in re.finditer(r"(?<![A-Za-z_])MeridianDialog\(", code):
        arguments = _arguments(code, match.end() - 1)
        actions = arguments.get("actions", "")
        if not actions.startswith("["):
            continue
        buttons = _top_level(actions[1:-1])
        if len(buttons) != 2 or not all(
            button.startswith("MeridianButton(") for button in buttons
        ):
            continue
        cancels = [
            button
            for button in buttons
            if re.search(r"\blabel:\s*(context\.)?l10n\.cancel\b", button)
            and "MeridianButtonVariant.quiet" in button
        ]
        if len(cancels) != 1:
            continue
        content = arguments.get("content")
        if content is not None:
            plain = re.fullmatch(r"(const\s+)?(Text|SelectableText)\((.*)\)", content, re.S)
            # Plain text: no widgets inside the Text's own arguments.
            if not plain or re.search(
                r"(?<![A-Za-z_.])(?!TextStyle\()[A-Z]\w*\(", plain.group(3)
            ):
                continue
        lines.append(code.count("\n", 0, match.start()) + 1)
    return lines


# Rules that need more than one line, with the same reporting as RULES.
MULTILINE_RULES = [
    # (id, function(text) -> line numbers, exempt files, explanation)
    ("hand-built-confirmation", hand_built_confirmations, set(), "Use showMeridianConfirm: the verb as confirmLabel, cancelLabel: context.l10n.cancel, the consequence as description or content, destructive: true for danger."),
]


def files():
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(SKIP_PREFIXES) or rel.endswith(".g.dart") and rel != GENERATED:
            continue
        yield rel, path.read_text(encoding="utf-8")


def scan():
    found = {}
    for rel, text in files():
        # Strip // comments so documentation may mention banned names.
        lines = [re.sub(r"//.*$", "", line) for line in text.splitlines()]
        for rule_id, pattern, exempt, _ in RULES:
            if rel in exempt:
                continue
            regex = re.compile(pattern)
            for number, line in enumerate(lines, 1):
                for _ in regex.finditer(line):
                    found.setdefault(rule_id, {}).setdefault(rel, []).append(number)
        for rule_id, check, exempt, _ in MULTILINE_RULES:
            if rel in exempt:
                continue
            for number in check(text):
                found.setdefault(rule_id, {}).setdefault(rel, []).append(number)
    return found


def main() -> None:
    found = scan()
    if "--report" in sys.argv:
        for rule_id, _, _, hint in RULES + MULTILINE_RULES:
            for rel, numbers in sorted(found.get(rule_id, {}).items()):
                for number in numbers:
                    print(f"{rel}:{number}: [{rule_id}] {hint}")
        return
    counts = {rule: {rel: len(n) for rel, n in by_file.items()} for rule, by_file in found.items()}
    if "--write-baseline" in sys.argv:
        BASELINE.write_text(json.dumps(counts, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"baseline written: {sum(sum(v.values()) for v in counts.values())} violations")
        return
    baseline = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    errors = []
    for rule_id, by_file in counts.items():
        for rel, count in by_file.items():
            allowed = baseline.get(rule_id, {}).get(rel, 0)
            if count > allowed:
                hint = next(h for r, _, _, h in RULES + MULTILINE_RULES if r == rule_id)
                errors.append(f"{rel}: [{rule_id}] {count} > baseline {allowed}. {hint}")
    stale = [
        f"{rule}:{rel} baseline {allowed} > actual {counts.get(rule, {}).get(rel, 0)} – lower the baseline"
        for rule, by_file in baseline.items()
        for rel, allowed in by_file.items()
        if counts.get(rule, {}).get(rel, 0) < allowed
    ]
    if errors or stale:
        raise SystemExit("\n".join(errors + stale))
    total = sum(sum(v.values()) for v in counts.values())
    print(f"Meridian usage guard passed ({total} baselined violations remain)")


if __name__ == "__main__":
    main()
