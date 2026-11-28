//! An owned child process speaking the remote protocol over stdin/stdout. Its stdout arrives
//! on the local executor as [`ProcessEvent`]s; stdin is written by a thread of its own, so a
//! large upload never blocks the window. Stderr is drained and discarded: it is never logged,
//! stored or shown.

use futures::channel::mpsc;
use std::io::{Read, Write};
use std::process::{ChildStdin, Command, Stdio};
use std::sync::mpsc as std_mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Grace after closing stdin, and again after the first kill attempt.
pub const TERMINATION_GRACE: Duration = Duration::from_secs(2);
const READ_CHUNK: usize = 64 * 1024;

#[derive(Debug, PartialEq, Eq)]
pub enum ProcessEvent {
    Stdout(Vec<u8>),
    /// Stdout reached its end (or failed).
    StdoutEnd,
    /// The process exited with this status; `None` when killed by a signal.
    Exited(Option<i32>),
}

enum StdinCommand {
    Write(Vec<u8>),
    Close,
}

/// A started child process.
pub struct RemoteProcess {
    pid: u32,
    reaped: Arc<Mutex<bool>>,
    stdin: Mutex<Option<std_mpsc::Sender<StdinCommand>>>,
    exit: Arc<Mutex<Option<Option<i32>>>>,
    exited: Arc<crate::rt::WakeSignal>,
}

impl RemoteProcess {
    /// Starts `executable` without a shell.
    ///
    /// # Errors
    /// The process could not be started.
    pub fn start(
        executable: &std::path::Path,
        arguments: &[String],
        environment: Option<&[(String, String)]>,
    ) -> std::io::Result<(Arc<Self>, mpsc::UnboundedReceiver<ProcessEvent>)> {
        let mut command = Command::new(executable);
        command
            .args(arguments)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(environment) = environment {
            command
                .env_clear()
                .envs(environment.iter().map(|(k, v)| (k, v)));
        }
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt as _;
            // CREATE_NO_WINDOW: no console flashes up for the OpenSSH client.
            command.creation_flags(0x0800_0000);
        }
        let mut child = command.spawn()?;
        let pid = child.id();
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let stdin = child.stdin.take();
        let (sender, receiver) = mpsc::unbounded();
        if let Some(mut stdout) = stdout {
            let sender = sender.clone();
            crate::rt::spawn_thread("remote-stdout", move || {
                let mut buffer = vec![0_u8; READ_CHUNK];
                loop {
                    match stdout.read(&mut buffer) {
                        Ok(0) | Err(_) => break,
                        Ok(count) => {
                            if sender
                                .unbounded_send(ProcessEvent::Stdout(buffer[..count].to_vec()))
                                .is_err()
                            {
                                break;
                            }
                        }
                    }
                }
                let _ = sender.unbounded_send(ProcessEvent::StdoutEnd);
            });
        } else {
            let _ = sender.unbounded_send(ProcessEvent::StdoutEnd);
        }
        if let Some(mut stderr) = stderr {
            crate::rt::spawn_thread("remote-stderr", move || {
                let mut sink = [0_u8; 8192];
                while matches!(stderr.read(&mut sink), Ok(count) if count > 0) {}
            });
        }
        let stdin_sender = stdin.map(|stdin| {
            let (commands, received) = std_mpsc::channel::<StdinCommand>();
            crate::rt::spawn_thread("remote-stdin", move || write_stdin(stdin, &received));
            commands
        });
        let reaped = Arc::new(Mutex::new(false));
        let exit = Arc::new(Mutex::new(None));
        let exited = Arc::new(crate::rt::WakeSignal::new());
        {
            let reaped = Arc::clone(&reaped);
            let exit = Arc::clone(&exit);
            let exited = Arc::clone(&exited);
            // Block in wait() so the thread causes zero idle wakeups while the host is connected.
            crate::rt::spawn_thread("remote-wait", move || {
                let code = child.wait().ok().and_then(|status| status.code());
                if let Ok(mut done) = reaped.lock() {
                    *done = true;
                }
                if let Ok(mut slot) = exit.lock() {
                    *slot = Some(code);
                }
                exited.notify();
                let _ = sender.unbounded_send(ProcessEvent::Exited(code));
            });
        }
        Ok((
            Arc::new(Self {
                pid,
                reaped,
                stdin: Mutex::new(stdin_sender),
                exit,
                exited,
            }),
            receiver,
        ))
    }

    /// Queues protocol bytes for stdin. Ignored after stdin closed or the process exited.
    pub fn write(&self, bytes: Vec<u8>) {
        if let Ok(stdin) = self.stdin.lock()
            && let Some(stdin) = stdin.as_ref()
        {
            let _ = stdin.send(StdinCommand::Write(bytes));
        }
    }

    /// Closes stdin once the queued bytes are written.
    pub fn close_stdin(&self) {
        if let Ok(mut stdin) = self.stdin.lock()
            && let Some(stdin) = stdin.take()
        {
            let _ = stdin.send(StdinCommand::Close);
        }
    }

    /// The exit status once the process exited.
    #[must_use]
    pub fn exit_status(&self) -> Option<Option<i32>> {
        self.exit.lock().ok().and_then(|exit| *exit)
    }

    /// Closes stdin, waits the grace for an exit, then kills the process (its tree on
    /// Windows) and waits again. Idempotent.
    pub async fn terminate(&self) {
        self.close_stdin();
        if self.exited_within(TERMINATION_GRACE).await {
            return;
        }
        if let Ok(reaped) = self.reaped.lock()
            && !*reaped
        {
            #[cfg(windows)]
            {
                if let Some(root) = std::env::var_os("SystemRoot") {
                    let mut taskkill = std::path::PathBuf::from(root);
                    taskkill.push("System32\\taskkill.exe");
                    let _ = Command::new(taskkill)
                        .args(["/T", "/F", "/PID", &self.pid.to_string()])
                        .stdin(Stdio::null())
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn();
                }
            }
            #[cfg(unix)]
            {
                gitlama_core::api::kill_process_id(self.pid);
            }
        }
        if !self.exited_within(TERMINATION_GRACE).await {
            super::note(
                crate::diagnostics::Level::Warning,
                "remote_process_kill_unconfirmed",
                &[],
            );
        }
    }

    async fn exited_within(&self, grace: Duration) -> bool {
        if self.exit_status().is_some() {
            return true;
        }
        let _ = crate::rt::timeout(grace, async {
            while self.exit_status().is_none() {
                if !self.exited.next().await {
                    break;
                }
            }
        })
        .await;
        self.exit_status().is_some()
    }
}

fn write_stdin(mut stdin: ChildStdin, commands: &std_mpsc::Receiver<StdinCommand>) {
    while let Ok(command) = commands.recv() {
        match command {
            StdinCommand::Write(bytes) => {
                if stdin
                    .write_all(&bytes)
                    .and_then(|()| stdin.flush())
                    .is_err()
                {
                    // A closed pipe surfaces through the exit and stdout's end.
                    return;
                }
            }
            StdinCommand::Close => return,
        }
    }
}
