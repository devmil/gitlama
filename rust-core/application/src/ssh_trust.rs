//! SSH host trust: probing a host key for the user to confirm, recording the confirmed key
//! and the strict SSH wrapper that only trusts recorded keys.
//! Application-owned clone attempts around the shared process and validation contracts.

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::dto::NativeCloneFailureKind;
use crate::dto::NativeHostKeyChallenge;
use devmil_git::activity::ActivityStatus;
use devmil_git::auth::{key_algorithm, parse_fingerprint, select_key_line, ssh_endpoint};
use devmil_git::clone::CloneSource;
use devmil_git::process::ActivityGitRunner;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Mutex, OnceLock};
pub(crate) const HOST_KEY_OUTPUT_LIMIT: usize = devmil_git::auth::SSH_HOST_KEY_OUTPUT_BYTES;
pub(crate) const KNOWN_HOSTS_LIMIT: usize = 1024 * 1024;

#[derive(Clone)]
pub(crate) struct PendingHostKey {
    pub(crate) challenge: NativeHostKeyChallenge,
    pub(crate) key_line: Vec<u8>,
}
pub(crate) static NEXT_HOST_CHALLENGE: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(1);
pub(crate) static KNOWN_HOSTS_WRITE: OnceLock<Mutex<()>> = OnceLock::new();

pub(crate) fn probe_host_key(
    source: &CloneSource,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    activity: &ActivityStore,
) -> Result<PendingHostKey, NativeCloneFailureKind> {
    probe_host_key_with_executables(
        source,
        cancellation,
        activity,
        std::ffi::OsStr::new("ssh-keyscan"),
        std::ffi::OsStr::new("ssh-keygen"),
    )
}

pub(crate) fn probe_host_key_with_executables(
    source: &CloneSource,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    activity: &ActivityStore,
    keyscan: &std::ffi::OsStr,
    keygen: &std::ffi::OsStr,
) -> Result<PendingHostKey, NativeCloneFailureKind> {
    let endpoint =
        ssh_endpoint(source, 253).map_err(|_| NativeCloneFailureKind::HostKeyProbeFailed)?;
    let scan = run_host_tool(
        keyscan,
        devmil_git::auth::keyscan_arguments(&endpoint, 5),
        Vec::new(),
        cancellation,
        activity,
    );
    if !matches!(scan.activity.status, ActivityStatus::Succeeded { .. }) {
        return Err(NativeCloneFailureKind::HostKeyProbeFailed);
    }
    let key_line = match select_key_line(&scan.stdout.bytes, &endpoint, HOST_KEY_OUTPUT_LIMIT) {
        Ok(line) => line,
        Err(_) => return Err(NativeCloneFailureKind::HostKeyProbeFailed),
    };
    let algorithm = match key_algorithm(&key_line, 64, HOST_KEY_OUTPUT_LIMIT) {
        Ok(algorithm) => algorithm,
        Err(_) => return Err(NativeCloneFailureKind::HostKeyProbeFailed),
    };
    let fingerprint_result = run_host_tool(
        keygen,
        devmil_git::auth::fingerprint_arguments(),
        devmil_git::auth::fingerprint_input(&key_line),
        cancellation,
        activity,
    );
    if !matches!(
        fingerprint_result.activity.status,
        ActivityStatus::Succeeded { .. }
    ) {
        return Err(NativeCloneFailureKind::HostKeyProbeFailed);
    }
    let fingerprint = match parse_fingerprint(&fingerprint_result.stdout.bytes, 256) {
        Ok(fingerprint) => fingerprint,
        Err(_) => return Err(NativeCloneFailureKind::HostKeyProbeFailed),
    };
    let challenge_id =
        match NEXT_HOST_CHALLENGE.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
            value.checked_add(1)
        }) {
            Ok(value) if value != 0 => value,
            _ => return Err(NativeCloneFailureKind::HostKeyProbeFailed),
        };
    if !valid_sha256_fingerprint(&fingerprint) {
        return Err(NativeCloneFailureKind::HostKeyProbeFailed);
    }
    let challenge = NativeHostKeyChallenge {
        challenge_id,
        host: endpoint.host,
        port: endpoint.port,
        algorithm,
        fingerprint,
    };
    Ok(PendingHostKey {
        challenge,
        key_line,
    })
}

pub(crate) fn trust_host_key(pending: &PendingHostKey) -> Result<PathBuf, NativeCloneFailureKind> {
    let wrapper = ensure_strict_ssh_wrapper()?;
    append_known_host_atomically(&pending.key_line)?;
    Ok(wrapper)
}

