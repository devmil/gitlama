#!/usr/bin/env python3
"""Generates qml/GitLama/L10n.qml from the ARB catalogs in l10n/.

The English catalog is the template; every other catalog must have the same
keys and placeholders. Messages are ICU MessageFormat subsets: `{name}` arguments, `{count, plural, =1{..} other{..}}`
and `{kind, select, a{..} other{..}}`, with nesting. Each message compiles to a
small tree the QML runtime renders.

QML reads strings with `L10n.t("key")`, `L10n.t("key", [arg, ...])` (arguments
in the order the template declares its placeholders) or
`L10n.tn("key", {name: value})`.

  python3 tooling/l10n/generate.py          write the singleton
  python3 tooling/l10n/generate.py --check  fail when it is stale
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = ROOT / "l10n"
OUTPUT = ROOT / "qml" / "GitLama" / "L10n.qml"
TEMPLATE = "en"
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class ParseError(Exception):
    pass


def parse(text: str) -> list:
    """Parses an ICU message into parts: str, ["a", name, format],
    ["p", name, {case: parts}] (plural) or ["s", name, {case: parts}]."""
    parts, end = _parse_parts(text, 0, top=True)
    if end != len(text):
        raise ParseError(f"unexpected '}}' at {end}")
    return parts


def _parse_parts(text: str, index: int, top: bool, plural_arg: str | None = None):
    parts: list = []
    buffer: list[str] = []
    while index < len(text):
        char = text[index]
        if char == "'" and index + 1 < len(text) and text[index + 1] == "'":
            buffer.append("'")
            index += 2
            continue
        if char == "{":
            if buffer:
                parts.append("".join(buffer))
                buffer = []
            part, index = _parse_argument(text, index + 1)
            parts.append(part)
            continue
        if char == "}":
            if top:
                raise ParseError(f"unbalanced '}}' at {index}")
            break
        if char == "#" and plural_arg is not None:
            if buffer:
                parts.append("".join(buffer))
                buffer = []
            parts.append(["a", plural_arg, "#"])
            index += 1
            continue
        buffer.append(char)
        index += 1
    if buffer:
        parts.append("".join(buffer))
    return parts, index


def _skip(text: str, index: int) -> int:
    while index < len(text) and text[index].isspace():
        index += 1
    return index


def _parse_argument(text: str, index: int):
    index = _skip(text, index)
    match = NAME.match(text, index)
    if not match:
        raise ParseError(f"expected an argument name at {index}")
    name = match.group(0)
    index = _skip(text, match.end())
    if index < len(text) and text[index] == "}":
        return ["a", name, ""], index + 1
    if text[index] != ",":
        raise ParseError(f"expected ',' or '}}' after {name}")
    index = _skip(text, index + 1)
    match = NAME.match(text, index)
    if not match:
        raise ParseError(f"expected a format after {name}")
    kind = match.group(0)
    index = _skip(text, match.end())
    if kind not in ("plural", "select"):
        raise ParseError(f"unsupported format {kind}")
    if text[index] != ",":
        raise ParseError(f"expected ',' after {kind}")
    index += 1
    cases: dict[str, list] = {}
    while True:
        index = _skip(text, index)
        if index >= len(text):
            raise ParseError("unterminated argument")
        if text[index] == "}":
            index += 1
            break
        start = index
        while index < len(text) and not text[index].isspace() and text[index] != "{":
            index += 1
        selector = text[start:index]
        index = _skip(text, index)
        if index >= len(text) or text[index] != "{":
            raise ParseError(f"expected '{{' after case {selector}")
        body, index = _parse_parts(
            text, index + 1, top=False, plural_arg=name if kind == "plural" else None
        )
        if index >= len(text) or text[index] != "}":
            raise ParseError(f"unterminated case {selector}")
        cases[selector] = body
        index += 1
    if "other" not in cases:
        raise ParseError(f"{name}: no 'other' case")
    return ["p" if kind == "plural" else "s", name, cases], index


def names_in(parts: list, found: list[str]) -> list[str]:
    for part in parts:
        if isinstance(part, str):
            continue
        if part[1] not in found:
            found.append(part[1])
        if part[0] in ("p", "s"):
            for body in part[2].values():
                names_in(body, found)
    return found


def compact(parts: list):
    """A plain message stays a string; anything else stays a part list."""
    if all(isinstance(part, str) for part in parts):
        return "".join(parts)
    return parts


def load(locale: str) -> dict:
    return json.loads((CATALOGS / f"app_{locale}.arb").read_text(encoding="utf-8"))


def messages(catalog: dict) -> dict[str, str]:
    return {key: value for key, value in catalog.items() if not key.startswith("@")}


def placeholders(template: dict, key: str, parsed: list) -> tuple[list[str], dict[str, str]]:
    declared = template.get(f"@{key}", {}).get("placeholders", {}) or {}
    names = list(declared.keys())
    for name in names_in(parsed, []):
        if name not in names:
            names.append(name)
    formats = {
        name: spec.get("format", "")
        for name, spec in declared.items()
        if isinstance(spec, dict) and spec.get("format")
    }
    return names, formats


def render() -> str:
    template = load(TEMPLATE)
    locales = sorted(path.stem.removeprefix("app_") for path in CATALOGS.glob("app_*.arb"))
    keys = sorted(messages(template))
    params: dict[str, list[str]] = {}
    formats: dict[str, dict[str, str]] = {}
    tables: dict[str, dict] = {}
    template_parsed = {}
    for key in keys:
        try:
            template_parsed[key] = parse(template[key])
        except ParseError as error:
            raise SystemExit(f"{TEMPLATE}.{key}: {error}")
        params[key], formats[key] = placeholders(template, key, template_parsed[key])
    for locale in locales:
        catalog = messages(load(locale))
        missing = sorted(set(keys) - set(catalog))
        extra = sorted(set(catalog) - set(keys))
        if missing or extra:
            raise SystemExit(f"{locale}: missing {missing[:5]} extra {extra[:5]}")
        table = {}
        for key in keys:
            try:
                parsed = parse(catalog[key])
            except ParseError as error:
                raise SystemExit(f"{locale}.{key}: {error}")
            used = set(names_in(parsed, []))
            if not used <= set(params[key]):
                raise SystemExit(f"{locale}.{key}: unknown placeholders {used - set(params[key])}")
            table[key] = compact(parsed)
        tables[locale] = table

    def dump(value) -> str:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

    used_params = {key: names for key, names in params.items() if names}
    used_formats = {key: fmt for key, fmt in formats.items() if fmt}
    lines = [
        "// GENERATED by tooling/l10n/generate.py from l10n/*.arb. Do not edit.",
        "pragma Singleton",
        "import QtQuick",
        "",
        "QtObject {",
        "    /// The active language; unknown codes fall back to English.",
        '    property string language: "en"',
        f"    readonly property var languages: {json.dumps(locales)}",
        '    readonly property var strings: language === "de" ? _de : _en',
        '    readonly property string locale: language === "de" ? "de-DE" : "en-US"',
        "",
        "    /// The message `key`; `args` fill its placeholders in declaration order.",
        "    function t(key, args) {",
        "        const names = _params[key]",
        "        const values = {}",
        "        if (names && args) {",
        "            for (let i = 0; i < names.length && i < args.length; ++i)",
        "                values[names[i]] = args[i]",
        "        }",
        "        return tn(key, values)",
        "    }",
        "",
        "    /// The message `key` with named arguments.",
        "    function tn(key, values) {",
        "        let message = strings[key]",
        "        if (message === undefined)",
        "            message = _en[key]",
        "        if (message === undefined)",
        "            return key",
        "        if (typeof message === \"string\")",
        "            return message",
        "        return _render(message, values || {}, _formats[key] || {})",
        "    }",
        "",
        "    /// Whether `key` exists in the catalog.",
        "    function has(key) {",
        "        return _en[key] !== undefined",
        "    }",
        "",
        "    function _number(value, format) {",
        "        const number = Number(value)",
        "        if (format === \"decimalPattern\" && isFinite(number))",
        "            return number.toLocaleString(Qt.locale(locale), \"f\", 0)",
        "        return String(value)",
        "    }",
        "",
        "    function _pluralCase(cases, value) {",
        "        const number = Number(value)",
        "        if (cases[\"=\" + number] !== undefined)",
        "            return cases[\"=\" + number]",
        "        if (number === 0 && cases.zero !== undefined)",
        "            return cases.zero",
        "        if (number === 1 && cases.one !== undefined)",
        "            return cases.one",
        "        if (number === 2 && cases.two !== undefined)",
        "            return cases.two",
        "        if (number !== 1 && number > 1 && number < 5 && cases.few !== undefined && language !== \"en\" && language !== \"de\")",
        "            return cases.few",
        "        return cases.other",
        "    }",
        "",
        "    function _render(parts, values, formats) {",
        "        let out = \"\"",
        "        for (let i = 0; i < parts.length; ++i) {",
        "            const part = parts[i]",
        "            if (typeof part === \"string\") {",
        "                out += part",
        "                continue",
        "            }",
        "            const value = values[part[1]]",
        "            if (part[0] === \"a\") {",
        "                if (value === undefined || value === null)",
        "                    out += \"\"",
        "                else if (part[2] === \"#\" || formats[part[1]])",
        "                    out += _number(value, formats[part[1]] || \"\")",
        "                else",
        "                    out += String(value)",
        "            } else if (part[0] === \"p\") {",
        "                out += _render(_pluralCase(part[2], value), values, formats)",
        "            } else {",
        "                const branch = part[2][String(value)]",
        "                out += _render(branch !== undefined ? branch : part[2].other, values, formats)",
        "            }",
        "        }",
        "        return out",
        "    }",
        "",
        f"    readonly property var _params: {dump(used_params)}",
        f"    readonly property var _formats: {dump(used_formats)}",
    ]
    for locale in locales:
        lines.append(f"    readonly property var _{locale}: {dump(tables[locale])}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    text = render()
    if "--check" in sys.argv[1:]:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != text:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; run tooling/l10n/generate.py", file=sys.stderr)
            return 1
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
