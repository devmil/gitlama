# Setting up a remote workspace host

Status: always offered. Open a remote repository from a new tab or with Open Remote Repository.
Only the combinations recorded in [the implementation ledger](IMPLEMENTATION.md) have been checked.

GitLama reaches another computer through your own OpenSSH setup and runs a small helper there.
It never asks for a password or private key and never accepts an unknown host key for you. It
installs its helper on the other computer only when you ask it to. You prepare the host once:

## 1. Make `ssh <alias>` work without prompts

GitLama connects with an alias from your SSH configuration (`~/.ssh/config`), for example:

```
Host devbox
  HostName devbox.example.net
  User alice
```

Check from a terminal that `ssh devbox true` returns without asking for anything:

- The host key must already be in `known_hosts`. Connect once from a terminal and verify the
  fingerprint; GitLama uses `StrictHostKeyChecking=yes` and never adds keys.
- Your key must be usable without a prompt: loaded in your SSH agent, or a key without a
  passphrase. GitLama uses `BatchMode=yes`; password and keyboard-interactive logins are not
  supported.
- Jump hosts and `ProxyCommand` from your configuration are used as they are. Their own host keys
  must be trusted as well.

GitLama disables agent and X11 forwarding, port forwardings, connection sharing and any
`RemoteCommand` for its connections, whatever your configuration says.

## 2. Check the host

The supported hosts are:

- a Linux x86_64 computer with glibc 2.35 or newer, kernel 5.15 or newer and OpenSSH server 8.9
  or newer;
- a 64-bit Arm Linux computer (`uname -m` reports `aarch64`), such as a Raspberry Pi 3, 4 or 5
  with 64-bit Raspberry Pi OS Bookworm or newer, with the same glibc, kernel and OpenSSH floors.
  32-bit Raspberry Pi OS (`armv7l`) is not supported, and neither is a 32-bit system on a 64-bit
  kernel: `uname -m` says `aarch64` there, but the helper cannot run and installation reports
  that it could not run on the host;
- a Mac with Apple silicon or an Intel processor running macOS 13 or newer, with Remote Login
  turned on (System Settings → General → Sharing).

Both need Git 2.39 or newer, a POSIX-compatible login shell (`sh`, `bash`, `zsh`, `dash`) and a
home directory on a local filesystem. On a Mac, GitLama uses a Git from Homebrew
(`/opt/homebrew/bin`) or `/usr/local/bin` when one is installed, and otherwise Apple's, which
needs the Command Line Tools (`xcode-select --install`). Musl-based systems (Alpine),
network-mounted home directories and restricted shells are not supported.

## 3. Install the helper for your GitLama version

Each GitLama version needs one helper version, with one helper per host platform (Linux x86_64,
Linux arm64, macOS on Apple silicon, macOS on Intel), and release packages carry all of them. An
update of GitLama needs a new helper only when the helper changed; otherwise hosts keep the one
they run. **Settings → Remote hosts** shows the helper version this GitLama needs.

When the connection fails with "helper not installed", the host has also reported its platform,
and GitLama offers **Install helper** right there: in the tab that could not connect, when you
reconnect or open a recent remote repository, in the host dialog and in Settings → Remote hosts.
It copies the helper for exactly that platform. GitLama shows the destination, the size and the
SHA-256 of the helper and copies it only after you confirm:

- It uses the same SSH connection and options as a normal connection, so nothing new is trusted.
- The helper goes to `~/.local/lib/gitlama/remote/<helper-id>/gitlama-remote-helper` in your own
  account; the helper ID is the helper version as 40 digits. No administrator rights are used and nothing outside this directory changes.
- A fixed script on the host writes it to a temporary file, refuses symbolic links in the path,
  compares the SHA-256, checks that it runs and reports this helper ID, and only then renames it into
  place. A failed or canceled installation leaves no partial helper behind.
- The host needs `sha256sum` (Linux) or `shasum` (macOS), `head` and a POSIX shell, which the
  supported systems include. A helper for another platform than the host's is refused.

GitLama then connects and reopens the host's tabs. Builds without a bundled helper show the
location instead.

Turn on **Install the helper automatically** for a host (in the confirmation, the host dialog or
Settings → Remote hosts) to skip the question: whenever that host lacks the helper this GitLama
version needs, GitLama copies and verifies it the same way while connecting, once per attempt.
Changing the host's SSH alias or confirming a changed identity turns it off again.

### Builds from source

Builds from source (`flutter run`, debug or release mode) bundle helpers of their own: the build
hook builds them from the checkout into `build/remote-helper/<platform>/` with the stripped
`helper-dev` profile, and **Install helper** offers them like in a release. The application looks
there only when it runs from that `build` directory and carries no packaged helper.

