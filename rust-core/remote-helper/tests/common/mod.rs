//! A minimal protocol client and fixture tooling for driving the real helper binary.
#![allow(dead_code)]
use gitlama_application::wire::runtime::{self as w, Map, ParseLimits, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::time::{Duration, Instant};

pub const HELPER: &str = env!("CARGO_BIN_EXE_gitlama-remote-helper");

pub struct Root(pub PathBuf);

impl Root {
    pub fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "gitlama-helper-it-{name}-{}-{}",
            std::process::id(),
            Instant::now().elapsed().as_nanos() ^ u128::from(rand_u64())
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(std::fs::canonicalize(path).unwrap())
    }
}

impl Drop for Root {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn rand_u64() -> u64 {
    let mut bytes = [0_u8; 8];
    getrandom::fill(&mut bytes).unwrap();
    u64::from_le_bytes(bytes)
}

pub fn git(directory: &Path, args: &[&str]) -> String {
    let output = Command::new("git")
        .args([
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "init.defaultBranch=main",
        ])
        .args(args)
        .current_dir(directory)
        .env("GIT_AUTHOR_DATE", "2026-01-01T00:00:00Z")
        .env("GIT_COMMITTER_DATE", "2026-01-01T00:00:00Z")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).trim().to_owned()
}

/// A repository with two commits, a staged change and an unstaged change.
pub fn ordinary_repository(parent: &Path) -> PathBuf {
    let repository = parent.join("ordinary");
    std::fs::create_dir_all(&repository).unwrap();
    git(&repository, &["init", "-q"]);
    // The remote environment's own identity, as a commit made on that host would use.
    git(&repository, &["config", "user.name", "Fixture"]);
    git(
        &repository,
        &["config", "user.email", "fixture@example.invalid"],
    );
    git(&repository, &["config", "commit.gpgsign", "false"]);
    std::fs::write(repository.join("README.md"), b"hello\n").unwrap();
    std::fs::write(repository.join("src.txt"), b"one\ntwo\nthree\n").unwrap();
    git(&repository, &["add", "."]);
    git(&repository, &["commit", "-qm", "initial"]);
    std::fs::write(repository.join("src.txt"), b"one\n2\nthree\n").unwrap();
    git(&repository, &["commit", "-qam", "second"]);
    std::fs::write(repository.join("staged.txt"), b"staged\n").unwrap();
    git(&repository, &["add", "staged.txt"]);
    std::fs::write(repository.join("README.md"), b"hello\nunstaged\n").unwrap();
    repository
}

/// How long a test waits for any helper frame before failing instead of hanging.
pub const FRAME_WAIT: Duration = Duration::from_secs(30);

pub struct Helper {
    pub child: Child,
    stdin: Option<ChildStdin>,
    frames: std::sync::mpsc::Receiver<Vec<u8>>,
    pub hello: Value,
    pub nonce: String,
    next_request: u64,
    pub publications: Vec<Value>,
    /// Chunk transactions reassembled so far.
    pub transactions: usize,
    assembling: HashMap<String, Vec<u8>>,
}

fn read_frame(stdout: &mut ChildStdout) -> Option<Vec<u8>> {
    let mut header = [0_u8; 4];
    stdout.read_exact(&mut header).ok()?;
    let length = u32::from_be_bytes(header) as usize;
    assert!(
        length > 0 && length <= 4 * 1024 * 1024,
        "frame length {length}"
    );
    let mut payload = vec![0_u8; length];
    stdout.read_exact(&mut payload).ok()?;
    Some(payload)
}

pub fn write_frame(stdin: &mut ChildStdin, value: &Value) {
    let bytes = w::to_bytes(value);
    stdin
        .write_all(&u32::try_from(bytes.len()).unwrap().to_be_bytes())
        .unwrap();
    stdin.write_all(&bytes).unwrap();
    stdin.flush().unwrap();
}

pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes.iter().fold(String::new(), |mut text, byte| {
        let _ = write!(text, "{byte:02x}");
        text
    })
}

/// Native path units carrying Unix bytes.
pub fn unit_bytes(units: &[u16]) -> Vec<u8> {
    units
        .iter()
        .map(|unit| u8::try_from(*unit).unwrap())
        .collect()
}

pub fn object(pairs: &[(&str, Value)]) -> Value {
    let mut map = Map::new();
    for (key, value) in pairs {
        map.insert((*key).to_owned(), value.clone());
    }
    Value::Object(map)
}

impl Helper {
    pub fn spawn(home: &Path) -> Self {
        Self::spawn_with(home, &[])
    }

