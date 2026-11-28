//! Reaching a helper: the installed OpenSSH
//! client with the fixed launch, the bundled helpers and their installation.

use super::channel::{Cancel, Channel};
use super::model::{Failure, HelperArtifact, HelperTarget, Phase, RemoteError};
use super::process::{ProcessEvent, RemoteProcess};
use super::protocol::is_valid_build_id;
use super::ssh;
use crate::rt;
use futures::StreamExt;
use gitlama_application::wire::contract::RemoteCapability;
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration;

/// How long an installation may take, including the upload.
pub const INSTALL_TIMEOUT: Duration = Duration::from_secs(600);
const INSTALL_OUTPUT_BYTES: usize = 4096;

/// How this application reaches helpers.
enum Transport {
    /// The installed OpenSSH client; the verified executable is kept after a probe.
    Ssh {
        verified: RefCell<Option<PathBuf>>,
        config: Option<PathBuf>,
    },
    /// A locally built helper started directly (development only); the alias is ignored.
    Local(PathBuf),
}

pub struct Connector {
    build_id: Option<String>,
    transport: Transport,
}

impl Connector {
    /// The production connector: OpenSSH, or in development builds the helper named by
    /// `GITLAMA_REMOTE_HELPER`.
    #[must_use]
    pub fn new() -> Self {
        let build_id = gitlama_core::api::remote_helper_build_id();
        let build_id =
            (is_valid_build_id(&build_id) && build_id != "0".repeat(40)).then_some(build_id);
        let development =
            cfg!(debug_assertions) || std::env::var_os("GITLAMA_SCREENSHOT").is_some();
        let local = std::env::var_os("GITLAMA_REMOTE_HELPER")
            .map(PathBuf::from)
            .filter(|path| development && path.is_absolute());
        let transport = match local {
            Some(path) => Transport::Local(path),
            None => Transport::Ssh {
                verified: RefCell::new(None),
                config: None,
            },
        };
        Self {
            build_id,
            transport,
        }
    }

    /// A connector for the SSH qualification lane (`scripts/verify_remote_workspaces.py
    /// --ssh-loopback`): OpenSSH with the fixture's configuration file in place of the user's,
    /// expecting a helper of `build_id`. Production never constructs it.
    #[must_use]
    pub fn qualification(config_file: PathBuf, build_id: String) -> Self {
        Self {
            build_id: is_valid_build_id(&build_id).then_some(build_id),
            transport: Transport::Ssh {
                verified: RefCell::new(None),
                config: Some(config_file),
            },
        }
    }

    /// The build ID a helper must report; `None` when this build has none.
    #[must_use]
    pub fn build_id(&self) -> Option<&str> {
        self.build_id.as_deref()
    }

    /// The helper for `target` bundled with this application, verified against its build,
    /// platform and digest; `None` when this build carries none.
    pub async fn bundled_helper(&self, target: HelperTarget) -> Option<HelperArtifact> {
        if matches!(self.transport, Transport::Local(_)) {
            return None;
        }
        let build_id = self.build_id.clone()?;
        rt::blocking(move || load_bundled_helper(&build_id, target)).await
    }

    async fn ssh_executable(&self) -> Result<PathBuf, Failure> {
        let Transport::Ssh { verified, .. } = &self.transport else {
            return Err(Failure::Unsupported);
        };
        if let Some(known) = verified.borrow().clone() {
            return Ok(known);
        }
        let executable = ssh::find_ssh().ok_or(Failure::SshUnavailable)?;
        let probe = executable.clone();
        let version = rt::blocking(move || ssh::read_version(&probe))
            .await
            .ok_or(Failure::SshUnavailable)?;
        if !ssh::is_supported_openssh(&version) {
            return Err(Failure::SshUnsupported);
        }
        *verified.borrow_mut() = Some(executable.clone());
        Ok(executable)
    }

    /// Starts the transport for `alias` and completes the handshake.
    ///
    /// # Errors
    /// Every failure before a usable channel.
    pub async fn open(
        &self,
        alias: &str,
        capabilities: HashSet<RemoteCapability>,
        cancel: Rc<Cancel>,
        on_phase: &dyn Fn(Phase),
    ) -> Result<Rc<Channel>, RemoteError> {
        let build_id = self.build_id.clone().ok_or(Failure::BuildMismatch)?;
        on_phase(Phase::Connecting);
        let (executable, arguments) = match &self.transport {
            Transport::Ssh { config, .. } => {
                let arguments = ssh::launch_arguments(alias, &build_id, config.as_deref())?;
                (self.ssh_executable().await?, arguments)
            }
            Transport::Local(helper) => (helper.clone(), vec!["--stdio".to_owned()]),
        };
        if cancel.is_canceled() {
            return Err(Failure::Canceled.into());
        }
        let (process, events) =
            RemoteProcess::start(&executable, &arguments, None).map_err(|_| {
                if matches!(self.transport, Transport::Local(_)) {
                    Failure::HelperNotInstalled
                } else {
                    Failure::SshUnavailable
                }
            })?;
        if cancel.is_canceled() {
            process.terminate().await;
            return Err(Failure::Canceled.into());
        }
        on_phase(Phase::Handshaking);
        Channel::connect(process, events, build_id, capabilities, Some(cancel)).await
    }