pub(crate) fn run_host_tool<I, S>(
    executable: &std::ffi::OsStr,
    arguments: I,
    stdin: Vec<u8>,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    activity: &ActivityStore,
) -> devmil_git::process::PrivateActivityResult
where
    I: IntoIterator<Item = S>,
    S: Into<std::ffi::OsString>,
{
    let command = devmil_git::auth::ssh_host_key_probe_command(executable, arguments, stdin);
    let activity_sink = activity.sink();
    let mut sink = move |event| activity_sink(event);
    ActivityGitRunner::run_private(
        command,
        allocate_activity_id(),
        Some(cancellation),
        &mut sink,
    )
}

pub(crate) fn authentication_paths() -> Result<(PathBuf, PathBuf), NativeCloneFailureKind> {
    let settings = crate::storage::settings_default_path();
    let settings = settings
        .path
        .map(PathBuf::from)
        .ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?;
    let root = settings
        .parent()
        .ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?
        .join("authentication");
    Ok((root.join("known_hosts"), root.join("gitlama-ssh")))
}

#[cfg(unix)]
pub(crate) fn ensure_strict_ssh_wrapper() -> Result<PathBuf, NativeCloneFailureKind> {
    let (known_hosts, wrapper) = authentication_paths()?;
    let parent = wrapper
        .parent()
        .ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?;
    let ssh = resolve_executable("ssh").ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?;
    let program = strict_ssh_wrapper_program(&ssh, &known_hosts);
    let name = wrapper
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?;
    crate::private_store::PrivateDir::application(parent)
        .and_then(|store| store.replace_executable(name, program.as_bytes()))
        .map_err(|_| NativeCloneFailureKind::HostKeyWriteFailed)?;
    Ok(wrapper)
}

#[cfg(unix)]
pub(crate) fn strict_ssh_wrapper_program(ssh: &Path, known_hosts: &Path) -> String {
    format!(
        "#!/bin/sh\nprevious=\nfor argument do\n  if [ \"$previous\" = -o ]; then\n    case \"$argument\" in StrictHostKeyChecking=*|UserKnownHostsFile=*|GlobalKnownHostsFile=*) exit 64 ;; esac\n    previous=\n    continue\n  fi\n  case \"$argument\" in\n    -o) previous=-o ;;\n    -oStrictHostKeyChecking=*|-oUserKnownHostsFile=*|-oGlobalKnownHostsFile=*) exit 64 ;;\n  esac\ndone\nexec {} -o StrictHostKeyChecking=yes -o UserKnownHostsFile={} -o GlobalKnownHostsFile=/dev/null \"$@\"\n",
        shell_quote(ssh),
        shell_quote(known_hosts)
    )
}

#[cfg(not(unix))]
pub(crate) fn ensure_strict_ssh_wrapper() -> Result<PathBuf, NativeCloneFailureKind> {
    Err(NativeCloneFailureKind::HostKeyWriteFailed)
}

#[cfg(unix)]
pub(crate) fn resolve_executable(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH")
        .into_iter()
        .flat_map(|value| std::env::split_paths(&value).collect::<Vec<_>>())
        .map(|directory| directory.join(name))
        .find(|path| path.is_file())
        .and_then(|path| path.canonicalize().ok())
}

#[cfg(unix)]
pub(crate) fn shell_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
}

pub(crate) fn valid_sha256_fingerprint(value: &str) -> bool {
    value.strip_prefix("SHA256:").is_some_and(|digest| {
        digest.len() == 43
            && digest
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'/'))
    })
}

pub(crate) fn append_known_host_atomically(key_line: &[u8]) -> Result<(), NativeCloneFailureKind> {
    let _guard = KNOWN_HOSTS_WRITE
        .get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let (known_hosts, _) = authentication_paths()?;
    append_known_host_at(&known_hosts, key_line)
}

