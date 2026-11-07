#!/usr/bin/env python3
"""Check the English and German ARB catalogs.

The check fails when:

- the catalogs do not have the same message keys, or an English message has
  no `@key` metadata;
- a message's placeholders, or its plural and select arguments with their
  cases, differ between English and German;
- a message is not used by the application (`lib/` outside `lib/l10n/`);
- one English text has different German translations under different keys
  (see docs/design-system/GLOSSARY.md). Pairs where the same English word
  genuinely needs two German words are listed in `DIVERGENT_ALLOWED`.

Usage:
  python3 scripts/check_l10n.py              # enforce
  python3 scripts/check_l10n.py --report     # list findings, never fail
"""

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
L10N = ROOT / "lib/l10n"

# English text -> reason, when one English text needs different German
# translations under different keys (a noun and a verb, for example).
DIVERGENT_ALLOWED: dict[str, str] = {}


def keys(document: dict[str, object]) -> set[str]:
    return {key for key in document if not key.startswith("@")}


class IcuError(ValueError):
    pass


def arguments(message: str) -> dict[str, tuple[str, frozenset[str]]]:
    """Every ICU argument of [message]: name -> (kind, cases).

    kind is `simple`, `plural` or `select`; cases are the selectors of a
    plural or select argument. Arguments inside cases are included.
    """
    found: dict[str, tuple[str, frozenset[str]]] = {}

    def parse(text: str, start: int, nested: bool) -> int:
        i = start
        while i < len(text):
            char = text[i]
            if char == "{":
                i = argument(text, i + 1)
                continue
            if char == "}":
                if nested:
                    return i
                raise IcuError(f"unbalanced '}}' at {i}")
            i += 1
        if nested:
            raise IcuError("unterminated case")
        return i

    def argument(text: str, i: int) -> int:
        end = i
        while end < len(text) and text[end] not in ",}":
            end += 1
        if end >= len(text):
            raise IcuError("unterminated argument")
        name = text[i:end].strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise IcuError(f"invalid argument name {name!r}")
        if text[end] == "}":
            found.setdefault(name, ("simple", frozenset()))
            return end + 1
        kind_end = text.index(",", end + 1) if "," in text[end + 1 :] else -1
        close = text.find("}", end + 1)
        if kind_end == -1 or (close != -1 and close < kind_end):
            # `{name, type}` or `{name, type, style}` without cases.
            found.setdefault(name, ("simple", frozenset()))
            depth = 1
            j = end + 1
            while depth:
                if j >= len(text):
                    raise IcuError("unterminated argument")
                depth += {"{": 1, "}": -1}.get(text[j], 0)
                j += 1
            return j
        kind = text[end + 1 : kind_end].strip()
        if kind not in ("plural", "select"):
            raise IcuError(f"unknown argument type {kind!r}")
        cases: list[str] = []
        j = kind_end + 1
        while True:
            while j < len(text) and text[j].isspace():
                j += 1
            if j >= len(text):
                raise IcuError("unterminated plural or select")
            if text[j] == "}":
                break
            selector_end = text.index("{", j)
            cases.append(text[j:selector_end].strip())
            j = parse(text, selector_end + 1, True) + 1
        if "other" not in cases:
            raise IcuError(f"{kind} argument {name!r} has no 'other' case")
        found[name] = (kind, frozenset(cases))
        return j + 1

    parse(message, 0, False)
    return found


def used_keys(candidates: set[str]) -> set[str]:
    sources = [
        path.read_text(encoding="utf-8")
        for path in (ROOT / "lib").rglob("*.dart")
        if not path.relative_to(ROOT).as_posix().startswith("lib/l10n/")
    ]
    # The developer gallery lives with the tests; only its own `gallery*`
    # messages may be used from there.
    gallery = (ROOT / "test" / "support" / "component_gallery.dart").read_text(encoding="utf-8")
    sources.append(
        "\n".join(re.findall(r"\.\s*gallery[A-Za-z0-9_]*", gallery))
    )
    text = "\n".join(sources)
    identifiers = set(re.findall(r"\.\s*([A-Za-z_][A-Za-z0-9_]*)", text))
    return candidates & identifiers


def main() -> int:
    report = "--report" in sys.argv
    english = json.loads((L10N / "app_en.arb").read_text(encoding="utf-8"))
    german = json.loads((L10N / "app_de.arb").read_text(encoding="utf-8"))
    english_keys = keys(english)
    german_keys = keys(german)
    errors: list[str] = []
    if english_keys != german_keys:
        errors.append(
            "ARB key mismatch: "
            f"missing in German={sorted(english_keys - german_keys)}, "
            f"missing in English={sorted(german_keys - english_keys)}"
        )
    missing_metadata = sorted(
        key for key in english_keys if f"@{key}" not in english
    )
    if missing_metadata:
        errors.append(f"English ARB metadata missing for: {missing_metadata}")
    orphan_metadata = sorted(
        key[1:]
        for key in english
        if key.startswith("@") and not key.startswith("@@") and key[1:] not in english
    )
    if orphan_metadata:
        errors.append(f"English ARB metadata without a message: {orphan_metadata}")

    for key in sorted(english_keys & german_keys):
        try:
            en_args = arguments(str(english[key]))
            de_args = arguments(str(german[key]))
        except IcuError as error:
            errors.append(f"{key}: invalid message ({error})")
            continue
        if set(en_args) != set(de_args):
            errors.append(
                f"{key}: placeholders differ "
                f"(en={sorted(en_args)}, de={sorted(de_args)})"
            )
            continue
        for name, (kind, cases) in en_args.items():
            de_kind, de_cases = de_args[name]
            if kind != de_kind:
                errors.append(f"{key}: '{name}' is {kind} in English, {de_kind} in German")
            elif kind == "select" and cases != de_cases:
                errors.append(
                    f"{key}: select '{name}' cases differ "
                    f"(en={sorted(cases)}, de={sorted(de_cases)})"
                )
            elif kind == "plural" and cases != de_cases:
                errors.append(
                    f"{key}: plural '{name}' cases differ "
                    f"(en={sorted(cases)}, de={sorted(de_cases)})"
                )

    unused = sorted(english_keys - used_keys(english_keys))
    if unused:
        errors.append(f"unused messages ({len(unused)}): {unused}")

    by_english: dict[str, dict[str, list[str]]] = {}
    for key in sorted(english_keys & german_keys):
        text = str(english[key])
        by_english.setdefault(text, {}).setdefault(str(german[key]), []).append(key)
    for text, translations in sorted(by_english.items()):
        if len(translations) < 2 or text in DIVERGENT_ALLOWED:
            continue
        variants = "; ".join(
            f"{translation!r} ({', '.join(keys_)})"
            for translation, keys_ in sorted(translations.items())
        )
        errors.append(f"divergent German translations of {text!r}: {variants}")

    stale_allowance = sorted(
        text
        for text in DIVERGENT_ALLOWED
        if len(by_english.get(text, {})) < 2
    )
    if stale_allowance:
        errors.append(f"DIVERGENT_ALLOWED entries no longer needed: {stale_allowance}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 0 if report else 1
    print(f"localization catalogs valid: {len(english_keys)} messages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
