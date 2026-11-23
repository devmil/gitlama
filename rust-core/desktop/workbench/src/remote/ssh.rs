//! The OpenSSH transport's fixed command lines (PROTOCOL.md, launch and installation): the
//! options, the launch and installation scripts, the version probe and the client lookup.
//! No user input except a validated alias ever becomes part of a command.

use super::model::{Failure, HelperTarget, is_valid_alias};
use super::protocol::is_valid_build_id;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// The oldest supported OpenSSH client (8.9 handles `SessionType` and
/// `ForkAfterAuthentication`).
pub const MINIMUM_OPENSSH: (u32, u32) = (8, 9);
const VERSION_PROBE_TIMEOUT: Duration = Duration::from_secs(5);
const VERSION_PROBE_BYTES: usize = 4096;
/// The largest helper the installation accepts.
pub const INSTALL_LIMIT: usize = 128 * 1024 * 1024;

/// The fixed SSH options of every remote connection, in order.
pub const FIXED_ARGUMENTS: &[&str] = &[
    "-T",
    "-o",
    "RequestTTY=no",
    "-o",
    "StdinNull=no",
    "-o",
    "BatchMode=yes",
    "-o",
    "StrictHostKeyChecking=yes",
    "-o",
    "ForwardAgent=no",
    "-o",
    "ForwardX11=no",
    "-o",
    "ClearAllForwardings=yes",
    "-o",
    "GSSAPIDelegateCredentials=no",
    "-o",
    "ControlMaster=no",
    "-o",
    "ControlPath=none",
    "-o",
    "ForkAfterAuthentication=no",
    "-o",
    "RemoteCommand=none",
    "-o",
    "SessionType=default",
    "-o",
    "PermitLocalCommand=no",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "ConnectionAttempts=1",
    "-o",
    "ServerAliveInterval=15",
    "-o",
    "ServerAliveCountMax=3",
];

fn supported_hosts() -> String {
    HelperTarget::ALL
        .iter()
        .map(|target| target.host())
        .collect::<Vec<_>>()
        .join("|")
}

/// The fixed launch string for POSIX shells, including macOS's zsh. Its only variable part is
/// the validated build ID.
///
/// # Panics
/// Never for a valid build ID; callers validate it.
#[must_use]
pub fn launch_command(build_id: &str) -> String {
    assert!(is_valid_build_id(build_id), "not a build ID");
    format!(
        "h=\"$HOME/.local/lib/gitlama/remote/{build_id}/gitlama-remote-helper\"; \
         p=\"$(uname -s)/$(uname -m)\"; \
         case \"$p\" in {hosts}) ;; \
         *) printf 'GITLAMA-BOOTSTRAP 1 platform\\n'; exit 3;; esac; \
         case \"$p\" in Darwin/*) for d in /usr/local/bin /opt/homebrew/bin; do \
         [ ! -x \"$d/git\" ] || PATH=\"$d:$PATH\"; done; export PATH;; esac; \
         [ -x \"$h\" ] || \
         {{ printf 'GITLAMA-BOOTSTRAP 1 missing %s\\n' \"$p\"; exit 3; }}; \
         exec \"$h\" --stdio",
        hosts = supported_hosts(),
    )
}

/// The fixed POSIX installation command; see PROTOCOL.md, installation.
///
/// # Panics
/// Never for a valid build ID and digest; callers validate them.
#[must_use]
pub fn install_command(build_id: &str, sha256: &str, target: HelperTarget) -> String {
    assert!(is_valid_build_id(build_id), "not a build ID");
    assert!(super::protocol::is_lower_hex(sha256, 64), "not a digest");
    let fail = |result: &str| format!("{{ printf 'GITLAMA-INSTALL 1 {result}\\n'; exit 3; }}");
    let limit = INSTALL_LIMIT;
    [
        "umask 077".to_owned(),
        format!("b={build_id}"),
        format!("s={sha256}"),
        format!("[ \"$(uname -s)/$(uname -m)\" = {} ] || {}", target.host(), fail("platform")),
        format!(
            "{{ command -v sha256sum || command -v shasum; }} >/dev/null 2>&1 || {}",
            fail("tools")
        ),
        "r=\"$HOME/.local/lib/gitlama\"".to_owned(),
        "d=\"$r/remote/$b\"".to_owned(),
        format!(
            "for p in \"$r\" \"$r/remote\" \"$d\" \"$d/gitlama-remote-helper\"; do [ ! -L \"$p\" ] || {}; done",
            fail("directory")
        ),
        format!(
            "mkdir -p \"$d\" && chmod 700 \"$r\" \"$r/remote\" \"$d\" || {}",
            fail("directory")
        ),
        "t=\"$d/.gitlama-remote-helper.$$\"".to_owned(),
        "trap 'rm -f \"$t\"' EXIT".to_owned(),
        format!("head -c {} > \"$t\" || {}", limit + 1, fail("write")),
        format!(
            "[ \"$(wc -c < \"$t\" | tr -d \" \")\" -le {limit} ] || {}",
            fail("write")
        ),
        "if command -v sha256sum >/dev/null 2>&1; then v=\"$(sha256sum < \"$t\" | cut -c1-64)\"; \
         else v=\"$(shasum -a 256 < \"$t\" | cut -c1-64)\"; fi"
            .to_owned(),
        format!("[ \"$v\" = \"$s\" ] || {}", fail("digest")),
        format!("chmod 700 \"$t\" || {}", fail("execute")),
        format!(
            "\"$t\" --version 2>/dev/null | grep -F -q \"\\\"buildId\\\":\\\"$b\\\"\" || {}",
            fail("execute")
        ),
        format!("mv -f \"$t\" \"$d/gitlama-remote-helper\" || {}", fail("write")),
        "printf 'GITLAMA-INSTALL 1 installed\\n'".to_owned(),
    ]
    .join("; ")
}