pub(crate) fn append_known_host_at(
    known_hosts: &Path,
    key_line: &[u8],
) -> Result<(), NativeCloneFailureKind> {
    let parent = known_hosts
        .parent()
        .ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?;
    let name = known_hosts
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or(NativeCloneFailureKind::HostKeyWriteFailed)?;
    let store = crate::private_store::PrivateDir::application(parent)
        .map_err(|_| NativeCloneFailureKind::HostKeyWriteFailed)?;
    if key_line.len() > HOST_KEY_OUTPUT_LIMIT {
        return Err(NativeCloneFailureKind::HostKeyWriteFailed);
    }
    let mut existing = store
        .read(name, KNOWN_HOSTS_LIMIT as u64)
        .map_err(|_| NativeCloneFailureKind::HostKeyWriteFailed)?
        .unwrap_or_default();
    if !existing
        .split(|byte| *byte == b'\n')
        .any(|line| line == key_line)
    {
        if !existing.is_empty() && !existing.ends_with(b"\n") {
            existing.push(b'\n');
        }
        existing.extend_from_slice(key_line);
        existing.push(b'\n');
    }
    if existing.len() > KNOWN_HOSTS_LIMIT {
        return Err(NativeCloneFailureKind::HostKeyWriteFailed);
    }
    store
        .replace(name, &existing)
        .map_err(|_| NativeCloneFailureKind::HostKeyWriteFailed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::ScratchDir as Fixture;
    #[cfg(unix)]
    use std::process::Command;

    #[test]
    fn known_hosts_replacement_is_bounded_deduplicated_and_owner_only() {
        let fixture = Fixture::new();
        let path = fixture.0.join("auth").join("known_hosts");
        let first = b"host.test ssh-ed25519 AAAA";
        let second = b"host.test ssh-rsa BBBB";
        append_known_host_at(&path, first).unwrap();
        append_known_host_at(&path, first).unwrap();
        append_known_host_at(&path, second).unwrap();
        assert_eq!(
            std::fs::read(&path).unwrap(),
            b"host.test ssh-ed25519 AAAA\nhost.test ssh-rsa BBBB\n"
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn known_hosts_refuses_symlinks_and_existing_temporary_files() {
        use std::os::unix::fs::symlink;

        let fixture = Fixture::new();
        let directory = fixture.0.join("auth");
        std::fs::create_dir(&directory).unwrap();
        let victim = fixture.0.join("victim");
        std::fs::write(&victim, b"keep").unwrap();
        let linked = directory.join("known_hosts");
        symlink(&victim, &linked).unwrap();
        assert_eq!(
            append_known_host_at(&linked, b"host ssh-ed25519 AAAA"),
            Err(NativeCloneFailureKind::HostKeyWriteFailed)
        );
        assert_eq!(std::fs::read(&victim).unwrap(), b"keep");
        std::fs::remove_file(&linked).unwrap();

        // A planted file beside the store is never written through: replacements use a new,
        // exclusively created temporary.
        let stale = linked.with_extension(format!("tmp.{}.host-11", std::process::id()));
        std::fs::write(&stale, b"stale").unwrap();
        append_known_host_at(&linked, b"host ssh-ed25519 AAAA").unwrap();
        assert_eq!(std::fs::read(&stale).unwrap(), b"stale");
        assert_eq!(std::fs::read(&linked).unwrap(), b"host ssh-ed25519 AAAA\n");
    }

    #[cfg(unix)]
    #[test]
    fn strict_ssh_wrapper_fixes_trust_files_and_rejects_option_overrides() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = Fixture::new();
        let ssh = fixture.0.join("ssh");
        let wrapper = fixture.0.join("wrapper");
        let known_hosts = fixture.0.join("known hosts");
        let output = fixture.0.join("arguments");
        std::fs::write(
            &ssh,
            b"#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$GITLAMA_TEST_OUTPUT\"\n",
        )
        .unwrap();
        std::fs::set_permissions(&ssh, std::fs::Permissions::from_mode(0o700)).unwrap();
        std::fs::write(
            &wrapper,
            strict_ssh_wrapper_program(&ssh, &known_hosts).as_bytes(),
        )
        .unwrap();
        std::fs::set_permissions(&wrapper, std::fs::Permissions::from_mode(0o700)).unwrap();
        let accepted = Command::new(&wrapper)
            .arg("git@example.test")
            .env("GITLAMA_TEST_OUTPUT", &output)
            .status()
            .unwrap();
        assert!(accepted.success());
        let arguments = std::fs::read_to_string(&output).unwrap();
        assert!(arguments.contains("StrictHostKeyChecking=yes"));
        assert!(arguments.contains(&format!("UserKnownHostsFile={}", known_hosts.display())));
        std::fs::remove_file(&output).unwrap();
        let rejected = Command::new(&wrapper)
            .args(["-o", "UserKnownHostsFile=/tmp/hostile", "git@example.test"])
            .env("GITLAMA_TEST_OUTPUT", &output)
            .status()
            .unwrap();
        assert_eq!(rejected.code(), Some(64));
        assert!(!output.exists());
    }
}
