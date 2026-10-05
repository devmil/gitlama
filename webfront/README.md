# GitLama public website

Run `python3 -m http.server 4173 --directory webfront` and open
`http://localhost:4173`. The checked-in site shows a deliberate unavailable
state until an authorized release transaction writes `_data/releases.json`.

The page contains no analytics, cookies or third-party scripts. Platform links
are rendered only from the signed retained release index and are restricted in
the browser to unauthenticated `https://github.com/` URLs. The release workflow
verifies Forgejo and the complete public GitHub mirror before it updates the
index. `northspline-release-ed25519.pub` is the versioned offline trust root.

`appcast.xml` is the update feed of the macOS application. The release workflow
renders it from the verified index; it lists only packages that carry an
update signature. Do not edit it by hand.

The site follows Meridian's GitLama brand (light and dark from
`prefers-color-scheme`): islands on the ground, the Git ember accent only for intent, lane
colours only for topology. The hero is a stage on the brand ground `#53261B`
where `site.js` draws the generated lane field with the Meridian graph geometry
and lane-focus behaviour. The Lama stands on a merge there, as in the app icon:
it opens with the hello pose, settles proud, and hops when a commit runs into
the merge. The ivory Lama appears only on the brand ground (stage, download
island, small brand tiles); the footer carries the single-ink family signature.
`site.js` also runs the small graph and diff models; it honours reduced motion
and loads no data. `assets/lama/` holds byte-identical copies of the vendored
masters in `resources/brand/`, copied by `scripts/generate-brand.py`. `releases.js`
alone reads the release index. Platform marks in `assets/platform/` come from
Simple Icons (CC0) except the Windows mark; `assets/icons/` holds Lucide icons.
`assets/fonts/JetBrainsMono-Regular.woff2` is a Latin subset of the design
system's JetBrains Mono, made with `pyftsubset --flavor=woff2`. The workspace screenshots are rendered from the real
app by the opt-in `website workspace capture` test in
`test/home_screen_test.dart`; its comment has the command.

Forgejo is authoritative and the public GitHub repository is a mirror.
`.forgejo/workflows/sync-website.yml` runs on every push to `main` that touches
the site and mirrors `webfront/` into the GitHub repository's `webfront/`
directory, together with `.github/workflows/gitlama-pages.yml`, which
deploys it with GitHub Pages. Releases publish the signed index through the
same mirror. The mirror owns only files recorded by
`.northspline-managed-files.json` in a directory carrying the exact
`.northspline-site-owner` marker, and a Pages workflow carrying its ownership
line. It uses a separate checkout credential and a normal fast-forward push; it
never force-pushes or claims an unrelated tree. GitHub Pages must be set to
deploy from GitHub Actions in the mirror's settings.

Local asset references in the pages and `style.css` carry a `?v=` content
digest, so a returning browser fetches changed styles, scripts and images.
After changing anything under `webfront/`, run
`python3 scripts/generate_webfront_versions.py` (`scripts/generate-brand.py`
runs it after copying brand derivatives); the website fixture fails while a
digest is stale.

Run the static and publication fixtures with:

```text
python3 -m unittest tests.package.test_release_website -v
python3 scripts/qualify-website.py --chrome /path/to/chrome-headless-shell
```
