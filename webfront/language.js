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
    "brand.label": "GitLama-Startseite",
    "nav.label": "Hauptnavigation",
    "nav.features": "Funktionen",
    "nav.remote": "Remote",
    "nav.download": "Download",
    "nav.releases": "Versionen",
    "language.label": "Sprache",
    "footer.tagline": "Ein Desktop-Client für Git von Devmil Solutions.",
    "footer.label": "Rechtliches",
    "footer.releases": "Versionen",
    "footer.license": "Lizenz",
    "footer.imprint": "Impressum",
    "footer.privacy": "Datenschutz",
    "footer.note": "Keine Webanalyse. Keine Tracking-Skripte.",

    "index.title": "GitLama · Dein Repository im Blick",
    "index.description": "GitLama ist ein Desktop-Client für Git unter macOS, Linux und Windows, entwickelt mit Flutter und Rust. Über SSH arbeitet er auch mit Repositorys auf anderen Rechnern.",
    "hero.eyebrow": "Git-Client für macOS, Linux und Windows",
    "hero.title1": "Dein Repository",
    "hero.title2": "im Blick.",
    "hero.intro": "GitLama ist ein Desktop-Client für Git. Er zeigt den Versionsgraphen, deine Änderungen und den ausgewählten Diff in einem Fenster.",
    "hero.download": "Herunterladen",
    "hero.what": "Was GitLama kann",
    "hero.note": "Beta. Freie Software unter GPL-3.0-or-later. Entwickelt mit Flutter und Rust.",
    "shot.label": "Der GitLama-Arbeitsbereich",
    "shot.theme": "Darstellung des Screenshots",
    "shot.light": "Hell",
    "shot.dark": "Dunkel",
    "shot.alt": "Der GitLama-Arbeitsbereich: eine Seitenleiste mit Branches, Remotes und Tags, der Versionsgraph mit einem zusammengeführten Feature-Branch und darunter der ausgewählte Commit mit seinen geänderten Dateien",
    "shot.caption": "Links die Seitenleiste, oben der Versionsgraph, darunter der ausgewählte Commit. Von der App selbst mit Beispieldaten gerendert.",
    "features.eyebrow": "Funktionen",
    "features.title": "Was GitLama kann",
    "features.intro": "Die alltäglichen Git-Aufgaben – und einige, für die man sonst ins Terminal wechseln muss.",
    "feature.changes.title": "Änderungen",
    "feature.changes.body": "Dateien, Hunks oder einzelne Zeilen vormerken. Diffs vereinheitlicht oder nebeneinander ansehen, auch bei Bildern und anderen Zeichenkodierungen. Commits mit Amend, Sign-off, Vorlagen und Co-Autoren erstellen.",
    "feature.history.title": "Verlauf",
    "feature.history.body": "Ein Versionsgraph mit Dateibäumen, Blame und Reflog. Zwei Commits vergleichen, Commit-Inhalte durchsuchen und einen Bisect Schritt für Schritt durchlaufen.",
    "feature.branches.title": "Branches und Umschreiben",
    "feature.branches.body": "Erstellen, umbenennen, mergen, cherry-picken und reverten. Interaktiver Rebase, Autosquash und Restack zeigen vor dem Ausführen eine Vorschau.",
    "feature.remotes.title": "Remotes und Hosting",
    "feature.remotes.body": "Fetch, Pull und Push, mit Force-with-Lease als bewusster Wahl. GitHub, GitLab, Forgejo oder Codeberg für Pull-Requests und Review-Entwürfe verbinden.",
    "feature.tools.title": "Worktrees und Werkzeuge",
    "feature.tools.body": "Worktrees, Submodule und Git LFS verwalten. Editor, Terminal, Diff- oder Merge-Tool öffnen und eigene Befehle hinzufügen.",
    "feature.recovery.title": "Wiederherstellung",
    "feature.recovery.body": "Konflikte und Rebases nach einem Neustart fortsetzen. Benannte Snapshots und Rückgängig pro Repository erlauben den Schritt zurück. Ist ein Ergebnis unklar, sagt die App das.",
    "graph.eyebrow": "Der Graph",
    "graph.title": "Spuren, die ihren Platz halten",
    "graph.body": "Der aktuelle Branch verläuft in der ersten Spur. Andere Branches zweigen in Kurven ab und münden wieder ein. So lässt sich ein Merge leicht verfolgen.",
    "graph.point1": "Wählst du einen Commit, werden seine Vorfahren hervorgehoben und alle anderen abgeblendet.",
    "graph.point2": "Branch-, Remote- und Tag-Labels stehen an dem Commit, auf den sie zeigen.",
    "graph.point3": "Befehlspalette, Hinweise auf Tastenkürzel und native Menüs lassen sich mit der Tastatur bedienen.",
    "graph.model": "Modell eines Versionsgraphen. Wähle einen Commit, um seine Vorfahren hervorzuheben.",
    "graph.note": "Ein Modell, nicht die App. Wähle einen Commit, um seine Vorfahren hervorzuheben.",
    "changes.eyebrow": "Änderungen",
    "changes.title": "Genau die Zeilen vormerken, die du meinst",
    "changes.body": "Wähle einzelne Zeilen aus einem Diff aus; der Rest bleibt nicht vorgemerkt. Das geht genauso mit Hunks und ganzen Dateien.",
    "changes.point1": "Vereinheitlichte Ansicht oder Ansicht nebeneinander, mit Einstellungen für Leerraum und Kontext.",
    "changes.point2": "Der Commit-Editor merkt sich für jeden Worktree einen eigenen Entwurf.",
    "remote.eyebrow": "Remote-Arbeitsbereiche",
    "remote.title": "Mit Repositorys auf einem anderen Computer arbeiten",
    "remote.body": "Öffne über dein gewohntes SSH ein Repository auf einem Linux-Rechner, einem Mac oder einem Raspberry\u00a0Pi. Nichts wird geklont: Das Repository bleibt, wo es ist, und GitLama zeigt Verlauf, Änderungen und Diffs, als läge es auf deinem eigenen Rechner.",
    "remote.point1": "GitLama nutzt deine SSH-Konfiguration, deine Schlüssel und deinen Agenten. Es fragt nie nach einem Passwort und akzeptiert nie einen unbekannten Host-Schlüssel.",
    "remote.point2": "Schreibgeschützt, bis du Änderungen für einen Host erlaubst. Dann laufen Vormerken, Commits, Branches, Stashes, Fetch, Pull und Push auf diesem Rechner – mit dessen eigenen Git-Zugangsdaten.",
    "remote.point3": "Jeder Host bekommt eine eigene Farbe und ein eigenes Symbol. So weißt du immer, zu welchem Rechner ein Tab gehört.",
    "remote.point4": "Bricht die Verbindung ab, wird sie von selbst wiederhergestellt, und keine Änderung wird doppelt gesendet.",
    "diff.unstaged": "Nicht vorgemerkt",
    "diff.stageHunk": "Hunk vormerken",
    "diff.model": "Modell eines nicht vorgemerkten Diffs",
    "diff.clean": "Nichts mehr vorzumerken.",
    "diff.cleanHint": "Bearbeite die Datei erneut, dann erscheinen die neuen Änderungen hier.",
    "diff.note": "Ein Modell, nicht die App. Klicke auf eine Zeilennummer, um geänderte Zeilen auszuwählen, und merke sie dann vor.",
    "download.eyebrow": "Download",
    "download.title": "GitLama herunterladen",
    "download.body": "GitLama befindet sich in der Beta-Phase und nutzt dein installiertes Git ab Version\u00a02.39. Öffne ein Repository, und schon kann es losgehen.",
    "download.none": "Noch keine verifizierte öffentliche Version verfügbar.",
    "verify.summary": "Download prüfen",
    "verify.body": "Zu jedem Paket ist die SHA-256-Prüfsumme angegeben. Kopiere sie mit der Schaltfläche neben dem Paket und vergleiche sie mit deiner Datei.",
    "verify.trust": "Die Links auf dieser Seite stammen aus einem mit Ed25519 signierten Release-Index.",
    "verify.key": "Öffentlicher Schlüssel",

    "releases.title": "Versionshinweise · GitLama",
    "releases.description": "Verifizierte Versionshinweise zu GitLama.",
    "releases.eyebrow": "VERSIONSVERLAUF",
    "releases.heading": "Versionshinweise",
    "releases.intro": "Diese Hinweise werden aus denselben signierten, archivierten Metadaten erzeugt wie die Download-Seite. Die Hinweise selbst gibt es nur auf Englisch.",

    "license.title": "Lizenz · GitLama",
    "license.description": "Lizenzinformationen zu GitLama.",
    "license.eyebrow": "LIZENZ",
    "license.heading": "Freie Software, alle Hinweise inklusive.",
    "license.body": "GitLama wird unter der GNU General Public License, Version\u00a03 oder später, verbreitet. Du darfst es unter diesen Bedingungen nutzen, untersuchen, verändern und weitergeben.",
    "license.link": "Lizenztext der GPL-3.0 lesen",
    "license.thirdTitle": "Werke Dritter",
    "license.third": "Die Release-Pakete enthalten die Drittanbieter-Hinweise des Projekts und die generierten Verzeichnisse der Rust- und Flutter-Abhängigkeiten. Diese Komponenten stehen weiterhin unter ihren jeweiligen Lizenzen.",
    "license.warrantyTitle": "Keine Gewährleistung",
    "license.warranty": "GitLama wird ohne Gewährleistung bereitgestellt, soweit das geltende Recht dies zulässt. Prüfe vor destruktiven Repository-Operationen deine Änderungen und Backups.",
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
      "package.msi": "Installationsprogramm", "package.msi.hint": "64-Bit-Windows",
      "package.AppImage": "AppImage", "package.AppImage.hint": "Eine einzige portable Datei",
      "package.deb": "DEB-Paket", "package.deb.hint": "Debian, Ubuntu und Derivate",
      "package.rpm": "RPM-Paket", "package.rpm.hint": "Fedora und andere RPM-basierte Distributionen",
      "package.tar.gz": "Tarball", "package.tar.gz.hint": "Portables Archiv",
      "release.notes": "Versionshinweise",
      "release.build": "Build {build} · Kanal {channel}",
      "release.label": "{version} · Build {build}",
      "release.yourSystem": "Dein System",
      "release.downloadFor": "Für {platform} herunterladen",
      "release.downloadFile": "{file} herunterladen",
      "release.copyChecksum": "SHA-256-Prüfsumme von {file} kopieren",
      "release.copied": "Kopiert",
      "release.copyFailed": "Fehlgeschlagen",
      "release.allChanges": "Alle {count} Änderungen",
      "release.changedIn": "Änderungen in {version}",
      "release.none": "Noch keine verifizierte öffentliche Version verfügbar.",
      "diff.stage": "Vormerken",
      "diff.staged": "{staged} vorgemerkt · {changes} nicht vorgemerkt",
      "diff.unstagedCount": "{changes} nicht vorgemerkt",
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
