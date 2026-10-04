// Renders downloads and release notes from the signed release index. Every
// value from the index reaches the page through textContent, and a link is
// rendered only for an unauthenticated https://github.com/ URL.
(function () {
  "use strict";

  const status = document.getElementById("release-status");
  const downloads = document.getElementById("download-grid");
  const releaseBar = document.getElementById("release-bar");
  const latestNotes = document.getElementById("latest-notes");
  const releaseList = document.getElementById("release-list");

  const formats = { macos: ["dmg"], windows: ["msi"], linux: ["AppImage", "deb", "rpm", "tar.gz"] };
  const platforms = {
    macos: { label: "macOS", icon: "apple" },
    windows: { label: "Windows", icon: "windows" },
    linux: { label: "Linux", icon: "linux" },
  };
  const packages = {
    dmg: { name: "Disk image", hint: "Apple silicon", icons: ["apple"] },
    msi: { name: "Installer", hint: "64-bit Windows", icons: ["windows"] },
    AppImage: { name: "AppImage", hint: "One portable file", icons: ["appimage"] },
    deb: { name: "DEB package", hint: "Debian, Ubuntu and derivatives", icons: ["debian", "ubuntu"] },
    rpm: { name: "RPM package", hint: "Fedora and other RPM-based distributions", icons: ["fedora"] },
    "tar.gz": { name: "Tarball", hint: "Portable archive", icons: ["archive"] },
  };

  function validAsset(a) {
    if (!a || typeof a !== "object" || !Object.hasOwn(formats, a.platform)
        || !formats[a.platform].includes(a.format) || typeof a.url !== "string") return false;
    try {
      const u = new URL(a.url);
      return u.protocol === "https:" && !u.username && !u.password && u.hostname==="github.com";
    } catch (_) {
      return false;
    }
  }

  function valid(d) {
    return d && d.schema_version === 1 && d.product === "GitLama" && d.latest
      && Array.isArray(d.latest.assets) && d.latest.assets.length === 6
      && d.latest.assets.every(validAsset)
      && Array.isArray(d.releases) && d.releases.length > 0 && d.releases.length <= 10;
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function icon(path) {
    const node = element("span", "icon");
    node.style.setProperty("--icon", `url(${path})`);
    node.setAttribute("aria-hidden", "true");
    return node;
  }

  function megabytes(bytes) {
    return `${(bytes / 1048576).toFixed(1)} MB`;
  }

  // The visitor's desktop platform, or null on phones, tablets and unknowns.
  function detectPlatform() {
    const agent = navigator.userAgent || "";
    const name = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
    if (/android|iphone|ipad|ipod/i.test(agent)) return null;
    if (/mac/i.test(name)) return navigator.maxTouchPoints > 1 ? null : "macos";
    if (/win/i.test(name)) return "windows";
    if (/linux|x11/i.test(name)) return "linux";
    return null;
  }

  // Browsers on some distributions name it; otherwise AppImage runs anywhere.
  function suggestedFormat(platform) {
    if (platform !== "linux") return formats[platform][0];
    const agent = navigator.userAgent || "";
    if (/ubuntu|debian|mint/i.test(agent)) return "deb";
    if (/fedora|red hat|suse/i.test(agent)) return "rpm";
    return "AppImage";
  }

  function copyChecksum(button, asset) {
    const restore = () => { button.textContent = "SHA-256"; };
    const done = (text) => { button.textContent = text; setTimeout(restore, 1600); };
    if (!navigator.clipboard) { window.prompt("SHA-256", asset.sha256); return; }
    navigator.clipboard.writeText(asset.sha256).then(() => done("Copied"), () => done("Failed"));
  }

  function assetRow(asset, suggested) {
    const kind = packages[asset.format];
    const row = element("li", suggested ? "asset suggested" : "asset");
    const icons = element("span", "asset-icons");
    kind.icons.forEach((name) => icons.append(icon(`assets/platform/${name}.svg`)));
    const text = element("span");
    const name = element("a", "asset-name", kind.name);
    name.href = asset.url;
    name.rel = "noopener";
    name.setAttribute("aria-label", `Download ${asset.file}`);
    text.append(name, element("span", "asset-hint", kind.hint));
    const meta = element("span", "asset-meta",
      `.${asset.format} · ${asset.architecture} · ${megabytes(asset.bytes)}`);
    const tail = element("span", "asset-tail");
    if (/^[0-9a-f]{64}$/.test(asset.sha256)) {
      const sha = element("button", "sha", "SHA-256");
      sha.type = "button";
      sha.title = asset.sha256;
      sha.setAttribute("aria-label", `Copy the SHA-256 checksum of ${asset.file}`);
      sha.addEventListener("click", () => copyChecksum(sha, asset));
      tail.append(sha);
    }
    const get = element("span", "asset-get");
    get.append(icon("assets/icons/download.svg"));
    tail.append(get);
    row.append(icons, text, meta, tail);
    return row;
  }

  function renderDownloads(r) {
    if (!status || !downloads) return;
    const detected = detectPlatform();
    status.hidden = true;

    if (releaseBar) {
      const notes = element("a", "", "Release notes");
      notes.href = "releases.html";
      releaseBar.append(element("span", "chip head plain", r.version),
        element("span", "", `Build ${r.build} · ${r.channel} channel`), notes);
      releaseBar.hidden = false;
    }

    downloads.hidden = false;
    for (const platform of ["macos", "windows", "linux"]) {
      const assets = r.assets.filter((a) => a.platform === platform);
      const card = element("article", "platform");
      card.dataset.platform = platform;
      const head = element("div", "platform-head");
      const mark = element("span", "platform-mark");
      mark.append(icon(`assets/platform/${platforms[platform].icon}.svg`));
      const title = element("div");
      title.append(element("h3", "", platforms[platform].label), element("p", "", assets[0].minimum_system));
      head.append(mark, title);
      if (platform === detected) head.append(element("span", "chip plain", "Your system"));
      const list = element("ul", "assets");
      const suggested = platform === detected ? suggestedFormat(platform) : null;
      formats[platform].forEach((format) => {
        const asset = assets.find((a) => a.format === format);
        if (asset) list.append(assetRow(asset, format === suggested));
      });
      card.append(head, list);
      downloads.append(card);
    }

    const label = `${r.version} · build ${r.build}`;
    const headerRelease = document.getElementById("header-release");
    if (headerRelease) headerRelease.textContent = r.version;
    const heroRelease = document.getElementById("hero-release");
    if (heroRelease) heroRelease.textContent = label;
    const heroDownload = document.getElementById("hero-download");
    if (heroDownload && detected) {
      heroDownload.lastElementChild.textContent = `Download for ${platforms[detected].label}`;
    }

    if (latestNotes && Array.isArray(r.notes) && r.notes.length) {
      const list = element("ul");
      r.notes.slice(0, 3).forEach((note) => list.append(element("li", "", note)));
      const more = element("a", "", r.notes.length > 3 ? `All ${r.notes.length} changes` : "Release notes");
      more.href = "releases.html";
      latestNotes.append(element("h3", "", `Changed in ${r.version}`), list, more);
      latestNotes.hidden = false;
    }
  }

  function renderNotes(releases) {
    if (!releaseList) return;
    releaseList.textContent = "";
    for (const r of releases) {
      const record = element("article", "release-record");
      record.append(element("h2", "", `${r.version} · build ${r.build}`),
        element("p", "", `${r.channel} · ${r.tag}`));
      if (Array.isArray(r.notes) && r.notes.length) {
        const list = element("ul");
        r.notes.forEach((note) => list.append(element("li", "", note)));
        record.append(list);
      }
      const order = ["dmg", "msi", "AppImage", "deb", "rpm", "tar.gz"];
      const assets = Array.isArray(r.assets) ? r.assets.filter(validAsset) : [];
      assets.sort((a, b) => order.indexOf(a.format) - order.indexOf(b.format));
      if (assets.length) {
        const links = element("div", "formats");
        assets.forEach((asset) => {
          const anchor = element("a", "", `${platforms[asset.platform].label} .${asset.format}`);
          anchor.href = asset.url;
          anchor.rel = "noopener";
          links.append(anchor);
        });
        record.append(links);
      }
      releaseList.append(record);
    }
  }

  fetch("_data/releases.json", { cache: "no-store" })
    .then((response) => {
      if (!response.ok) throw new Error("unavailable");
      return response.json();
    })
    .then((data) => {
      if (!valid(data)) throw new Error("invalid");
      renderDownloads(data.latest);
      renderNotes(data.releases);
    })
    .catch(() => {
      if (releaseList) releaseList.textContent = "No verified public release is available yet.";
    });
})();
