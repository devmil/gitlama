"""Locate the resolved meridian_ui package and GitLama's icon names.

meridian_ui is a pinned Git dependency; `flutter pub get` records where it
was resolved in .dart_tool/package_config.json.
"""
from pathlib import Path
import json
import re
from urllib.parse import urlparse
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parent.parent
ALIASES = ROOT / "lib/app/gitlama_icons.dart"
ALIAS_PREFIX = "packages/meridian_ui/assets/icons/"


def meridian_root(root: Path = ROOT) -> Path:
    config = json.loads((root / ".dart_tool/package_config.json").read_text(encoding="utf-8"))
    for package in config["packages"]:
        if package["name"] == "meridian_ui":
            uri = package["rootUri"]
            if uri.startswith("file:"):
                return Path(url2pathname(urlparse(uri).path))
            return (root / ".dart_tool" / uri).resolve()
    raise SystemExit("meridian_ui is not resolved: run flutter pub get")


def meridian_icon_names(root: Path = ROOT) -> set[str]:
    spec = json.loads((meridian_root(root) / "tokens/icons.json").read_text(encoding="utf-8"))
    return {icon["name"] for icon in spec["icons"]}


def gitlama_icon_aliases(root: Path = ROOT) -> dict[str, str]:
    """Alias name -> the Meridian icon name it draws."""
    source = (root / ALIASES.relative_to(ROOT)).read_text(encoding="utf-8")
    return {
        alias: target
        for alias, target in re.findall(
            r"'([a-z0-9-]+)':\s*'" + re.escape(ALIAS_PREFIX) + r"([a-z0-9-]+)\.svg'", source
        )
    }


def available_icon_names(root: Path = ROOT) -> set[str]:
    return meridian_icon_names(root) | set(gitlama_icon_aliases(root))
