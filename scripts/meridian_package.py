"""Locate the vendored Meridian QML module and GitLama's icon names.

Meridian's QML module is vendored into qml/Meridian by scripts/sync-meridian.sh.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parent.parent
ALIASES = Path("qml/GitLama/GitLamaIcons.qml")


def meridian_root(root: Path = ROOT) -> Path:
    module = root / "qml/Meridian"
    if not (module / "qmldir").is_file():
        raise SystemExit("qml/Meridian is not vendored: run scripts/sync-meridian.sh")
    return module


def meridian_icon_names(root: Path = ROOT) -> set[str]:
    icons = (meridian_root(root) / "IconData.qml").read_text(encoding="utf-8")
    return set(json.loads(re.search(r"readonly property var names: (\[.*?\])", icons).group(1)))


def gitlama_icon_aliases(root: Path = ROOT) -> dict[str, str]:
    """Alias name -> the Meridian icon name it draws."""
    source = (root / ALIASES).read_text(encoding="utf-8")
    return dict(re.findall(r'"([a-z0-9-]+)"\s*:\s*"([a-z0-9-]+)"', source))


def available_icon_names(root: Path = ROOT) -> set[str]:
    return meridian_icon_names(root) | set(gitlama_icon_aliases(root))
