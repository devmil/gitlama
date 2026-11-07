//! `gitlama-remote-helper`: `GitLama`'s headless repository backend, started by the desktop
//! client through SSH for one connection. See docs/remote-workspaces/PROTOCOL.md.
#[cfg(unix)]
mod directory;
#[cfg(unix)]
mod dispatch;
#[cfg(unix)]
mod frame;
#[cfg(unix)]
mod initialize;
#[cfg(unix)]
mod protocol;
#[cfg(unix)]
mod server;
#[cfg(unix)]
mod sessions;
#[cfg(unix)]
mod store;
#[cfg(unix)]
mod writes;

use std::process::ExitCode;

const USAGE: &str = "usage: gitlama-remote-helper --stdio | --version\n";

fn main() -> ExitCode {
    let arguments: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    match arguments
        .iter()
        .map(|argument| argument.to_str())
        .collect::<Vec<_>>()
        .as_slice()
    {
        [Some("--version")] => {
            println!(
                "{{\"buildId\":\"{}\",\"sourceCommit\":\"{}\",\"protocolMajor\":1,\"protocolMinor\":0,\"platform\":\"{}\",\"architecture\":\"{}\"}}",
                gitlama_application::remote_session_policy::BUILD_ID,
                gitlama_application::remote_session_policy::SOURCE_COMMIT,
                std::env::consts::OS,
                std::env::consts::ARCH
            );
            ExitCode::SUCCESS
        }
        [Some("--stdio")] => serve(),
        _ => {
            eprint!("{USAGE}");
            ExitCode::from(2)
        }
    }
}

#[cfg(not(unix))]
fn serve() -> ExitCode {
    eprintln!("gitlama-remote-helper: unsupported platform");
    ExitCode::from(3)
}

#[cfg(unix)]
fn serve() -> ExitCode {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex};

    let Ok((input, output)) = protocol_streams() else {
        return ExitCode::from(4);
    };
    // Every Git child inherits these. Read-only browsing never fetches missing objects or
    // prompts; every session opens with the helper's session policy, which keeps status
    // refreshes out of the user's index.
    std::env::set_var("GIT_NO_LAZY_FETCH", "1");
    std::env::set_var("GIT_TERMINAL_PROMPT", "0");

    let git_version = git_version();
    let git_state = match &git_version {
        None => "missing",
        Some(version) if !supported_git(version) => "unsupported",
        Some(_) => "available",
    };
    let home = std::env::var_os("HOME")
        .map(std::path::PathBuf::from)
        .filter(|home| home.is_absolute());
    let store = home
        .as_deref()
        .and_then(|home| store::Store::open(home).ok());
    let Ok(incarnation) = protocol::random_id() else {
        return ExitCode::from(4);
    };
    let account_uid = rustix::process::geteuid().as_raw();
    let account_name = account_name();
    let writes = store
        .as_ref()
        .and_then(|store| writes::Writes::open(store, home.as_deref()));
    let mut capabilities = vec![
        protocol::Capability::Read,
        protocol::Capability::ListDirectory,
    ];
    if writes.is_some() {
        capabilities.extend(protocol::Capability::WRITES);
    }
    let build_id = gitlama_application::remote_session_policy::BUILD_ID;
    let hello = protocol::hello(&protocol::HelloFacts {
        build_id,
        incarnation: &incarnation,
        git_state,
        git_version: git_version.as_deref(),
        store_id: store.as_ref().map(store::Store::id),
        account_uid,
        account_name: &account_name,
        capabilities: &capabilities,
    });
    let output = Arc::new(Mutex::new(Some(output)));
    let write = |value: &gitlama_application::wire::runtime::Value| {
        let mut guard = server::lock(&output);
        guard.as_mut().is_some_and(|file| {
            frame::write_frame(file, &gitlama_application::wire::runtime::to_bytes(value)).is_ok()
        })
    };
    if !write(&hello) {
        return ExitCode::from(4);
    }

    let clock = frame::FrameClock::new();
    let acknowledged = Arc::new(AtomicBool::new(false));
    spawn_watchdog(
        clock.clone(),
        Arc::clone(&acknowledged),
        Arc::clone(&output),
    );
    let mut input = input;
    let acknowledgement = frame::read_frame(&mut input, frame::MAX_HELLO_BYTES, &clock)
        .ok()
        .and_then(|bytes| {
            gitlama_application::wire::runtime::parse(
                &bytes,
                gitlama_application::wire::runtime::ParseLimits::FRAME,
            )
            .ok()
        })
        .and_then(|value| {
            protocol::acknowledgement(&value, build_id, &incarnation, &capabilities).ok()
        });
    let Some(acknowledgement) = acknowledgement else {
        write(&protocol::fatal("handshakeRejected"));
        return ExitCode::from(2);
    };
    acknowledged.store(true, Ordering::Release);
    let Some(output) = server::lock(&output).take() else {
        return ExitCode::from(4);
    };
    let connection = server::Connection::new(
        protocol::Session {
            nonce: acknowledgement.nonce,
            incarnation,
        },
        acknowledgement.capabilities,
        home.and_then(|home| std::fs::canonicalize(home).ok()),
        store
            .as_ref()
            .map(|store| store.id().to_owned())
            .unwrap_or_default(),
        writes,
    );
    server::serve(&connection, input, output, &clock);
    ExitCode::SUCCESS
}

