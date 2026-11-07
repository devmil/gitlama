//! Child processes the application starts outside Git, such as the SSH transport of a remote
//! workspace.
//!
//! The Dart VM reaps every child of the process (`waitpid(-1)`) while any `dart:io` process
//! runs, so a Git command the core starts at that time loses its exit status and looks failed.
//! Starting these children here keeps every child owned and waited for by Rust.
use crate::frb_generated::StreamSink;
pub use gitlama_contract::child_process::*;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::{Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

struct Entry {
    stdin: Option<Sender<Vec<u8>>>,
    pid: u32,
}

static NEXT_CHILD: AtomicU64 = AtomicU64::new(1);

fn children() -> MutexGuard<'static, HashMap<u64, Entry>> {
    static CHILDREN: OnceLock<Mutex<HashMap<u64, Entry>>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn event(kind: NativeChildEventKind, child_id: u64) -> NativeChildEvent {
    NativeChildEvent {
        kind,
        child_id,
        bytes: Vec::new(),
        exit_code: None,
    }
}

/// The exit code as `dart:io` reports it.
fn exit_code(status: std::process::ExitStatus) -> i32 {
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            return -signal;
        }
    }
    status.code().unwrap_or(-1)
}

fn command(
    executable: &str,
    arguments: &[String],
    environment: &[NativeEnvironmentVariable],
) -> Command {
    let mut command = Command::new(executable);
    command.args(arguments);
    for variable in environment {
        command.env(&variable.name, &variable.value);
    }
    command
}

/// Starts `executable` without a shell and reports its life on `sink`: `Started` (or
/// `StartFailed`), then `Stdout` chunks, `StdoutClosed` and `Exited`. Standard error is drained
/// and discarded.
pub fn start(
    executable: String,
    arguments: Vec<String>,
    environment: Vec<NativeEnvironmentVariable>,
    sink: StreamSink<NativeChildEvent>,
) {
    let mut child = match command(&executable, &arguments, &environment)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => {
            let _ = sink.add(event(NativeChildEventKind::StartFailed, 0));
            return;
        }
    };
    let id = NEXT_CHILD.fetch_add(1, Ordering::Relaxed);
    let (stdin_sender, stdin_receiver) = mpsc::channel::<Vec<u8>>();
    if let Some(mut stdin) = child.stdin.take() {
        // Writes keep their order and never block the caller.
        std::thread::spawn(move || {
            for chunk in stdin_receiver {
                if stdin
                    .write_all(&chunk)
                    .and_then(|()| stdin.flush())
                    .is_err()
                {
                    break;
                }
            }
        });
    }
    if let Some(mut stderr) = child.stderr.take() {
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 16 * 1024];
            while matches!(stderr.read(&mut buffer), Ok(read) if read > 0) {}
        });
    }
    children().insert(
        id,
        Entry {
            stdin: Some(stdin_sender),
            pid: child.id(),
        },
    );
    let _ = sink.add(event(NativeChildEventKind::Started, id));
    if let Some(mut stdout) = child.stdout.take() {
        let sink = sink.clone();
        std::thread::spawn(move || {
            let mut buffer = vec![0_u8; 64 * 1024];
            loop {
                match stdout.read(&mut buffer) {
                    Ok(0) | Err(_) => break,
                    Ok(read) => {
                        let mut chunk = event(NativeChildEventKind::Stdout, id);
                        chunk.bytes = buffer[..read].to_vec();
                        if sink.add(chunk).is_err() {
                            break;
                        }
                    }
                }
            }
            let _ = sink.add(event(NativeChildEventKind::StdoutClosed, id));
        });
    }
    // A descendant may keep standard output open after the child exited: the exit is reported
    // on its own.
    std::thread::spawn(move || wait(child, id, &sink));
}

fn wait(mut child: Child, id: u64, sink: &StreamSink<NativeChildEvent>) {
    let code = child.wait().map_or(-1, exit_code);
    children().remove(&id);
    let mut exited = event(NativeChildEventKind::Exited, id);
    exited.exit_code = Some(code);
    let _ = sink.add(exited);
}

/// Queues `bytes` for the child's standard input. False after it closed or the child exited.
pub fn write(child_id: u64, bytes: Vec<u8>) -> bool {
    children()
        .get(&child_id)
        .and_then(|entry| entry.stdin.as_ref())
        .is_some_and(|stdin| stdin.send(bytes).is_ok())
}

/// Closes the child's standard input once the queued bytes are written.
pub fn close_stdin(child_id: u64) {
    if let Some(entry) = children().get_mut(&child_id) {
        entry.stdin = None;
    }
}

/// Sends SIGTERM, or SIGKILL when `kill`, to a running child. False when it already exited.
pub fn signal(child_id: u64, kill: bool) -> bool {
    let Some(pid) = children().get(&child_id).map(|entry| entry.pid) else {
        return false;
    };
    send_signal(pid, kill)
}

#[cfg(unix)]
fn send_signal(pid: u32, kill: bool) -> bool {
    use rustix::process::{kill_process, Pid, Signal};
    let Some(pid) = i32::try_from(pid).ok().and_then(Pid::from_raw) else {
        return false;
    };
    kill_process(pid, if kill { Signal::KILL } else { Signal::TERM }).is_ok()
}

/// Windows keeps `dart:io` processes, which reap only their own children.
#[cfg(not(unix))]
fn send_signal(_pid: u32, _kill: bool) -> bool {
    false
}

/// Runs `executable` to completion without a shell and keeps up to `maximum_bytes` of its
/// standard error. A child still running after `timeout_ms` is killed.
pub fn run_capture(
    executable: String,
    arguments: Vec<String>,
    timeout_ms: u32,
    maximum_bytes: u32,
) -> NativeCapturedProcess {
    let Ok(mut child) = command(&executable, &arguments, &[])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
    else {
        return NativeCapturedProcess {
            started: false,
            timed_out: false,
            exit_code: None,
            stderr: Vec::new(),
        };
    };
    let limit = maximum_bytes as usize;
    let reader = child.stderr.take().map(|mut stderr| {
        std::thread::spawn(move || {
            let mut kept = Vec::new();
            let mut buffer = [0_u8; 4096];
            while let Ok(read) = stderr.read(&mut buffer) {
                if read == 0 {
                    break;
                }
                let room = limit.saturating_sub(kept.len());
                kept.extend_from_slice(&buffer[..read.min(room)]);
            }
            kept
        })
    });
    let deadline = Instant::now() + Duration::from_millis(u64::from(timeout_ms));
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                break None;
            }
        }
    };
    let stderr = reader
        .and_then(|reader| reader.join().ok())
        .unwrap_or_default();
    NativeCapturedProcess {
        started: true,
        timed_out: status.is_none(),
        exit_code: status.map(exit_code),
        stderr,
    }
}