    /// Copies `artifact` to `alias` through the fixed installation command and verifies it
    /// there. Only an explicit user action (or a host's automatic installation) calls this.
    ///
    /// # Errors
    /// `install…`, `sshConnectionFailed`, `unsupportedPlatform`, `timedOut` or `canceled`.
    pub async fn install_helper(
        &self,
        alias: &str,
        artifact: &HelperArtifact,
        cancel: Rc<Cancel>,
    ) -> Result<(), Failure> {
        if self.build_id.as_deref() != Some(artifact.build_id.as_str()) {
            return Err(Failure::InstallUnavailable);
        }
        let Transport::Ssh { config, .. } = &self.transport else {
            return Err(Failure::InstallUnavailable);
        };
        let arguments = ssh::install_arguments(
            alias,
            &artifact.build_id,
            &artifact.sha256,
            artifact.target,
            config.as_deref(),
        )?;
        let executable = self.ssh_executable().await?;
        run_install(
            &executable,
            &arguments,
            &artifact.bytes,
            cancel,
            INSTALL_TIMEOUT,
        )
        .await
    }
}

impl Default for Connector {
    fn default() -> Self {
        Self::new()
    }
}

/// Runs the fixed installation command and maps its single result line.
async fn run_install(
    executable: &Path,
    arguments: &[String],
    bytes: &[u8],
    cancel: Rc<Cancel>,
    timeout: Duration,
) -> Result<(), Failure> {
    let (process, mut events) =
        RemoteProcess::start(executable, arguments, None).map_err(|_| Failure::SshUnavailable)?;
    const CHUNK: usize = 256 * 1024;
    for chunk in bytes.chunks(CHUNK) {
        if cancel.is_canceled() {
            break;
        }
        process.write(chunk.to_vec());
    }
    process.close_stdin();
    let mut output = Vec::new();
    let mut status = None;
    let mut stdout_done = false;
    let deadline = std::time::Instant::now() + timeout;
    while !(stdout_done && status.is_some()) {
        if cancel.is_canceled() || std::time::Instant::now() >= deadline {
            break;
        }
        // Wakes at least every half second to notice cancel and the deadline.
        let next = rt::timeout(Duration::from_millis(500), events.next()).await;
        match next {
            None => continue,
            Some(None) => break,
            Some(Some(ProcessEvent::Stdout(chunk))) => {
                let room = INSTALL_OUTPUT_BYTES.saturating_sub(output.len());
                output.extend(chunk.iter().take(room));
            }
            Some(Some(ProcessEvent::StdoutEnd)) => stdout_done = true,
            Some(Some(ProcessEvent::Exited(code))) => {
                status = Some(code);
                if !stdout_done {
                    // Give stdout a moment to deliver the result line.
                    stdout_done = true;
                    while let Some(Some(event)) =
                        rt::timeout(Duration::from_secs(2), events.next()).await
                    {
                        match event {
                            ProcessEvent::Stdout(chunk) => {
                                let room = INSTALL_OUTPUT_BYTES.saturating_sub(output.len());
                                output.extend(chunk.iter().take(room));
                            }
                            ProcessEvent::StdoutEnd => break,
                            ProcessEvent::Exited(_) => {}
                        }
                    }
                }
            }
        }
    }
    let Some(status) = status else {
        process.terminate().await;
        return Err(if cancel.is_canceled() {
            Failure::Canceled
        } else {
            Failure::TimedOut
        });
    };
    install_result(&output, status)
}

/// Login scripts may print before the installer; only its last line counts.
fn install_result(output: &[u8], status: Option<i32>) -> Result<(), Failure> {
    let text: String = output.iter().map(|byte| char::from(*byte)).collect();
    let line = text
        .split('\n')
        .map(str::trim)
        .rfind(|line| !line.is_empty())
        .unwrap_or("");
    const PREFIX: &str = "GITLAMA-INSTALL 1 ";
    if status == Some(0) && line == format!("{PREFIX}installed") {
        return Ok(());
    }
    Err(match line.strip_prefix(PREFIX) {
        Some("platform") => Failure::UnsupportedPlatform,
        Some("directory") => Failure::InstallDirectory,
        Some("write") => Failure::InstallWrite,
        Some("digest") => Failure::InstallDigest,
        Some("execute") => Failure::InstallExecute,
        _ if line.is_empty() && status == Some(255) => Failure::SshConnectionFailed,
        _ => Failure::InstallFailed,
    })
}