/// Ends the process when the acknowledgement does not arrive within ten seconds or any frame
/// stays incomplete past its deadline. Neither case does teardown work.
#[cfg(unix)]
fn spawn_watchdog(
    clock: frame::FrameClock,
    acknowledged: std::sync::Arc<std::sync::atomic::AtomicBool>,
    output: std::sync::Arc<std::sync::Mutex<Option<std::fs::File>>>,
) {
    use std::sync::atomic::Ordering;
    use std::time::Duration;
    std::thread::spawn(move || {
        let started = std::time::Instant::now();
        loop {
            std::thread::sleep(Duration::from_millis(200));
            let unacknowledged = !acknowledged.load(Ordering::Acquire)
                && started.elapsed() > Duration::from_secs(10);
            if unacknowledged || clock.expired() {
                if unacknowledged {
                    if let Some(file) = server::lock(&output).as_mut() {
                        let fatal = protocol::fatal("handshakeTimeout");
                        let _ = frame::write_frame(
                            file,
                            &gitlama_application::wire::runtime::to_bytes(&fatal),
                        );
                    }
                }
                std::process::exit(2);
            }
        }
    });
}

/// Moves the protocol to private descriptors. Standard input becomes `/dev/null` and standard
/// output becomes standard error, so no child process or stray write can touch the protocol.
#[cfg(unix)]
fn protocol_streams() -> std::io::Result<(std::fs::File, std::fs::File)> {
    use rustix::fs::{Mode, OFlags};
    let input = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stdin(), 3)?;
    let output = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stdout(), 3)?;
    let null = rustix::fs::open("/dev/null", OFlags::RDONLY | OFlags::CLOEXEC, Mode::empty())?;
    rustix::stdio::dup2_stdin(&null)?;
    rustix::stdio::dup2_stdout(rustix::stdio::stderr())?;
    Ok((std::fs::File::from(input), std::fs::File::from(output)))
}

/// `git --version` through the shared runner, bounded to five seconds and 256 bytes, as
/// `major.minor.patch`.
#[cfg(unix)]
fn git_version() -> Option<String> {
    use gitlama_application::devmil_git::process::{
        ActivityGitRunner, GitProcessCommand, ProcessArgument, SemanticTimeout,
    };
    use gitlama_application::devmil_git::version::GitVersion;
    let command = GitProcessCommand::git("git")
        .arg(ProcessArgument::visible("--version"))
        .output_limit(256)
        .semantic_timeout(
            SemanticTimeout::new(std::time::Duration::from_secs(5), "git version").ok()?,
        );
    let mut result = ActivityGitRunner::run_private(
        command,
        gitlama_application::activity::allocate_activity_id(),
        None,
        &mut |_| {},
    );
    if !matches!(
        result.activity.status,
        gitlama_application::devmil_git::activity::ActivityStatus::Succeeded { .. }
    ) {
        return None;
    }
    let version = GitVersion::parse(&result.stdout.take_bytes())?;
    Some(format!(
        "{}.{}.{}",
        version.major, version.minor, version.patch
    ))
}

#[cfg(unix)]
fn supported_git(version: &str) -> bool {
    let mut parts = version
        .split('.')
        .map(|part| part.parse::<u32>().unwrap_or(0));
    let parsed = (
        parts.next().unwrap_or(0),
        parts.next().unwrap_or(0),
        parts.next().unwrap_or(0),
    );
    parsed >= (2, 39, 0)
}

/// The account's display name, bounded; never part of any authority.
#[cfg(unix)]
fn account_name() -> String {
    ["USER", "LOGNAME"]
        .iter()
        .find_map(|name| std::env::var(name).ok())
        .filter(|name| name.len() <= 128 && !name.chars().any(char::is_control))
        .unwrap_or_default()
}