    pub fn spawn_with(home: &Path, environment: &[(&str, &str)]) -> Self {
        let mut command = Command::new(HELPER);
        command
            .arg("--stdio")
            .env("HOME", home)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(if std::env::var_os("HELPER_STDERR").is_some() {
                Stdio::inherit()
            } else {
                Stdio::null()
            });
        for (key, value) in environment {
            command.env(key, value);
        }
        let mut child = command.spawn().unwrap();
        let stdin = child.stdin.take();
        let mut stdout = child.stdout.take().unwrap();
        let (sender, frames) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            while let Some(frame) = read_frame(&mut stdout) {
                if sender.send(frame).is_err() {
                    break;
                }
            }
        });
        let hello = w::parse(
            &frames.recv_timeout(FRAME_WAIT).expect("hello"),
            ParseLimits::FRAME,
        )
        .unwrap();
        Self {
            child,
            stdin,
            frames,
            hello,
            nonce: "f".repeat(32),
            next_request: 0,
            publications: Vec::new(),
            transactions: 0,
            assembling: HashMap::new(),
        }
    }

    pub fn incarnation(&self) -> String {
        self.hello["helperIncarnation"].as_str().unwrap().to_owned()
    }

    pub fn acknowledge(&mut self, capabilities: &[&str]) {
        let ack = object(&[
            ("kind", Value::from("helloAck")),
            ("protocolMajor", Value::from(1)),
            ("protocolMinor", Value::from(0)),
            ("buildId", self.hello["buildId"].clone()),
            ("helperIncarnation", self.hello["helperIncarnation"].clone()),
            ("connectionNonce", Value::from(self.nonce.clone())),
            (
                "capabilities",
                Value::Array(capabilities.iter().map(|c| Value::from(*c)).collect()),
            ),
        ]);
        self.send_raw(&ack);
    }

    pub fn send_raw(&mut self, value: &Value) {
        write_frame(self.stdin.as_mut().unwrap(), value);
    }

    pub fn envelope(&mut self, kind: &str, payload: Value) -> u64 {
        self.next_request += 1;
        let envelope = object(&[
            ("protocolMajor", Value::from(1)),
            ("connectionNonce", Value::from(self.nonce.clone())),
            ("helperIncarnation", Value::from(self.incarnation())),
            ("requestId", Value::from(self.next_request.to_string())),
            ("kind", Value::from(kind)),
            ("payload", payload),
        ]);
        self.send_raw(&envelope);
        self.next_request
    }

    pub fn send_call(&mut self, method: &str, arguments: Value) -> u64 {
        self.envelope(
            "call",
            object(&[("method", Value::from(method)), ("args", arguments)]),
        )
    }

    /// The next complete envelope, reassembling chunk transactions. `None` means the helper
    /// closed its output; a helper that stays silent fails the test.
    pub fn next(&mut self) -> Option<Value> {
        loop {
            let frame = match self.frames.recv_timeout(FRAME_WAIT) {
                Ok(frame) => frame,
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return None,
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                    panic!("no helper frame within {FRAME_WAIT:?}")
                }
            };
            let value = w::parse(&frame, ParseLimits::FRAME).unwrap();
            if value.get("kind").and_then(Value::as_str) != Some("chunk") {
                return Some(value);
            }
            let payload = &value["payload"];
            let transaction = payload["transaction"].as_str().unwrap().to_owned();
            let data = w::bytes_d(&payload["data"]).unwrap();
            let buffer = self.assembling.entry(transaction.clone()).or_default();
            buffer.extend(data);
            let index: usize = payload["index"].as_str().unwrap().parse().unwrap();
            let count: usize = payload["count"].as_str().unwrap().parse().unwrap();
            if index + 1 == count {
                let bytes = self.assembling.remove(&transaction).unwrap();
                assert_eq!(
                    bytes.len().to_string(),
                    payload["totalBytes"].as_str().unwrap()
                );
                let digest = hex(&Sha256::digest(&bytes));
                assert_eq!(digest, payload["digest"].as_str().unwrap());
                let inner = w::parse(&bytes, ParseLimits::TRANSACTION).unwrap();
                self.transactions += 1;
                assert_eq!(inner["requestId"], value["requestId"]);
                return Some(inner);
            }
        }
    }

    /// Waits for the result of `request`, keeping publications.
    pub fn result(&mut self, request: u64) -> Value {
        loop {
            let envelope = self.next().expect("connection closed before the result");
            match envelope["kind"].as_str().unwrap() {
                "publication" => self.publications.push(envelope),
                "result" if request_id(&envelope) == Some(request) => {
                    return envelope["payload"].clone();
                }
                "result" | "pong" | "goodbye" => {}
                other => panic!("unexpected {other}"),
            }
        }
    }

    pub fn call(&mut self, method: &str, arguments: Value) -> Value {
        let request = self.send_call(method, arguments);
        self.result(request)
    }

    pub fn ok(&mut self, method: &str, arguments: Value) -> Value {
        let payload = self.call(method, arguments);
        assert!(payload.get("ok").is_some(), "{method} failed: {payload}");
        payload["ok"].clone()
    }

    pub fn error_code(&mut self, method: &str, arguments: Value) -> String {
        let payload = self.call(method, arguments);
        payload["error"]["code"]
            .as_str()
            .unwrap_or_else(|| panic!("{method} did not fail: {payload}"))
            .to_owned()
    }

    pub fn close_stdin(&mut self) {
        self.stdin = None;
    }

    pub fn wait_exit(&mut self, limit: Duration) -> Option<std::process::ExitStatus> {
        let started = Instant::now();
        while started.elapsed() < limit {
            if let Some(status) = self.child.try_wait().unwrap() {
                return Some(status);
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        None
    }

    pub fn open(&mut self, path: &Path, generation: u64) -> Value {
        self.ok(
            "openRepository",
            object(&[
                ("path", w::bytes_e(path.as_os_str().as_encoded_bytes())),
                ("generation", Value::from(generation.to_string())),
                ("expectedBinding", Value::Null),
            ]),
        )
    }
}

impl Drop for Helper {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// An envelope's decimal request identifier.
pub fn request_id(envelope: &Value) -> Option<u64> {
    envelope["requestId"].as_str()?.parse().ok()
}