- On Linux the hook builds the Linux x86_64 helper with the Rust toolchain alone, and the Linux
  arm64 helper when `rustup target add aarch64-unknown-linux-gnu` was run and a cross linker
  (`aarch64-linux-gnu-gcc` with its C library) or cargo-zigbuild is installed.
- On a Mac it builds the macOS helper for the Mac's own processor natively, and both Linux
  helpers with cargo-zigbuild, set up once:

  ```sh
  brew install zig
  cargo install --locked cargo-zigbuild
  rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu
  ```

A helper that could not be built is skipped, and `build/remote-helper/build-failure-<platform>.txt`
says why; the application still builds and shows the manual location for that platform. A bundle
of the same helper version built on another computer sharing the checkout is offered as well;
the helper ID, platform and SHA-256 are checked either way. A checkout that changes the helper
raises its version (see "Remote helper compatibility" in `AGENTS.md`), so hosts install the new
helper; other commits share the installed one. Set `GITLAMA_DEV_REMOTE_HELPER=0` to skip the
helper build.

### Manual installation

The release page also lists `gitlama-remote-helper-<version>-<build>-<platform>.tar.gz` for
`linux-x86_64`, `linux-arm64`, `macos-arm64` and `macos-x86_64`, and the signed release metadata records each
SHA-256 and helper ID. On the remote computer, with the archive for its platform:

```sh
build=<helper ID shown by GitLama>
mkdir -p ~/.local/lib/gitlama/remote/"$build"
cd ~/.local/lib/gitlama/remote/"$build"
# Copy the archive here, then compare its SHA-256 with the signed release metadata:
sha256sum gitlama-remote-helper-*.tar.gz   # on a Mac: shasum -a 256 gitlama-remote-helper-*.tar.gz
tar -xzf gitlama-remote-helper-*.tar.gz
chmod 0755 gitlama-remote-helper
./gitlama-remote-helper --version
```

`--version` must report the same `buildId`. A new helper version never replaces an older
helper; each version lives in its own directory, and connections in use keep running their
helper. You may delete directories of helper versions no GitLama you use needs any more.

The helper keeps its identity and the receipts of remote writes in
`~/.local/state/gitlama/remote-helper/`. Do not copy this directory to another computer: a copied
store makes two computers look like one.

## 4. Connect

In GitLama choose **Open Remote Repository…**, add a host with a label and the alias, and
connect. The first connection records the remote account and helper store; if they ever change,
GitLama refuses to attach until you confirm the new identity.

Staging and committing on a host are off until you allow them for that host. Allowed writes are
recorded on this computer before they are sent, and every outcome is checked against the
helper's receipt after a lost connection. GitLama never resends a write whose outcome is
unknown.

## Troubleshooting

| Message | What to check |
| --- | --- |
| SSH is not installed or too old | Install OpenSSH 8.9 or newer on this computer |
| Could not connect | `ssh <alias> true` in a terminal: host key, agent, network |
| Helper not installed | Install helper, or step 3 with the helper ID GitLama shows |
| Helper could not run on the host | A `noexec` home or a glibc older than 2.35 |
| Helper arrived damaged | A login script that reads standard input; try again |
| Unsupported platform | The host is not Linux x86_64 or arm64, nor macOS on Apple silicon or Intel (32-bit Raspberry Pi OS included) |
| Could not start the helper | Shell start-up files that print text, a `noexec` home, a missing glibc |
| Git missing or too old | Install Git 2.39 or newer on the host; on a Mac, the Command Line Tools or Homebrew Git |
| Helper store unavailable | `~/.local/state/gitlama/remote-helper` must be a real directory you own |
| Host identity changed | The account or helper store differs; confirm only if you expect it |

## Hosting accounts for repositories on another computer

GitLama uses the hosting accounts configured on this computer for remote
repositories too. Add an account in **Settings → Hosting accounts**. The remote
repository's Git remote URL selects the provider repository; use
**Settings → Repository link** to choose an account or override the mapping
when automatic matching is ambiguous (for example, an SSH hostname alias).
Bindings distinguish the remote host/account and repository path from local
paths and paths on other hosts.

Pull requests, issues, checks and reviews are requested directly from this
computer, using the existing provider capabilities and review authorization.
Opening the create-pull-request page opens this computer's browser; it does not
submit a pull request. These provider actions can use already received metadata
while SSH is disconnected. Checkout still changes the remote repository and
requires a live connection with changes allowed and refs support.

The provider must be reachable from this computer and the local hosting account
must have access. Credentials installed only on the remote host are not used;
GitLama does not tunnel provider requests or copy credentials between machines.
This feature needs no helper update.
