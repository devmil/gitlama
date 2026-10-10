// Language choice for the GitLama pages. English is the source text in the
// HTML; German copy lives here. The choice is shared with the other Devmil
// sites on this origin through the `preferred-language` key.
//
// Main pages swap text in place: an element with data-i18n="key" gets its
// text, data-i18n-attr="aria-label:key;alt:key" its attributes. Legal pages
// are separate files per language; their switch links to the counterpart
// and only records the choice. They never redirect.
//
// Every string reaches the page through textContent or setAttribute.
(function () {
  "use strict";

  const KEY = "preferred-language";
  const LANGUAGES = ["en", "de"];

  // German copy of the static pages, by data-i18n key.
  const DE = {
    "skip": "Zum Inhalt springen",
    "brand.label": "GitLama Startseite",
    "nav.label": "Hauptnavigation",
    "nav.features": "Funktionen",
    "nav.download": "Download",
    "nav.releases": "Versionen",
    "language.label": "Sprache",
    "footer.tagline": "Ein Git-Client für den Desktop von Devmil Solutions.",
    "footer.label": "Rechtliches",
    "footer.releases": "Versionshinweise",
    "footer.license": "Lizenz",
    "footer.imprint": "Impressum",
    "footer.privacy": "Datenschutz",
    "footer.note": "Keine Analyse. Keine Tracking-Skripte.",

    "index.title": "GitLama · Ihr Repository im Blick",
    "index.description": "GitLama ist ein Git-Client für macOS, Linux und Windows, entwickelt mit Flutter und Rust.",
    "hero.eyebrow": "Git-Client für macOS, Linux und Windows",
    "hero.title1": "Ihr Repository",
    "hero.title2": "im Blick.",
    "hero.intro": "GitLama ist ein Git-Client für den Desktop. Versionsgraph, Ihre Änderungen und der ausgewählte Diff stehen in einem Fenster.",
    "hero.download": "Herunterladen",
    "hero.what": "Was GitLama kann",
    "hero.note": "Beta. Freie Software unter GPL-3.0-or-later. Entwickelt mit Flutter und Rust.",
    "shot.label": "Der GitLama-Arbeitsbereich",
    "shot.theme": "Darstellung des Screenshots",
    "shot.light": "Hell",
    "shot.dark": "Dunkel",
    "shot.alt": "Der GitLama-Arbeitsbereich: eine Seitenleiste mit Branches, Remotes und Tags, der Versionsgraph mit einem zusammengeführten Feature-Branch und darunter der ausgewählte Commit mit seinen geänderten Dateien",
    "shot.caption": "Links die Seitenleiste, oben der Versionsgraph, darunter der ausgewählte Commit. Aus der App mit Beispieldaten gerendert.",
    "features.eyebrow": "Funktionen",
    "features.title": "Was GitLama kann",
    "features.intro": "Die alltäglichen Git-Aufgaben und einige, für die man sonst ins Terminal wechselt.",
    "feature.changes.title": "Änderungen",
    "feature.changes.body": "Dateien, Hunks oder einzelne Zeilen stagen. Diffs vereinheitlicht oder geteilt ansehen, auch für Bilder und andere Kodierungen. Committen mit Amend, Sign-off, Vorlagen und Co-Autoren.",
    "feature.history.title": "Verlauf",
    "feature.history.body": "Ein Versionsgraph mit Dateibäumen, Blame und Reflog. Zwei Commits vergleichen, Commit-Inhalte durchsuchen und Schritt für Schritt bisecten.",
    "feature.branches.title": "Branches und Umschreiben",
    "feature.branches.body": "Erstellen, umbenennen, mergen, cherry-picken und reverten. Interaktiver Rebase, Autosquash und Restacking zeigen vorher eine Vorschau.",
    "feature.remotes.title": "Remotes und Hosting",
    "feature.remotes.body": "Fetch, Pull und Push, mit Force-with-Lease als bewusster Wahl. GitHub, GitLab, Forgejo oder Codeberg verbinden, für Pull-Requests und Review-Entwürfe.",
    "feature.tools.title": "Worktrees und Werkzeuge",
    "feature.tools.body": "Worktrees, Submodule und Git LFS verwalten. Editor, Terminal, Diff- oder Merge-Tool öffnen und eigene Befehle hinzufügen.",
    "feature.recovery.title": "Wiederherstellung",
    "feature.recovery.body": "Konflikte und Rebases nach einem Neustart fortsetzen. Benannte Snapshots und Rückgängig pro Repository erlauben den Schritt zurück. Ist ein Ergebnis unklar, sagt die App das.",
    "graph.eyebrow": "Der Graph",
    "graph.title": "Spuren, die bleiben",
    "graph.body": "Der aktuelle Branch verläuft in der ersten Spur. Andere Branches zweigen in Kurven ab und münden wieder ein, so bleibt ein Merge leicht nachvollziehbar.",
    "graph.point1": "Ein ausgewählter Commit hebt seine Vorfahren hervor und blendet den Rest ab.",
    "graph.point2": "Branch-, Remote- und Tag-Labels sitzen auf dem Commit, auf den sie zeigen.",
    "graph.point3": "Befehlspalette, Tastenkürzel-Hinweise und native Menüs funktionieren mit der Tastatur.",
    "graph.model": "Modell eines Versionsgraphen. Wählen Sie einen Commit, um seine Vorfahren hervorzuheben.",
    "graph.note": "Ein Modell, nicht die App. Wählen Sie einen Commit, um seine Vorfahren hervorzuheben.",
    "changes.eyebrow": "Änderungen",
    "changes.title": "Genau die Zeilen stagen, die Sie meinen",
    "changes.body": "Einzelne Zeilen aus einem Diff auswählen und den Rest nicht stagen. Das geht auch mit Hunks und ganzen Dateien.",
    "changes.point1": "Vereinheitlichte und geteilte Ansicht, mit Einstellungen für Leerzeichen und Kontext.",
    "changes.point2": "Der Commit-Editor behält einen Entwurf pro Worktree.",
    "diff.unstaged": "Nicht gestaged",
    "diff.stageHunk": "Hunk stagen",
    "diff.model": "Modell eines nicht gestagten Diffs",
    "diff.clean": "Nichts mehr zu stagen.",
    "diff.cleanHint": "Bearbeiten Sie die Datei erneut, dann erscheinen die neuen Änderungen hier.",
    "diff.note": "Ein Modell, nicht die App. Klicken Sie auf eine Zeilennummer, um geänderte Zeilen auszuwählen, und stagen Sie sie dann.",
    "download.eyebrow": "Download",
    "download.title": "GitLama herunterladen",
    "download.body": "GitLama ist in der Beta-Phase. Es nutzt Ihr installiertes Git ab Version 2.39. Repository öffnen, und es kann losgehen.",
    "download.none": "Noch keine verifizierte öffentliche Version verfügbar.",
    "verify.summary": "Download prüfen",
    "verify.body": "Zu jedem Paket ist die SHA-256-Prüfsumme angegeben. Kopieren Sie sie mit der Schaltfläche neben dem Paket und vergleichen Sie sie mit Ihrer Datei.",
    "verify.trust": "Die Links auf dieser Seite stammen aus einem mit Ed25519 signierten Release-Index.",
    "verify.key": "Öffentlicher Schlüssel",

    "releases.title": "Versionshinweise · GitLama",
    "releases.description": "Verifizierte Versionshinweise zu GitLama.",
    "releases.eyebrow": "VERSIONSVERLAUF",
    "releases.heading": "Versionshinweise",
    "releases.intro": "Diese Hinweise stammen aus denselben signierten, aufbewahrten Metadaten wie die Download-Seite. Die Hinweise selbst gibt es nur auf Englisch.",

    "license.title": "Lizenz · GitLama",
    "license.description": "Lizenzinformationen zu GitLama.",
    "license.eyebrow": "LIZENZ",
    "license.heading": "Freie Software, mit allen Hinweisen.",
    "license.body": "GitLama wird unter der GNU General Public License, Version 3 oder später, verbreitet. Sie dürfen es unter diesen Bedingungen nutzen, untersuchen, verändern und weitergeben.",
    "license.link": "Lizenztext der GPL-3.0 lesen",
    "license.thirdTitle": "Werke Dritter",
    "license.third": "Die Release-Pakete enthalten die Hinweise des Projekts zu Drittkomponenten und die erzeugten Verzeichnisse der Rust- und Flutter-Abhängigkeiten. Diese Komponenten stehen weiterhin unter ihren jeweiligen Lizenzen.",
    "license.warrantyTitle": "Keine Gewährleistung",
    "license.warranty": "GitLama wird ohne Gewährleistung bereitgestellt, soweit das geltende Recht dies zulässt. Prüfen Sie Änderungen und Backups vor destruktiven Repository-Operationen.",
  };

  // Copy that releases.js and site.js build at run time.
  const MESSAGES = {
    en: {
      "package.dmg": "Disk image", "package.dmg.hint": "Apple silicon",
      "package.msi": "Installer", "package.msi.hint": "64-bit Windows",
      "package.AppImage": "AppImage", "package.AppImage.hint": "One portable file",
      "package.deb": "DEB package", "package.deb.hint": "Debian, Ubuntu and derivatives",
      "package.rpm": "RPM package", "package.rpm.hint": "Fedora and other RPM-based distributions",
      "package.tar.gz": "Tarball", "package.tar.gz.hint": "Portable archive",
      "release.notes": "Release notes",
      "release.build": "Build {build} · {channel} channel",
      "release.label": "{version} · build {build}",
      "release.yourSystem": "Your system",
      "release.downloadFor": "Download for {platform}",
      "release.downloadFile": "Download {file}",
      "release.copyChecksum": "Copy the SHA-256 checksum of {file}",
      "release.copied": "Copied",
      "release.copyFailed": "Failed",
      "release.allChanges": "All {count} changes",
      "release.changedIn": "Changed in {version}",
      "release.none": "No verified public release is available yet.",
      "diff.stage": "Stage",
      "diff.staged": "{staged} staged · {changes} unstaged",
      "diff.unstagedCount": "{changes} unstaged",
      "diff.startOver": "Start over",
      "diff.selectAdded": "Select added line: {code}",
      "diff.selectRemoved": "Select removed line: {code}",
    },
    de: {
      "package.dmg": "Disk-Image", "package.dmg.hint": "Apple Silicon",
      "package.msi": "Installationsprogramm", "package.msi.hint": "Windows, 64 Bit",
      "package.AppImage": "AppImage", "package.AppImage.hint": "Eine portable Datei",
      "package.deb": "DEB-Paket", "package.deb.hint": "Debian, Ubuntu und Derivate",
      "package.rpm": "RPM-Paket", "package.rpm.hint": "Fedora und andere RPM-basierte Distributionen",
      "package.tar.gz": "Tarball", "package.tar.gz.hint": "Portables Archiv",
      "release.notes": "Versionshinweise",
      "release.build": "Build {build} · Kanal {channel}",
      "release.label": "{version} · Build {build}",
      "release.yourSystem": "Ihr System",
      "release.downloadFor": "Für {platform} herunterladen",
      "release.downloadFile": "{file} herunterladen",
      "release.copyChecksum": "SHA-256-Prüfsumme von {file} kopieren",
      "release.copied": "Kopiert",
      "release.copyFailed": "Fehlgeschlagen",
      "release.allChanges": "Alle {count} Änderungen",
      "release.changedIn": "Neu in {version}",
      "release.none": "Noch keine verifizierte öffentliche Version verfügbar.",
      "diff.stage": "Stagen",
      "diff.staged": "{staged} gestaged · {changes} nicht gestaged",
      "diff.unstagedCount": "{changes} nicht gestaged",
      "diff.startOver": "Von vorn",
      "diff.selectAdded": "Hinzugefügte Zeile auswählen: {code}",
      "diff.selectRemoved": "Entfernte Zeile auswählen: {code}",
    },
  };

  const root = document.documentElement;
  // A legal page's language is the one in its URL.
  const legalPage = root.hasAttribute("data-legal-page");
  const english = new WeakMap();
  const listeners = [];
  let current = "en";

  function stored() {
    try {
      const value = window.localStorage.getItem(KEY);
      return LANGUAGES.includes(value) ? value : null;
    } catch (_) {
      return null;
    }
  }

  function store(language) {
    try {
      window.localStorage.setItem(KEY, language);
    } catch (_) {
      // Storage may be unavailable; the choice then lasts for this page.
    }
  }

  function initial() {
    const saved = stored();
    if (saved) return saved;
    return String(navigator.language || "").toLowerCase().startsWith("de") ? "de" : "en";
  }

  function t(key, values) {
    const table = MESSAGES[current] || MESSAGES.en;
    const text = Object.hasOwn(table, key) ? table[key] : MESSAGES.en[key];
    if (typeof text !== "string") return key;
    return text.replace(/\{(\w+)\}/g, (match, name) =>
      values && Object.hasOwn(values, name) ? String(values[name]) : match);
  }

  function copy(original, key) {
    return current === "de" && Object.hasOwn(DE, key) ? DE[key] : original;
  }

  // Translates [data-i18n] text and [data-i18n-attr] attributes under scope.
  function translate(scope) {
    const base = scope || document;
    const nodes = Array.from(base.querySelectorAll("[data-i18n], [data-i18n-attr]"));
    if (base.nodeType === 1 && base.matches("[data-i18n], [data-i18n-attr]")) nodes.unshift(base);
    for (const node of nodes) {
      if (!english.has(node)) {
        const attributes = {};
        for (const pair of (node.dataset.i18nAttr || "").split(";")) {
          const [name] = pair.split(":");
          if (name) attributes[name.trim()] = node.getAttribute(name.trim());
        }
        english.set(node, { text: node.dataset.i18n ? node.textContent : null, attributes });
      }
      const source = english.get(node);
      if (node.dataset.i18n) node.textContent = copy(source.text, node.dataset.i18n);
      for (const pair of (node.dataset.i18nAttr || "").split(";")) {
        const [name, key] = pair.split(":").map((part) => part && part.trim());
        if (name && key && source.attributes[name] !== null) {
          node.setAttribute(name, copy(source.attributes[name], key));
        }
      }
    }
  }

  function apply(language) {
    current = LANGUAGES.includes(language) ? language : "en";
    root.lang = current;
    translate(document);
    // Legal links work without JavaScript and point at the English pages;
    // here they follow the chosen language.
    for (const link of document.querySelectorAll("a[data-legal]")) {
      link.href = (current === "de" ? "de/" : "") + link.dataset.legal + ".html";
    }
    for (const button of document.querySelectorAll(".language-switch button[data-lang]")) {
      button.setAttribute("aria-pressed", String(button.dataset.lang === current));
    }
    listeners.forEach((listener) => listener(current));
  }

  function emails() {
    for (const el of document.querySelectorAll(".contact-email")) {
      const a = document.createElement("a");
      a.href = "#";
      a.textContent = el.textContent;
      a.addEventListener("click", (e) => {
        e.preventDefault();
        const d = el.dataset;
        window.location.href = "mail" + "to:" + d.user + "@" + d.domain + "." + d.tld;
      });
      el.replaceChildren(a);
    }
  }

  if (legalPage) {
    current = LANGUAGES.includes(root.lang) ? root.lang : "en";
    for (const link of document.querySelectorAll(".language-switch a[data-lang]")) {
      link.addEventListener("click", () => store(link.dataset.lang));
    }
  } else {
    for (const button of document.querySelectorAll(".language-switch button[data-lang]")) {
      button.addEventListener("click", () => {
        store(button.dataset.lang);
        apply(button.dataset.lang);
      });
    }
    for (const control of document.querySelectorAll(".language-switch[hidden]")) control.hidden = false;
    apply(initial());
  }
  emails();

  window.GitLamaLanguage = {
    current: () => current,
    t,
    translate,
    onChange(listener) { listeners.push(listener); },
  };
})();