fn base_arguments(alias: &str, config_file: Option<&Path>) -> Result<Vec<String>, Failure> {
    if !is_valid_alias(alias) {
        return Err(Failure::Unsupported);
    }
    let mut arguments = Vec::new();
    if let Some(config) = config_file {
        arguments.push("-F".to_owned());
        arguments.push(config.display().to_string());
    }
    arguments.extend(FIXED_ARGUMENTS.iter().map(|value| (*value).to_owned()));
    arguments.push("--".to_owned());
    arguments.push(alias.to_owned());
    Ok(arguments)
}

/// The complete `ssh` argument array that launches the helper on `alias`. `config_file`
/// replaces the user's SSH configuration; only qualification fixtures pass it.
///
/// # Errors
/// `unsupported` for an alias that is not a host or `user@host`.
pub fn launch_arguments(
    alias: &str,
    build_id: &str,
    config_file: Option<&Path>,
) -> Result<Vec<String>, Failure> {
    let mut arguments = base_arguments(alias, config_file)?;
    arguments.push(launch_command(build_id));
    Ok(arguments)
}

/// The `ssh` argument array that installs a helper on `alias`.
///
/// # Errors
/// `unsupported` for an invalid alias.
pub fn install_arguments(
    alias: &str,
    build_id: &str,
    sha256: &str,
    target: HelperTarget,
    config_file: Option<&Path>,
) -> Result<Vec<String>, Failure> {
    let mut arguments = base_arguments(alias, config_file)?;
    arguments.push(install_command(build_id, sha256, target));
    Ok(arguments)
}

/// Parses `OpenSSH_<major>.<minor>` from `ssh -V` output.
#[must_use]
pub fn parse_openssh_version(text: &str) -> Option<(u32, u32)> {
    let start = text.find("OpenSSH_")? + "OpenSSH_".len();
    let rest = text[start..]
        .strip_prefix("for_Windows_")
        .unwrap_or(&text[start..]);
    let major_end = rest.find(|c: char| !c.is_ascii_digit())?;
    let major = rest[..major_end].parse().ok()?;
    let rest = rest[major_end..].strip_prefix('.')?;
    let minor_end = rest
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(rest.len());
    if major_end > 4 || minor_end == 0 || minor_end > 4 {
        return None;
    }
    Some((major, rest[..minor_end].parse().ok()?))
}

/// Whether `ssh -V` output names a supported OpenSSH client.
#[must_use]
pub fn is_supported_openssh(text: &str) -> bool {
    parse_openssh_version(text).is_some_and(|version| version >= MINIMUM_OPENSSH)
}

/// Finds the installed OpenSSH client. Never searches the current directory or relative
/// `PATH` entries.
#[must_use]
pub fn resolve_executable(
    windows: bool,
    environment: &dyn Fn(&str) -> Option<String>,
    current_directory: &str,
    is_file: &dyn Fn(&str) -> bool,
) -> Option<String> {
    let mut candidates = Vec::new();
    if windows {
        let absolute = |path: &str| {
            let bytes = path.as_bytes();
            bytes.len() >= 3
                && bytes[0].is_ascii_alphabetic()
                && bytes[1] == b':'
                && bytes[2] == b'\\'
        };
        if let Some(root) = environment("SystemRoot").or_else(|| environment("SYSTEMROOT"))
            && absolute(&root)
        {
            candidates.push(format!(
                "{}\\System32\\OpenSSH\\ssh.exe",
                root.trim_end_matches('\\')
            ));
        }
        let current = current_directory.trim_end_matches('\\').to_lowercase();
        let path = environment("Path")
            .or_else(|| environment("PATH"))
            .unwrap_or_default();
        for entry in path.split(';') {
            if !absolute(entry) || entry.contains('"') {
                continue;
            }
            let directory = entry.trim_end_matches('\\');
            if directory.to_lowercase() == current {
                continue;
            }
            candidates.push(format!("{directory}\\ssh.exe"));
        }
    } else {
        candidates.push("/usr/bin/ssh".to_owned());
        let trim = |path: &str| {
            let trimmed = path.trim_end_matches('/');
            if trimmed.is_empty() {
                "/".to_owned()
            } else {
                trimmed.to_owned()
            }
        };
        let current = trim(current_directory);
        for entry in environment("PATH").unwrap_or_default().split(':') {
            if !entry.starts_with('/') {
                continue;
            }
            let directory = trim(entry);
            if directory == current {
                continue;
            }
            candidates.push(if directory == "/" {
                "/ssh".to_owned()
            } else {
                format!("{directory}/ssh")
            });
        }
    }
    candidates.into_iter().find(|candidate| is_file(candidate))
}