/// Where release packages place the helper for `target`, relative to the executable's
/// directory.
fn bundle_directory(executable_directory: &Path, target: HelperTarget) -> PathBuf {
    if cfg!(target_os = "macos") {
        executable_directory
            .join("../Resources/remote-helper")
            .join(target.directory())
    } else if cfg!(windows) {
        executable_directory
            .join("remote-helper")
            .join(target.directory())
    } else {
        executable_directory
            .join("lib/remote-helper")
            .join(target.directory())
    }
}

/// Loads the helper bundled next to the running executable and verifies its descriptor. A
/// build from source has no packaged helper and uses the one `scripts/run-dev.sh` placed in
/// the checkout's `build/remote-helper`.
fn load_bundled_helper(build_id: &str, target: HelperTarget) -> Option<HelperArtifact> {
    let executable = std::env::current_exe().ok()?;
    let directory = executable.parent()?;
    if let Some(found) = load_helper(&bundle_directory(directory, target), build_id, target) {
        return Some(found);
    }
    if cfg!(windows) {
        return None;
    }
    // A build from source runs from the checkout's `rust-core/target`.
    let mut current = directory;
    while let Some(parent) = current.parent() {
        if current.file_name().is_some_and(|name| name == "target")
            && parent.file_name().is_some_and(|name| name == "rust-core")
            && let Some(checkout) = parent.parent()
        {
            return load_helper(
                &checkout
                    .join("build/remote-helper")
                    .join(target.directory()),
                build_id,
                target,
            );
        }
        current = parent;
    }
    None
}

fn load_helper(directory: &Path, build_id: &str, target: HelperTarget) -> Option<HelperArtifact> {
    let descriptor = std::fs::read(directory.join("gitlama-remote-helper.json")).ok()?;
    if descriptor.len() > 4096 {
        return None;
    }
    let descriptor: serde_json::Value = serde_json::from_slice(&descriptor).ok()?;
    if descriptor["schema"] != 1
        || descriptor["target"] != target.triple()
        || descriptor["build_id"] != build_id
    {
        return None;
    }
    let path = directory.join("gitlama-remote-helper");
    let length = std::fs::metadata(&path).ok()?.len();
    if length < 1 || length > ssh::INSTALL_LIMIT as u64 {
        return None;
    }
    let bytes = std::fs::read(&path).ok()?;
    let sha256 = super::model::hex(&Sha256::digest(&bytes));
    if descriptor["bytes"] != bytes.len() || descriptor["sha256"] != sha256.as_str() {
        return None;
    }
    Some(HelperArtifact {
        build_id: build_id.to_owned(),
        target,
        sha256,
        bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_last_installer_line_decides() {
        assert_eq!(
            install_result(b"motd\nGITLAMA-INSTALL 1 installed\n", Some(0)),
            Ok(())
        );
        assert_eq!(
            install_result(b"GITLAMA-INSTALL 1 installed\n", Some(3)),
            Err(Failure::InstallFailed)
        );
        assert_eq!(
            install_result(b"GITLAMA-INSTALL 1 digest\n", Some(3)),
            Err(Failure::InstallDigest)
        );
        assert_eq!(
            install_result(b"", Some(255)),
            Err(Failure::SshConnectionFailed)
        );
        assert_eq!(
            install_result(b"noise", Some(255)),
            Err(Failure::InstallFailed)
        );
    }

    #[test]
    fn bundled_helpers_are_verified_against_their_descriptor() {
        let directory = std::env::temp_dir().join(format!(
            "gitlama-helper-{}",
            super::super::model::random_hex32()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let build = "0000000000000000000000000000000000000023";
        let bytes = b"helper".to_vec();
        let digest = super::super::model::hex(&Sha256::digest(&bytes));
        std::fs::write(directory.join("gitlama-remote-helper"), &bytes).unwrap();
        let descriptor = |sha: &str| {
            serde_json::json!({"schema": 1, "build_id": build, "target": "x86_64-unknown-linux-gnu",
                               "sha256": sha, "bytes": bytes.len()})
            .to_string()
        };
        std::fs::write(
            directory.join("gitlama-remote-helper.json"),
            descriptor(&digest),
        )
        .unwrap();
        let artifact = load_helper(&directory, build, HelperTarget::LinuxX86_64).unwrap();
        assert_eq!(artifact.sha256, digest);
        assert!(load_helper(&directory, build, HelperTarget::LinuxArm64).is_none());
        assert!(load_helper(&directory, &"1".repeat(40), HelperTarget::LinuxX86_64).is_none());
        std::fs::write(
            directory.join("gitlama-remote-helper.json"),
            descriptor(&"0".repeat(64)),
        )
        .unwrap();
        assert!(load_helper(&directory, build, HelperTarget::LinuxX86_64).is_none());
        let _ = std::fs::remove_dir_all(directory);
    }
}
