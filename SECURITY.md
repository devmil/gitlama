# Security policy

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
("Report a vulnerability" on the repository's Security tab), not in a public
issue. Include the GitLama version and build, your operating system and the
steps to reproduce.

Fixes are released in the newest beta and stable builds. Older builds are not
patched; the in-app updater offers the fixed release.

Release packages are signed: the macOS application with a Developer ID and
notarized, and every package is listed with its size and SHA-256 digest in the
signed release index (`release/metadata.json`), which the application and the
website verify with the public key `release/northspline-release-ed25519.pub`.