/// This computer's OpenSSH client.
#[must_use]
pub fn find_ssh() -> Option<PathBuf> {
    let current = std::env::current_dir()
        .map(|path| path.display().to_string())
        .unwrap_or_default();
    resolve_executable(
        cfg!(windows),
        &|name| std::env::var(name).ok(),
        &current,
        &|path| Path::new(path).is_file(),
    )
    .map(PathBuf::from)
}

/// Runs `<executable> -V` without a shell, keeps the first 4096 bytes of stderr and kills the
/// probe after five seconds. Blocking: call it on the blocking pool.
#[must_use]
pub fn read_version(executable: &Path) -> Option<String> {
    let mut child = Command::new(executable)
        .arg("-V")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;
    let mut stderr = child.stderr.take()?;
    let reader = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = (&mut stderr)
            .take(VERSION_PROBE_BYTES as u64)
            .read_to_end(&mut bytes);
        bytes
    });
    let deadline = Instant::now() + VERSION_PROBE_TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
    let bytes = reader.join().ok()?;
    Some(bytes.iter().map(|byte| char::from(*byte)).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    const BUILD: &str = "0000000000000000000000000000000000000023";

    #[test]
    fn launch_runs_only_the_fixed_script() {
        let arguments = launch_arguments("alice@build", BUILD, None).unwrap();
        assert_eq!(arguments[0], "-T");
        assert_eq!(arguments[arguments.len() - 4], "ServerAliveCountMax=3");
        let documented = std::fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../docs/remote-workspaces/PROTOCOL.md"
        ))
        .unwrap();
        assert!(
            documented.contains(&launch_command(BUILD).replace(BUILD, "<build-id>")),
            "the launch differs from PROTOCOL.md"
        );
        assert_eq!(arguments[arguments.len() - 2], "alice@build");
        let script = arguments.last().unwrap();
        assert!(script.starts_with(&format!("h=\"$HOME/.local/lib/gitlama/remote/{BUILD}/")));
        assert!(script.contains("Linux/x86_64|Linux/aarch64|Darwin/arm64|Darwin/x86_64)"));
        assert!(script.ends_with("exec \"$h\" --stdio"));
        assert_eq!(
            launch_arguments("-oProxyCommand=x", BUILD, None),
            Err(Failure::Unsupported)
        );
    }

    #[test]
    fn install_script_checks_platform_digest_and_build() {
        let digest = "a".repeat(64);
        let script = install_command(BUILD, &digest, HelperTarget::MacosArm64);
        assert!(
            script.contains(
                "= Darwin/arm64 ] || { printf 'GITLAMA-INSTALL 1 platform\\n'; exit 3; }"
            )
        );
        assert!(script.contains(&format!("head -c {} >", INSTALL_LIMIT + 1)));
        assert!(script.contains("grep -F -q \"\\\"buildId\\\":\\\"$b\\\"\""));
        assert!(script.ends_with("printf 'GITLAMA-INSTALL 1 installed\\n'"));
    }

    #[test]
    fn openssh_versions_are_parsed() {
        assert_eq!(parse_openssh_version("OpenSSH_9.6p1 Ubuntu"), Some((9, 6)));
        assert_eq!(
            parse_openssh_version("OpenSSH_for_Windows_8.9p1"),
            Some((8, 9))
        );
        assert!(is_supported_openssh("OpenSSH_8.9p1"));
        assert!(!is_supported_openssh("OpenSSH_8.8p1"));
        assert!(!is_supported_openssh("Dropbear"));
    }

    #[test]
    fn the_client_is_never_found_in_relative_or_current_directories() {
        let environment =
            |name: &str| (name == "PATH").then(|| "bin:/work/:/opt/ssh/bin".to_owned());
        let found =
            resolve_executable(false, &environment, "/work", &|path| path != "/usr/bin/ssh");
        assert_eq!(found.as_deref(), Some("/opt/ssh/bin/ssh"));
        let windows = |name: &str| match name {
            "SystemRoot" => Some("C:\\Windows".to_owned()),
            "Path" => Some(".;C:\\Tools\\".to_owned()),
            _ => None,
        };
        let found = resolve_executable(true, &windows, "C:\\Work", &|path| {
            path.starts_with("C:\\Tools")
        });
        assert_eq!(found.as_deref(), Some("C:\\Tools\\ssh.exe"));
    }
}
