from html.parser import HTMLParser
import json
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.lib.package_contract import TARGETS, Version, artifact_name
from scripts.lib.release_manifest import build_manifest, encode
from scripts.lib.release_signing import openssl_binary, sign_manifest, write_public_key
from scripts.lib.release_website import sync_index, write_receipt


class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.images = []; self.ids = set()

    def handle_starttag(self, tag, attributes):
        values = dict(attributes)
        if "id" in values: self.ids.add(values["id"])
        if tag in {"a", "link", "script", "img", "image"}:
            value = values.get("href") or values.get("src")
            if value: self.links.append(value)
        if tag == "img": self.images.append(values)


PAGES = ("index.html", "releases.html", "license.html", "privacy.html", "imprint.html",
         "de/privacy.html", "de/imprint.html")
LEGAL = ("imprint", "privacy")


class ReleaseWebsiteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(); self.root = Path(self.temporary.name)
        self.key = self.root / "key.pem"
        subprocess.run([openssl_binary(), "genpkey", "-algorithm", "ED25519", "-out", self.key], check=True)
        self.key.chmod(0o600); self.public = self.root / "public.pub"
        write_public_key(self.public, key_file=self.key)
        self.candidate = self.root / "candidate"; self.candidate.mkdir()
        version = Version("1.2.3", 7)
        for index, target in enumerate(TARGETS):
            (self.candidate / artifact_name(version, *target)).write_bytes(f"web-{index}".encode())
        document = build_manifest(self.candidate, version,
                                  "https://github.com/devmil/gitlama/releases/download/v1.2.3-7", "stable")
        self.manifest = self.root / "metadata.json"; self.manifest.write_bytes(encode(document))
        self.signature = self.root / "metadata.json.sig"
        sign_manifest(self.manifest, self.signature, key_file=self.key)

    def tearDown(self) -> None: self.temporary.cleanup()

    def test_index_changes_only_after_matching_release_receipt(self) -> None:
        site = self.root / "site"; site.mkdir(); data = site / "_data"; data.mkdir()
        old = b"previous\n"; (data / "releases.json").write_bytes(old)
        receipt = self.root / "receipt.json"
        write_receipt(receipt, self.manifest, "v1.2.3-7")
        changed = json.loads(receipt.read_text()); changed["github_release"] = "failed"
        receipt.write_text(json.dumps(changed), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "receipt"):
            sync_index(site, self.manifest, self.signature, self.public, receipt, "v1.2.3-7")
        self.assertEqual((data / "releases.json").read_bytes(), old)
        write_receipt(receipt, self.manifest, "v1.2.3-7")
        sync_index(site, self.manifest, self.signature, self.public, receipt, "v1.2.3-7")
        self.assertEqual((data / "releases.json").read_bytes(), self.manifest.read_bytes())
        channels = json.loads((data / "channels.json").read_text())
        self.assertEqual(channels["channels"]["stable"]["tag"], "v1.2.3-7")

    def test_release_deploys_the_committed_index_without_force(self) -> None:
        pages = Path(".github/workflows/gitlama-pages.yml").read_text(encoding="utf-8")
        self.assertIn("'webfront/**'", pages)
        self.assertIn("path: ./webfront", pages)
        self.assertIn("workflow_call:", pages)
        self.assertIn("ref: ${{ inputs.ref || github.sha }}", pages)
        release = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
        website = release.split("\n  website:\n", 1)[1]
        self.assertIn("needs: [prepare, publish]", website)
        self.assertIn("uses: ./.github/workflows/gitlama-pages.yml", website)
        self.assertIn("ref: main", website)
        self.assertNotIn("--force", release)

    def test_website_asset_urls_carry_current_content_versions(self) -> None:
        # A returning browser must never keep a stale stylesheet, script or image.
        from scripts.generate_webfront_versions import stale
        self.assertEqual(stale(), [])
        index = Path("webfront/index.html").read_text(encoding="utf-8")
        for name in ("style.css", "site.js", "releases.js", "assets/icon-32.png",
                     "assets/lama/lama-antics.css", "assets/lama/lama-antics.js",
                     "https://devmil.de/gitlama/assets/feature-graphic.png"):
            self.assertRegex(index, re.escape(name) + r"\?v=[0-9a-f]{12}\"")

    def test_static_pages_have_landmarks_alt_text_focus_and_no_broken_local_links(self) -> None:
        root = Path("webfront")
        for page in PAGES:
            parser = Links(); text = (root / page).read_text(encoding="utf-8"); parser.feed(text)
            self.assertIn("<main", text); self.assertIn("skip-link", text)
            for image in parser.images: self.assertIn("alt", image)
            for link in parser.links:
                if link.startswith(("http://", "https://", "#")): continue
                path = link.split("#", 1)[0].split("?", 1)[0]
                if path:
                    self.assertTrue(((root / page).parent / path).resolve().is_file(),
                                    f"broken {page}: {link}")
        style = (root / "style.css").read_text(encoding="utf-8")
        self.assertIn(":focus-visible", style); self.assertIn("prefers-reduced-motion", style)
        self.assertIn("@media(max-width:620px)", style)
        self.assertEqual((root / "northspline-release-ed25519.pub").read_bytes(),
                         Path("release/northspline-release-ed25519.pub").read_bytes())
        def luminance(color):
            channels = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
            linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
                      for value in channels]
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        def contrast(first, second):
            light, dark = sorted((luminance(first), luminance(second)), reverse=True)
            return (light + 0.05) / (dark + 0.05)
        # Meridian's GitLama pairs, light then dark: muted text on the
        # ground and on islands, accent text on islands, text on the accent.
        pairs = (("#52616A", "#E8ECEE"), ("#52616A", "#FFFFFF"), ("#0160A0", "#FFFFFF"),
                 ("#FFFFFF", "#056CB3"), ("#FFFFFF", "#045B98"), ("#93A5AE", "#0B151A"),
                 ("#93A5AE", "#122027"), ("#87C4FE", "#122027"), ("#06111D", "#5BB1FE"),
                 ("#06111D", "#87C4FE"),
                 # The brand-ground stage and download island, in both appearances:
                 # copy, muted copy and the stage's accent.
                 ("#F4F7F8", "#14242B"), ("#A9BAC2", "#14242B"), ("#5BB1FE", "#14242B"),
                 # The active language switch label, light then dark.
                 ("#0160A0", "#DBEBFC"), ("#87C4FE", "#16334D"))
        for foreground, background in pairs:
            self.assertIn(foreground, style); self.assertIn(background, style)
            self.assertGreaterEqual(contrast(foreground, background), 4.5,
                                    f"{foreground} on {background}")
        # The ivory Lama needs the brand ground: every pose sits in the stage,
        # a brand tile or the download island, and comes from the vendored masters.
        index = (root / "index.html").read_text(encoding="utf-8")
        for pose in re.findall(r'assets/lama/(lama-[a-z-]+\.svg)', index + style):
            self.assertEqual((root / "assets/lama" / pose).read_bytes(),
                             Path("resources/brand", pose).read_bytes(), pose)
        self.assertIn("background: var(--brand)", style)
        script = (root / "releases.js").read_text(encoding="utf-8")
        # Icons are named in the script, so the link check above misses them.
        for name in re.findall(r'"([a-z]+)"', script.split("function validAsset")[0]):
            if name in {"apple", "windows", "linux", "appimage", "debian", "ubuntu", "fedora", "archive"}:
                self.assertTrue((root / "assets/platform" / f"{name}.svg").is_file(), name)
        self.assertTrue((root / "assets/fonts/OFL.txt").is_file())
        self.assertIn('u.hostname==="github.com"', script)

    def test_published_files_never_contain_the_joined_contact_address(self) -> None:
        address = "@".join(("info", ".".join(("devmil", "de"))))
        for path in Path("webfront").rglob("*"):
            if path.is_file() and path.suffix in {".html", ".js", ".css", ".json", ".xml", ".map", ".txt"}:
                text = path.read_text(encoding="utf-8").lower()
                self.assertNotIn(address, text, str(path))
                self.assertNotIn("mailto:" + "info", text, str(path))

    def test_every_page_links_both_legal_pages_and_legal_pages_pair_languages(self) -> None:
        root = Path("webfront")
        for page in PAGES:
            text = (root / page).read_text(encoding="utf-8")
            german = page.startswith("de/")
            for name in LEGAL:
                self.assertIn(f'href="{name}.html"', text, page)
            self.assertIn(">Impressum<" if german else ">Imprint<", text, page)
            self.assertIn(">Datenschutz<" if german else ">Privacy<", text, page)
            self.assertIn('class="language-switch"', text, page)
            self.assertIn("language.js", text, page)
        for name in LEGAL:
            english = (root / f"{name}.html").read_text(encoding="utf-8")
            german = (root / "de" / f"{name}.html").read_text(encoding="utf-8")
            self.assertIn('<html lang="en" data-legal-page>', english)
            self.assertIn('<html lang="de" data-legal-page>', german)
            self.assertIn(f'href="de/{name}.html" lang="de"', english)
            self.assertIn(f'href="../{name}.html" lang="en"', german)
            for text in (english, german):
                self.assertIn('class="contact-email" data-user="info" data-domain="devmil" data-tld="de"', text)
            self.assertIn("[punkt]", german)
        sitemap = (root / "sitemap.xml").read_text(encoding="utf-8")
        for page in PAGES:
            location = "https://devmil.de/gitlama/" + ("" if page == "index.html" else page)
            self.assertIn(f"<loc>{location}</loc>", sitemap)

    def test_translated_pages_have_german_copy_for_every_key(self) -> None:
        root = Path("webfront")
        script = (root / "language.js").read_text(encoding="utf-8")
        self.assertIn('const KEY = "preferred-language";', script)
        german = script.split("const DE = {", 1)[1].split("\n  };", 1)[0]
        keys = set(re.findall(r'^\s*"([A-Za-z0-9.]+)":', german, re.M))
        messages = script.split("const MESSAGES = {", 1)[1]
        english, deutsch = messages.split("\n    de: {", 1)
        for page in ("index.html", "releases.html", "license.html"):
            text = (root / page).read_text(encoding="utf-8")
            used = set(re.findall(r'data-i18n="([^"]+)"', text))
            for pairs in re.findall(r'data-i18n-attr="([^"]+)"', text):
                used.update(pair.split(":", 1)[1] for pair in pairs.split(";"))
            self.assertTrue(used, page)
            self.assertEqual(used - keys, set(), page)
        for name in ("releases.js", "site.js"):
            for key in re.findall(r'\bt\(\s*"([a-zA-Z.]+)"', (root / name).read_text(encoding="utf-8")):
                self.assertIn(f'"{key}":', english, key); self.assertIn(f'"{key}":', deutsch, key)
        for key in re.findall(r'"(package\.[A-Za-z.]+)":', english):
            self.assertIn(f'"{key}":', deutsch, key)
        self.assertNotIn("innerHTML", script)


if __name__ == "__main__": unittest.main()
