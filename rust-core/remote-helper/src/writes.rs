//! Durable, at-most-once admission of remote writes: staging, commits, ref changes, stashes,
//! transfers and discards; merge, cherry-pick, revert, rebase, restack, conflict resolution and
//! bisect; snapshots, file restores, patches and index-lock removal; worktrees, submodules
//! and Git LFS.
//!
//! A preview issues a one-use token bound to the session, helper incarnation, current admission
//! epoch and the exact intent digest. Execution checks the token and digest, takes the
//! cross-helper lock of the repository's common Git directory, and durably records `Prepared`
//! and then `Started` before Git runs. The terminal receipt records the outcome with evidence.
//! A duplicate operation identifier returns its receipt without executing again; a lookup after
//! a disconnect reads receipts only. There is no exactly-once promise across a crash between a
//! Git effect and its terminal receipt: such an operation is reported as unknown, never replayed.
use crate::server::{lock, Connection};
use crate::sessions::Workspace;
use gitlama_application::dto::{
    NativeCommitExecutionState, NativeCommitRequest, NativeDiscardExecutionState,
    NativeDiscardRequest, NativeRefMutationExecutionState, NativeRefMutationKind,
    NativeRefMutationRequest, NativeStagingExecutionState, NativeStagingRequest,
    NativeStashExecutionState, NativeStashRequest, NativeTransferExecutionState,
    NativeTransferFailureKind, NativeTransferKind, NativeTransferRequest,
};
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Map, ParseLimits, Value};
use rustix::fd::OwnedFd;
use rustix::fs::{self as fs, FlockOperation, Mode, OFlags};
use rustix::io::Errno;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::io::{Read, Write};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const PREVIEW_LIFETIME: Duration = Duration::from_mins(2);
const PREVIEWS_PER_SESSION: usize = 8;
const RECEIPT_BYTES: u64 = 64 * 1024;
const RECEIPTS: usize = 10_000;
/// Rotate the admission epoch and compact resolved receipts above this count.
const COMPACTION_THRESHOLD: usize = 8_000;
const RESOLVED_RETENTION: Duration = Duration::from_hours(30 * 24);
const LOCK_WAIT: Duration = Duration::from_secs(5);
use gitlama_application::wire::contract::{
    COMMIT_DESCRIPTION_BYTES as MESSAGE_BYTES, STAGE_PATHS, STAGE_PATH_BYTES, STAGE_ROWS,
    TEXT_BYTES,
};

type Code = &'static str;

use gitlama_application::wire::contract::{CONFLICT_RESULT_BYTES, PATCH_BYTES};

/// The write families come from the generated contract.
use gitlama_application::wire::contract::{RemoteOutcome, RemoteWriteFamily as Family};

/// What the helper records about a family, beyond the shared contract.
trait FamilyEvidence {
    fn evidence(self) -> &'static [Evidence];
}

impl FamilyEvidence for Family {
    /// What is recorded before and after Git runs. An operation whose every piece of evidence
    /// is provably unchanged did not apply.
    fn evidence(self) -> &'static [Evidence] {
        match self {
            Self::Stage | Self::IndexLock => &[Evidence::Index],
            Self::Commit => &[Evidence::Index, Evidence::Head],
            Self::Refs | Self::Transfer | Self::Extension => &[
                Evidence::Index,
                Evidence::Head,
                Evidence::Refs,
                Evidence::Config,
                Evidence::Worktree,
            ],
            Self::Stash | Self::Snapshot => &[
                Evidence::Index,
                Evidence::Head,
                Evidence::Refs,
                Evidence::Stash,
                Evidence::Worktree,
            ],
            // Discard restores tracked content from the index and removes untracked files; the
            // worktree evidence covers both the content and every untracked file.
            Self::Discard | Self::Conflict | Self::Restore | Self::Patch => {
                &[Evidence::Index, Evidence::Worktree]
            }
            Self::History
            | Self::Rebase
            | Self::Restack
            | Self::Sequencer
            | Self::SnapshotRestore => &[
                Evidence::Index,
                Evidence::Head,
                Evidence::Refs,
                Evidence::Worktree,
            ],
            Self::Bisect => &[Evidence::Head, Evidence::Refs, Evidence::Worktree],
        }
    }
}

#[derive(Clone, Copy)]
enum Evidence {
    Index,
    Head,
    Refs,
    Config,
    Stash,
    Worktree,
}

impl Evidence {
    const fn key(self) -> &'static str {
        match self {
            Self::Index => "index",
            Self::Head => "head",
            Self::Refs => "refs",
            Self::Config => "config",
            Self::Stash => "stash",
            Self::Worktree => "worktree",
        }
    }

    fn collect(self, workspace: &Workspace) -> Value {
        let git_dir = &workspace.git_dir;
        match self {
            Self::Index => index_evidence(git_dir),
            Self::Head => head_evidence(git_dir),
            // Every ref with its target, including symbolic refs and the stash tip.
            Self::Refs => git_digest(
                git_dir,
                &[
                    "for-each-ref",
                    "--format=%(refname)%00%(objectname)%00%(symref)",
                ],
            ),
            // Upstreams and remotes live in the repository's own configuration.
            Self::Config => git_digest(git_dir, &["config", "--local", "--list", "-z"]),
            // Every stash entry, not only the newest.
            Self::Stash => git_digest(git_dir, &["log", "-g", "--format=%H", "refs/stash", "--"]),
            Self::Worktree => worktree_evidence(git_dir, &workspace.worktree),
        }
    }
}

struct Preview {
    session_id: u64,
    generation: u64,
    family: Family,
    epoch: String,
    digest: String,
    request: Value,
    core_token: Option<u64>,
    created: Instant,
    /// The private copy of a patch to apply; removed with the preview.
    patch_file: Option<std::path::PathBuf>,
}

impl Drop for Preview {
    fn drop(&mut self) {
        if let Some(file) = self.patch_file.take() {
            let _ = std::fs::remove_file(file);
        }
    }
}

pub struct Writes {
    root: OwnedFd,
    receipts: OwnedFd,
    locks: OwnedFd,
    /// Where patches to apply are kept between their preview and execution.
    patches: Option<std::path::PathBuf>,
    epoch: Mutex<String>,
    previews: Mutex<HashMap<String, Preview>>,
}

/// A receipt as stored and as reported to the client.
#[derive(Clone)]
struct Receipt {
    operation_id: String,
    epoch: String,
    family: String,
    digest: String,
    binding: String,
    lock_key: String,
    owner: String,
    state: String,
    outcome: Option<String>,
    result_object_id: Option<String>,
    evidence: Map<String, Value>,
    updated_millis: u64,
}

impl Receipt {
    fn to_value(&self) -> Value {
        let mut map = Map::new();
        map.insert("schema".into(), Value::from(1));
        map.insert("operationId".into(), Value::from(self.operation_id.clone()));
        map.insert("epoch".into(), Value::from(self.epoch.clone()));
        map.insert("family".into(), Value::from(self.family.clone()));
        map.insert("digest".into(), Value::from(self.digest.clone()));
        map.insert("binding".into(), Value::from(self.binding.clone()));
        map.insert("lockKey".into(), Value::from(self.lock_key.clone()));
        map.insert("owner".into(), Value::from(self.owner.clone()));
        map.insert("state".into(), Value::from(self.state.clone()));
        map.insert(
            "outcome".into(),
            self.outcome.clone().map_or(Value::Null, Value::from),
        );
        map.insert(
            "resultObjectId".into(),
            self.result_object_id
                .clone()
                .map_or(Value::Null, Value::from),
        );
        map.insert("evidence".into(), Value::Object(self.evidence.clone()));
        map.insert(
            "updatedAt".into(),
            Value::from(self.updated_millis.to_string()),
        );
        Value::Object(map)
    }

    fn parse(bytes: &[u8]) -> Option<Self> {
        let value = w::parse(bytes, ParseLimits::FRAME).ok()?;
        let object = w::object(
            &value,
            "receipt",
            &[
                "schema",
                "operationId",
                "epoch",
                "family",
                "digest",
                "binding",
                "lockKey",
                "owner",
                "state",
                "outcome",
                "resultObjectId",
                "evidence",
                "updatedAt",
            ],
        )
        .ok()?;
        let text = |name: &str| object.field(name).as_str().map(str::to_owned);
        if object.field("schema").as_u64() != Some(1) {
            return None;
        }
        Some(Self {
            operation_id: text("operationId")?,
            epoch: text("epoch")?,
            family: text("family")?,
            digest: text("digest")?,
            binding: text("binding")?,
            lock_key: text("lockKey")?,
            owner: text("owner")?,
            state: text("state")?,
            outcome: text("outcome"),
            result_object_id: text("resultObjectId"),
            evidence: object.field("evidence").as_object()?.clone(),
            updated_millis: w::big_d(object.field("updatedAt")).ok()?,
        })
    }

    /// The protocol's operation object.
    fn operation(&self, outcome_override: Option<&str>) -> Value {
        let mut map = Map::new();
        map.insert("operationId".into(), Value::from(self.operation_id.clone()));
        map.insert("epoch".into(), Value::from(self.epoch.clone()));
        map.insert("state".into(), Value::from(self.state.clone()));
        map.insert(
            "outcome".into(),
            outcome_override
                .map(str::to_owned)
                .or_else(|| self.outcome.clone())
                .map_or(Value::Null, Value::from),
        );
        map.insert(
            "resultObjectId".into(),
            self.result_object_id
                .clone()
                .map_or(Value::Null, Value::from),
        );
        Value::Object(map)
    }
}

fn directory(parent: &OwnedFd, name: &CStr) -> Option<OwnedFd> {
    let flags = OFlags::DIRECTORY | OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC;
    match fs::openat(parent, name, flags, Mode::empty()) {
        Ok(directory) => Some(directory),
        Err(Errno::NOENT) => {
            match fs::mkdirat(parent, name, Mode::from_raw_mode(0o700)) {
                Ok(()) | Err(Errno::EXIST) => {}
                Err(_) => return None,
            }
            crate::store::sync_directory(parent).ok()?;
            fs::openat(parent, name, flags, Mode::empty()).ok()
        }
        Err(_) => None,
    }
}

fn name(text: &str) -> Option<CString> {
    CString::new(text).ok()
}

/// Atomically replaces `file` in `parent`: write and sync a private temporary file, rename it
/// and sync the directory.
fn write_atomic(parent: &OwnedFd, file: &str, bytes: &[u8]) -> bool {
    let Ok(suffix) = crate::protocol::random_id() else {
        return false;
    };
    let (Some(temporary), Some(target)) = (name(&format!(".{file}.{suffix}.tmp")), name(file))
    else {
        return false;
    };
    let Ok(handle) = crate::store::create_at(
        parent,
        &temporary,
        OFlags::WRONLY | OFlags::EXCL | OFlags::NOFOLLOW | OFlags::CLOEXEC,
    ) else {
        return false;
    };
    let mut handle = std::fs::File::from(handle);
    let written = handle
        .write_all(bytes)
        .and_then(|()| handle.sync_all())
        .is_ok();
    drop(handle);
    let installed = written
        && fs::renameat(parent, &temporary, parent, &target).is_ok()
        && crate::store::sync_directory(parent).is_ok();
    if !installed {
        let _ = fs::unlinkat(parent, &temporary, fs::AtFlags::empty());
    }
    installed
}

/// `Ok(None)` when the file does not exist; `Err` when it exists but cannot be read safely.
fn read_bounded(parent: &OwnedFd, file: &str, limit: u64) -> Result<Option<Vec<u8>>, ()> {
    let target = name(file).ok_or(())?;
    let handle = match fs::openat(
        parent,
        &target,
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    ) {
        Ok(handle) => handle,
        Err(Errno::NOENT) => return Ok(None),
        Err(_) => return Err(()),
    };
    let mut bytes = Vec::new();
    std::fs::File::from(handle)
        .take(limit + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| ())?;
    if bytes.len() as u64 > limit {
        return Err(());
    }
    Ok(Some(bytes))
}

/// An exclusive advisory lock held until dropped. Not inherited by children (close-on-exec).
struct Held(#[allow(dead_code)] OwnedFd);

fn lock_file(parent: &OwnedFd, file: &str, wait: Duration) -> Result<Held, Code> {
    let target = name(file).ok_or("internal")?;
    let handle = crate::store::create_at(
        parent,
        &target,
        OFlags::RDWR | OFlags::NOFOLLOW | OFlags::CLOEXEC,
    )
    .map_err(|_| "storeUnavailable")?;
    let started = Instant::now();
    loop {
        match fs::flock(&handle, FlockOperation::NonBlockingLockExclusive) {
            Ok(()) => return Ok(Held(handle)),
            Err(Errno::WOULDBLOCK) if started.elapsed() < wait => {
                std::thread::sleep(Duration::from_millis(20));
            }
            Err(Errno::WOULDBLOCK) => return Err("timedOut"),
            Err(_) => return Err("storeUnavailable"),
        }
    }
}

fn sha256_hex(parts: &[&[u8]]) -> String {
    let mut digest = Sha256::new();
    for part in parts {
        digest.update(u32::try_from(part.len()).unwrap_or(u32::MAX).to_be_bytes());
        digest.update(part);
    }
    crate::protocol::hex(&digest.finalize())
}

/// The intent digest: a domain tag, the workspace binding and the canonical request bytes.
/// Objects encode with sorted keys, so equal requests digest equally.
fn intent_digest(family: Family, binding: &str, request: &Value) -> String {
    sha256_hex(&[
        b"gitlama-remote-intent-v1",
        family.name().as_bytes(),
        binding.as_bytes(),
        &w::to_bytes(request),
    ])
}

/// Runs a fixed read-only Git query against `git_dir` and digests its output. Optional locks
/// stay off, so the query never refreshes the index it describes.
fn git_digest(git_dir: &std::path::Path, arguments: &[&str]) -> Value {
    git_digest_in(git_dir, None, arguments)
}

fn git_digest_in(
    git_dir: &std::path::Path,
    worktree: Option<&std::path::Path>,
    arguments: &[&str],
) -> Value {
    let mut digest = Sha256::new();
    // A missing HEAD (unborn branch) is evidence too: it digests the empty output.
    if run_evidence_query(git_dir, worktree, arguments, &mut |bytes| {
        digest.update(bytes);
    }) {
        Value::from(crate::protocol::hex(&digest.finalize()))
    } else {
        Value::Null
    }
}

/// Evidence output larger than this is not digested; the outcome stays unknown instead.
const EVIDENCE_OUTPUT_BYTES: usize = 256 * 1024 * 1024;

/// Runs a read-only evidence query through the shared runner: process-tree ownership, an idle
/// deadline and bounded output. `observe` receives stdout as it arrives. Completes with whether
/// Git succeeded and every byte was observed.
fn run_evidence_query(
    git_dir: &std::path::Path,
    worktree: Option<&std::path::Path>,
    arguments: &[&str],
    observe: &mut dyn FnMut(&[u8]),
) -> bool {
    use gitlama_application::devmil_git::process::{
        ActivityGitRunner, GitProcessCommand, ProcessArgument, SemanticTimeout,
    };
    let mut command = GitProcessCommand::git("git")
        .arg(ProcessArgument::visible("--git-dir"))
        .arg(ProcessArgument::visible(git_dir.as_os_str()));
    if let Some(worktree) = worktree {
        command = command
            .arg(ProcessArgument::visible("--work-tree"))
            .arg(ProcessArgument::visible(worktree.as_os_str()))
            .current_dir(worktree);
    } else {
        command = command.current_dir(git_dir);
    }
    let mut command = command
        .args(
            arguments
                .iter()
                .map(|argument| ProcessArgument::visible(*argument)),
        )
        .env("GIT_OPTIONAL_LOCKS", "0")
        .expect("constant environment is valid")
        .redact_output()
        .output_limit(EVIDENCE_OUTPUT_BYTES);
    if let Ok(idle) = SemanticTimeout::new(std::time::Duration::from_mins(1), "evidence") {
        command = command.output_idle_timeout(idle);
    }
    let mut result = ActivityGitRunner::run_private_observing_stdout(
        command,
        gitlama_application::activity::allocate_activity_id(),
        None,
        &mut |_| {},
        observe,
    );
    let complete = !result.stdout.truncated;
    let _ = result.stdout.take_bytes();
    complete
        && matches!(
            result.activity.status,
            gitlama_application::devmil_git::activity::ActivityStatus::Succeeded { .. }
        )
}

/// The index's semantic content: mode, object, stage and path of every entry. Stat data is
/// deliberately excluded; Git refreshes it even when an operation changes nothing.
fn index_evidence(git_dir: &std::path::Path) -> Value {
    git_digest(git_dir, &["ls-files", "--stage", "-z"])
}

/// The working files: their status, the content of tracked changes and the size and time of
/// untracked files. Read-only; optional locks stay off.
fn worktree_evidence(git_dir: &std::path::Path, worktree: &std::path::Path) -> Value {
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::MetadataExt;
    let status = git_digest_in(
        git_dir,
        Some(worktree),
        &[
            "status",
            "--porcelain=v2",
            "-z",
            "--untracked-files=all",
            "--ignore-submodules=none",
        ],
    );
    let changes = git_digest_in(
        git_dir,
        Some(worktree),
        &[
            "diff",
            "-z",
            "--binary",
            "--no-ext-diff",
            "--no-textconv",
            "--no-color",
        ],
    );
    let mut untracked = Vec::new();
    let listed = run_evidence_query(
        git_dir,
        Some(worktree),
        &["ls-files", "-o", "-z", "--exclude-standard"],
        &mut |bytes| untracked.extend_from_slice(bytes),
    );
    if !listed || status.is_null() || changes.is_null() {
        return Value::Null;
    }
    let mut files = Sha256::new();
    for path in untracked.split(|byte| *byte == 0) {
        if path.is_empty() {
            continue;
        }
        files.update(u32::try_from(path.len()).unwrap_or(u32::MAX).to_be_bytes());
        files.update(path);
        let path = worktree.join(std::ffi::OsStr::from_bytes(path));
        if let Ok(metadata) = std::fs::symlink_metadata(path) {
            files.update(metadata.len().to_be_bytes());
            files.update(metadata.mtime().to_be_bytes());
            files.update(metadata.mtime_nsec().to_be_bytes());
            files.update(metadata.mode().to_be_bytes());
        }
    }
    Value::from(sha256_hex(&[
        &w::to_bytes(&status),
        &w::to_bytes(&changes),
        crate::protocol::hex(&files.finalize()).as_bytes(),
    ]))
}

/// What HEAD names and resolves to.
fn head_evidence(git_dir: &std::path::Path) -> Value {
    let symbolic = git_digest(git_dir, &["symbolic-ref", "-q", "HEAD"]);
    let resolved = git_digest(git_dir, &["rev-parse", "-q", "--verify", "HEAD"]);
    Value::from(sha256_hex(&[
        &w::to_bytes(&symbolic),
        &w::to_bytes(&resolved),
    ]))
}

impl Writes {
    /// The coordinator for a store whose receipt directories are usable. `home` locates the
    /// store for the core, which reads a patch to apply by path.
    pub fn open(store: &crate::store::Store, home: Option<&std::path::Path>) -> Option<Self> {
        let root = rustix::io::fcntl_dupfd_cloexec(store.directory(), 3).ok()?;
        let receipts = directory(&root, c"receipts")?;
        let locks = directory(&root, c"locks")?;
        let patches = home.and_then(|home| {
            directory(&root, c"patches")?;
            let path = home.join(".local/state/gitlama/remote-helper/patches");
            remove_stale_patches(&path);
            Some(path)
        });
        let writes = Self {
            root,
            receipts,
            locks,
            patches,
            epoch: Mutex::new(String::new()),
            previews: Mutex::new(HashMap::new()),
        };
        let _store = lock_file(&writes.root, "store.lock", LOCK_WAIT).ok()?;
        let epoch = writes.current_epoch()?;
        *lock(&writes.epoch) = epoch;
        writes.compact();
        Some(writes)
    }

    fn current_epoch(&self) -> Option<String> {
        match read_bounded(&self.root, "admission.json", 4096) {
            Ok(Some(bytes)) => {
                let value = w::parse(&bytes, ParseLimits::FRAME).ok()?;
                let object = w::object(&value, "admission", &["schema", "epoch"]).ok()?;
                let epoch = object.field("epoch").as_str()?;
                (object.field("schema").as_u64() == Some(1) && crate::protocol::is_hex(epoch, 32))
                    .then(|| epoch.to_owned())
            }
            Ok(None) => self.rotate_epoch(),
            // An unreadable admission record blocks writes rather than starting a new epoch.
            Err(()) => None,
        }
    }

    /// Writes a fresh random epoch. Callers hold the store lock.
    fn rotate_epoch(&self) -> Option<String> {
        let epoch = crate::protocol::random_id().ok()?;
        let record = format!("{{\"schema\":1,\"epoch\":\"{epoch}\"}}\n");
        write_atomic(&self.root, "admission.json", record.as_bytes()).then_some(epoch)
    }

    fn epoch_directory(&self, epoch: &str) -> Option<OwnedFd> {
        if !crate::protocol::is_hex(epoch, 32) {
            return None;
        }
        directory(&self.receipts, &name(epoch)?)
    }

    /// Names in a directory capability, without following links.
    fn names(directory: &OwnedFd) -> Vec<String> {
        let Ok(mut entries) = fs::Dir::read_from(directory) else {
            return Vec::new();
        };
        let mut names = Vec::new();
        while let Some(Ok(entry)) = entries.read() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name != "." && name != ".." {
                names.push(name);
            }
        }
        names
    }

    fn receipt_count(&self) -> usize {
        Self::names(&self.receipts)
            .iter()
            .filter_map(|epoch| self.epoch_directory(epoch))
            .map(|directory| Self::names(&directory).len())
            .sum()
    }

    /// Above the threshold, rotates the epoch, then deletes resolved receipts of retired epochs
    /// past their retention. Unresolved receipts are never removed. Callers hold the store lock.
    fn compact(&self) {
        if self.receipt_count() < COMPACTION_THRESHOLD {
            return;
        }
        let Some(epoch) = self.rotate_epoch() else {
            return;
        };
        let retired_before = gitlama_application::clock::unix_millis()
            .saturating_sub(u64::try_from(RESOLVED_RETENTION.as_millis()).unwrap_or(u64::MAX));
        for epoch_name in Self::names(&self.receipts) {
            if epoch_name == epoch {
                continue;
            }
            let Some(directory) = self.epoch_directory(&epoch_name) else {
                continue;
            };
            for file in Self::names(&directory) {
                let Ok(Some(bytes)) = read_bounded(&directory, &file, RECEIPT_BYTES) else {
                    continue;
                };
                let Some(parsed) = Receipt::parse(&bytes) else {
                    continue;
                };
                if parsed.state == "terminal" && parsed.updated_millis < retired_before {
                    if let Some(target) = name(&file) {
                        let _ = fs::unlinkat(&directory, &target, fs::AtFlags::empty());
                    }
                }
            }
            let _ = crate::store::sync_directory(&directory);
        }
        *lock(&self.epoch) = epoch;
    }

    fn read_receipt(&self, epoch: &str, operation_id: &str) -> Result<Option<Receipt>, Code> {
        let Some(directory) = self.epoch_directory(epoch) else {
            return Err("storeUnavailable");
        };
        match read_bounded(&directory, &format!("{operation_id}.json"), RECEIPT_BYTES) {
            Ok(Some(bytes)) => Receipt::parse(&bytes).map(Some).ok_or("storeUnavailable"),
            Ok(None) => Ok(None),
            Err(()) => Err("storeUnavailable"),
        }
    }

    fn write_receipt(&self, receipt: &Receipt) -> bool {
        let Some(directory) = self.epoch_directory(&receipt.epoch) else {
            return false;
        };
        let bytes = w::to_bytes(&receipt.to_value());
        bytes.len() as u64 <= RECEIPT_BYTES
            && write_atomic(
                &directory,
                &format!("{}.json", receipt.operation_id),
                &bytes,
            )
    }

    /// Answers one write method.
    ///
    /// # Errors
    /// A protocol error code.
    pub fn call(
        &self,
        connection: &Connection,
        method: &str,
        arguments: &Value,
    ) -> Result<Value, Code> {
        if method == "lookupOperation" {
            return self.lookup(arguments);
        }
        if let Some(family) = method.strip_prefix("preview").and_then(Family::of_method) {
            return self.preview(connection, family, arguments);
        }
        if let Some(family) = method.strip_prefix("execute").and_then(Family::of_method) {
            return self.execute(connection, family, arguments);
        }
        Err("unsupportedCommand")
    }

    /// Keeps the patch of a `previewPatch` request in a private file the core can read and
    /// check again before applying it.
    fn keep_patch(&self, request: &Value) -> Result<std::path::PathBuf, Code> {
        let object = w::object(request, "patch", &["content"]).map_err(|_| "invalidRequest")?;
        let content = w::bytes_d(object.field("content")).map_err(|_| "invalidRequest")?;
        if content.is_empty() || content.len() > PATCH_BYTES {
            return Err("invalidRequest");
        }
        let directory_path = self.patches.as_ref().ok_or("storeUnavailable")?;
        let directory = directory(&self.root, c"patches").ok_or("storeUnavailable")?;
        let file = format!(
            "{}.patch",
            crate::protocol::random_id().map_err(|_| "internal")?
        );
        if !write_atomic(&directory, &file, &content) {
            return Err("storeUnavailable");
        }
        Ok(directory_path.join(file))
    }

    fn session(
        connection: &Connection,
        object: &w::Object<'_>,
    ) -> Result<(u64, u64, Workspace), Code> {
        let session_id: u64 = w::big_d(object.field("sessionId")).map_err(|_| "invalidRequest")?;
        let generation: u64 = w::big_d(object.field("generation")).map_err(|_| "invalidRequest")?;
        let (live_generation, workspace) = connection
            .sessions
            .workspace_of(session_id)
            .ok_or("unknownSession")?;
        if live_generation != generation {
            return Err("unknownSession");
        }
        Ok((session_id, generation, workspace))
    }

    fn preview(
        &self,
        connection: &Connection,
        family: Family,
        arguments: &Value,
    ) -> Result<Value, Code> {
        let object = w::object(
            arguments,
            "preview",
            &["sessionId", "generation", "request"],
        )
        .map_err(|_| "invalidRequest")?;
        let (session_id, generation, workspace) = Self::session(connection, &object)?;
        let request = object.field("request").clone();
        require_pull_stash_capability(connection, family, &request)?;
        // Plans against the current state; the helper sees no file events between refreshes.
        // Staging names exact rows of a diff the client read and checks them itself.
        if family != Family::Stage
            && !gitlama_application::application::session::reload_snapshot(session_id, generation)
        {
            return Err("unknownSession");
        }
        let mut patch_file = match family {
            Family::Patch => Some(self.keep_patch(&request)?),
            _ => None,
        };
        let (core_token, core_preview) = core_preview(
            family,
            session_id,
            generation,
            &request,
            patch_file.as_deref(),
        )?;
        let epoch = lock(&self.epoch).clone();
        let digest = intent_digest(family, &workspace.binding, &request);
        let mut result = Map::new();
        if !family.direct() && core_token.is_none() {
            if let Some(file) = patch_file.take() {
                let _ = std::fs::remove_file(file);
            }
            // The core rejected the operation; there is nothing to admit.
            result.insert("token".into(), Value::Null);
        } else {
            let token = crate::protocol::random_id().map_err(|_| "internal")?;
            let mut previews = lock(&self.previews);
            previews.retain(|_, preview| preview.created.elapsed() <= PREVIEW_LIFETIME);
            let mut own: Vec<(String, Instant)> = previews
                .iter()
                .filter(|(_, preview)| preview.session_id == session_id)
                .map(|(token, preview)| (token.clone(), preview.created))
                .collect();
            if own.len() >= PREVIEWS_PER_SESSION {
                own.sort_by_key(|(_, created)| *created);
                previews.remove(&own[0].0);
            }
            previews.insert(
                token.clone(),
                Preview {
                    session_id,
                    generation,
                    family,
                    epoch: epoch.clone(),
                    digest: digest.clone(),
                    request,
                    core_token,
                    created: Instant::now(),
                    patch_file: patch_file.take(),
                },
            );
            result.insert("token".into(), Value::from(token));
        }
        result.insert("epoch".into(), Value::from(epoch));
        result.insert("digest".into(), Value::from(digest));
        result.insert(
            "expiresInMs".into(),
            Value::from(PREVIEW_LIFETIME.as_millis().to_string()),
        );
        if let Some(preview) = core_preview {
            result.insert("preview".into(), preview);
        }
        Ok(Value::Object(result))
    }

    #[allow(clippy::too_many_lines)] // One admission sequence; each step's order is the contract.
    fn execute(
        &self,
        connection: &Connection,
        family: Family,
        arguments: &Value,
    ) -> Result<Value, Code> {
        let names: &[&str] = match family {
            _ if family.direct() => &[
                "sessionId",
                "generation",
                "token",
                "epoch",
                "digest",
                "operationId",
                "request",
            ],
            _ => &[
                "sessionId",
                "generation",
                "token",
                "epoch",
                "digest",
                "operationId",
            ],
        };
        let object = w::object(arguments, "execute", names).map_err(|_| "invalidRequest")?;
        let text = |field: &str| object.field(field).as_str().ok_or("invalidRequest");
        let (token, epoch, digest, operation_id) = (
            text("token")?,
            text("epoch")?,
            text("digest")?,
            text("operationId")?,
        );
        if !crate::protocol::is_hex(operation_id, 32)
            || !crate::protocol::is_hex(epoch, 32)
            || !crate::protocol::is_hex(digest, 64)
        {
            return Err("invalidRequest");
        }
        let (session_id, generation, workspace) = Self::session(connection, &object)?;
        // A known operation is answered from its receipt, even when unresolved: never twice.
        if let Some(existing) = self.read_receipt(epoch, operation_id)? {
            return if existing.digest == digest && existing.binding == workspace.binding {
                Ok(executed(&existing, None, None))
            } else {
                Err("operationIdConflict")
            };
        }
        if epoch != *lock(&self.epoch) {
            return Err("admissionEpochRetired");
        }
        let preview = {
            let previews = lock(&self.previews);
            let preview = previews.get(token).ok_or("previewExpired")?;
            if preview.created.elapsed() > PREVIEW_LIFETIME
                || preview.session_id != session_id
                || preview.generation != generation
                || preview.family != family
                || preview.epoch != epoch
            {
                return Err("previewExpired");
            }
            if preview.digest != digest {
                return Err("preconditionFailed");
            }
            (preview.request.clone(), preview.core_token)
        };
        if family.direct()
            && intent_digest(family, &workspace.binding, object.field("request")) != digest
        {
            return Err("preconditionFailed");
        }
        let request = preview.0;
        require_pull_stash_capability(connection, family, &request)?;
        // Serializes this repository's helper mutations across sessions and processes.
        let _repository = lock_file(
            &self.locks,
            &format!("{}.lock", workspace.lock_key),
            LOCK_WAIT,
        )?;
        let mut receipt = {
            let _store = lock_file(&self.root, "store.lock", LOCK_WAIT)?;
            if epoch != *lock(&self.epoch) {
                return Err("admissionEpochRetired");
            }
            if self.read_receipt(epoch, operation_id)?.is_some() {
                return Err("operationIdConflict");
            }
            if self.receipt_count() >= RECEIPTS {
                return Err("receiptCapacity");
            }
            let receipt = Receipt {
                operation_id: operation_id.to_owned(),
                epoch: epoch.to_owned(),
                family: family.name().to_owned(),
                digest: digest.to_owned(),
                binding: workspace.binding.clone(),
                lock_key: workspace.lock_key.clone(),
                owner: connection.session.incarnation.clone(),
                state: "prepared".into(),
                outcome: None,
                result_object_id: None,
                evidence: Map::new(),
                updated_millis: gitlama_application::clock::unix_millis(),
            };
            if !self.write_receipt(&receipt) {
                return Err("storeUnavailable");
            }
            receipt
        };
        fault("after-prepared");
        // The token is consumed only now: a failed durable write above leaves it usable. A kept
        // patch outlives the preview until Git has applied it.
        let consumed = lock(&self.previews)
            .remove(token)
            .map(|mut preview| preview.patch_file.take());
        let _patch = PatchFile(consumed.clone().flatten());
        if consumed.is_none() {
            receipt.state = "terminal".into();
            receipt.outcome = Some("notApplied".into());
            let _ = self.write_receipt(&receipt);
            return Err("previewExpired");
        }
        for evidence in family.evidence() {
            receipt.evidence.insert(
                format!("{}Before", evidence.key()),
                evidence.collect(&workspace),
            );
        }
        receipt.state = "started".into();
        receipt.updated_millis = gitlama_application::clock::unix_millis();
        if !self.write_receipt(&receipt) {
            // Prepared is durable and no executor started: provably not applied.
            receipt.state = "terminal".into();
            receipt.outcome = Some("notApplied".into());
            let _ = self.write_receipt(&receipt);
            return Err("storeUnavailable");
        }
        fault("after-started");
        let core_token = preview.1;
        let (outcome, result_object_id, result) = match family {
            Family::Stage => {
                let staging =
                    g::dec_native_staging_request(&request).map_err(|_| "invalidRequest")?;
                let result =
                    gitlama_application::application::staging::repository_session_staging_execute(
                        session_id, generation, staging,
                    );
                let unchanged = record_after(family, &workspace, &mut receipt);
                let outcome = settle(
                    match result.state {
                        NativeStagingExecutionState::Completed
                        | NativeStagingExecutionState::ReconciledWithWarning => Terminal::Done,
                        NativeStagingExecutionState::Stale => Terminal::Stale,
                        NativeStagingExecutionState::Failed => Terminal::Refused,
                        NativeStagingExecutionState::OutcomeUncertain => Terminal::Uncertain,
                    },
                    unchanged,
                );
                (
                    outcome,
                    None,
                    g::enc_native_staging_execution_result(&result),
                )
            }
            Family::Commit => {
                let result =
                    gitlama_application::application::commit::repository_session_commit_execute(
                        session_id,
                        generation,
                        core_token.ok_or("previewExpired")?,
                    );
                let unchanged = record_after(family, &workspace, &mut receipt);
                let outcome = settle(
                    match result.state {
                        NativeCommitExecutionState::Completed
                        | NativeCommitExecutionState::ReconciledWithWarning
                            if result.commit.is_some() =>
                        {
                            Terminal::Done
                        }
                        NativeCommitExecutionState::Stale => Terminal::Stale,
                        NativeCommitExecutionState::OutcomeUncertain => Terminal::Uncertain,
                        // A commit without its new object cannot be confirmed either.
                        NativeCommitExecutionState::Completed
                        | NativeCommitExecutionState::ReconciledWithWarning
                        | NativeCommitExecutionState::Failed => Terminal::Failed,
                    },
                    unchanged,
                );
                (
                    outcome,
                    result.commit.clone(),
                    g::enc_native_commit_execution_result(&result),
                )
            }
            Family::Refs => {
                let result =
                    gitlama_application::application::refs::repository_session_ref_mutation_execute(
                        session_id,
                        generation,
                        core_token.ok_or("previewExpired")?,
                    );
                let unchanged = record_after(family, &workspace, &mut receipt);
                let outcome = settle(
                    match result.state {
                        NativeRefMutationExecutionState::Completed
                        | NativeRefMutationExecutionState::ReconciledWithWarning => Terminal::Done,
                        NativeRefMutationExecutionState::Stale => Terminal::Stale,
                        NativeRefMutationExecutionState::Failed => Terminal::Failed,
                        NativeRefMutationExecutionState::OutcomeUncertain => Terminal::Uncertain,
                    },
                    unchanged,
                );
                (
                    outcome,
                    None,
                    g::enc_native_ref_mutation_execution_result(&result),
                )
            }
            Family::Stash => {
                let result =
                    gitlama_application::application::stash::repository_session_stash_execute(
                        session_id,
                        generation,
                        core_token.ok_or("previewExpired")?,
                    );
                let unchanged = record_after(family, &workspace, &mut receipt);
                let outcome = settle(
                    match result.state {
                        NativeStashExecutionState::Completed
                        | NativeStashExecutionState::ReconciledWithWarning => Terminal::Done,
                        // The stash ran and left conflicts; the result says whether it was kept.
                        NativeStashExecutionState::Conflict => Terminal::Partial,
                        NativeStashExecutionState::Stale => Terminal::Stale,
                        NativeStashExecutionState::Failed => Terminal::Failed,
                        NativeStashExecutionState::OutcomeUncertain => Terminal::Uncertain,
                    },
                    unchanged,
                );
                (outcome, None, g::enc_native_stash_execution_result(&result))
            }
            Family::Discard => {
                let result =
                    gitlama_application::application::discard::repository_session_discard_execute(
                        session_id,
                        generation,
                        core_token.ok_or("previewExpired")?,
                    );
                let unchanged = record_after(family, &workspace, &mut receipt);
                // Some files may already be gone after a failure: nothing is ever restored or
                // resent, so a changed worktree leaves the outcome unknown.
                let outcome = settle(
                    match result.state {
                        NativeDiscardExecutionState::Completed
                        | NativeDiscardExecutionState::ReconciledWithWarning => Terminal::Done,
                        NativeDiscardExecutionState::Stale => Terminal::Stale,
                        NativeDiscardExecutionState::Failed => Terminal::Failed,
                        NativeDiscardExecutionState::OutcomeUncertain => Terminal::Uncertain,
                    },
                    unchanged,
                );
                (
                    outcome,
                    None,
                    g::enc_native_discard_execution_result(&result),
                )
            }
            Family::Transfer => {
                let kind = g::dec_native_transfer_request(&request)
                    .map_err(|_| "invalidRequest")?
                    .kind;
                let result =
                    gitlama_application::application::transfer::repository_session_transfer_execute(
                        session_id,
                        generation,
                        core_token.ok_or("previewExpired")?,
                    );
                let unchanged = record_after(family, &workspace, &mut receipt);
                let outcome = settle(
                    match result.state {
                        NativeTransferExecutionState::Completed
                        | NativeTransferExecutionState::ReconciledWithWarning => Terminal::Done,
                        NativeTransferExecutionState::Stale => Terminal::Stale,
                        // A push may have reached the server even when nothing changed here.
                        NativeTransferExecutionState::Failed
                            if updates_server(kind)
                                && !refused_before_update(
                                    result.failure.as_ref().map(|failure| failure.kind),
                                ) =>
                        {
                            Terminal::Uncertain
                        }
                        NativeTransferExecutionState::Failed => Terminal::Failed,
                        NativeTransferExecutionState::OutcomeUncertain => Terminal::Uncertain,
                    },
                    unchanged,
                );
                (
                    outcome,
                    None,
                    g::enc_native_transfer_execution_result(&result),
                )
            }
            other => {
                let result = execute_core(other, session_id, generation, core_token, &request)?;
                let unchanged = record_after(family, &workspace, &mut receipt);
                (settle(terminal_of(other, &result), unchanged), None, result)
            }
        };
        fault("before-terminal");
        receipt.state = "terminal".into();
        receipt.outcome = Some(outcome.name().to_owned());
        receipt.result_object_id = result_object_id;
        receipt.updated_millis = gitlama_application::clock::unix_millis();
        if self.write_receipt(&receipt) {
            fault("after-terminal");
            Ok(executed(&receipt, None, Some(result)))
        } else {
            // The Git outcome stands; only the receipt's durability degraded.
            receipt.state = "started".into();
            Ok(executed(&receipt, Some(outcome.name()), Some(result)))
        }
    }

    fn lookup(&self, arguments: &Value) -> Result<Value, Code> {
        let object = w::object(
            arguments,
            "lookupOperation",
            &["epoch", "operationId", "digest"],
        )
        .map_err(|_| "invalidRequest")?;
        let text = |field: &str| object.field(field).as_str().ok_or("invalidRequest");
        let (epoch, operation_id, digest) = (text("epoch")?, text("operationId")?, text("digest")?);
        if !crate::protocol::is_hex(operation_id, 32) || !crate::protocol::is_hex(epoch, 32) {
            return Err("invalidRequest");
        }
        let Some(receipt) = self.read_receipt(epoch, operation_id)? else {
            let mut operation = Map::new();
            operation.insert("operationId".into(), Value::from(operation_id));
            operation.insert("epoch".into(), Value::from(epoch));
            operation.insert("state".into(), Value::from("absent"));
            // An absent receipt never proves the operation did not run.
            operation.insert("outcome".into(), Value::from("unknown"));
            operation.insert("resultObjectId".into(), Value::Null);
            let mut map = Map::new();
            map.insert("operation".into(), Value::Object(operation));
            return Ok(Value::Object(map));
        };
        if receipt.digest != digest {
            return Err("operationIdConflict");
        }
        let outcome = match receipt.state.as_str() {
            "terminal" => None,
            state => {
                // The owner holds the repository lock while it executes. A lock we can take
                // means the owner is gone: Prepared never started, Started may have run.
                match lock_file(
                    &self.locks,
                    &format!("{}.lock", receipt.lock_key),
                    Duration::ZERO,
                ) {
                    Ok(_held) if state == "prepared" => Some("notApplied"),
                    Ok(_held) => Some("unknown"),
                    Err(_) => Some("running"),
                }
            }
        };
        let mut map = Map::new();
        map.insert("operation".into(), receipt.operation(outcome));
        Ok(Value::Object(map))
    }
}

/// Ends the process at a named durability boundary when `GITLAMA_HELPER_FAULT` names it.
/// Compiled only into debug builds, which tests use; release helpers have no fault hook.
#[cfg(debug_assertions)]
fn fault(boundary: &str) {
    if std::env::var("GITLAMA_HELPER_FAULT").as_deref() == Ok(boundary) {
        std::process::abort();
    }
}

#[cfg(not(debug_assertions))]
fn fault(_boundary: &str) {}

fn executed(receipt: &Receipt, outcome: Option<&str>, result: Option<Value>) -> Value {
    let mut map = Map::new();
    map.insert("operation".into(), receipt.operation(outcome));
    map.insert("result".into(), result.unwrap_or(Value::Null));
    Value::Object(map)
}

/// Validates `request` and previews it in the core, which captures the exact state the
/// operation was previewed against and keeps a token for it. The helper token admits that core
/// token once. Staging has no core preview.
fn core_preview(
    family: Family,
    session_id: u64,
    generation: u64,
    request: &Value,
    patch_file: Option<&std::path::Path>,
) -> Result<(Option<u64>, Option<Value>), Code> {
    Ok(match family {
        Family::Stage => {
            validate_stage(&g::dec_native_staging_request(request).map_err(|_| "invalidRequest")?)?;
            (None, None)
        }
        Family::Commit => {
            let commit = g::dec_native_commit_request(request).map_err(|_| "invalidRequest")?;
            validate_commit(&commit)?;
            let result =
                gitlama_application::application::commit::repository_session_commit_preview(
                    session_id, generation, commit,
                );
            (
                result.preview.as_ref().map(|preview| preview.token),
                Some(g::enc_native_commit_preview_result(&result)),
            )
        }
        Family::Refs => {
            let refs = g::dec_native_ref_mutation_request(request).map_err(|_| "invalidRequest")?;
            validate_refs(&refs)?;
            let result =
                gitlama_application::application::refs::repository_session_ref_mutation_preview(
                    session_id, generation, refs,
                );
            (
                result.preview.as_ref().map(|preview| preview.token),
                Some(g::enc_native_ref_mutation_preview_result(&result)),
            )
        }
        Family::Stash => {
            let stash = g::dec_native_stash_request(request).map_err(|_| "invalidRequest")?;
            validate_stash(&stash)?;
            let result = gitlama_application::application::stash::repository_session_stash_preview(
                session_id, generation, stash,
            );
            (
                result.preview.as_ref().map(|preview| preview.token),
                Some(g::enc_native_stash_preview_result(&result)),
            )
        }
        Family::Discard => {
            let discard = g::dec_native_discard_request(request).map_err(|_| "invalidRequest")?;
            validate_discard(&discard)?;
            let result =
                gitlama_application::application::discard::repository_session_discard_preview(
                    session_id, generation, discard,
                );
            (
                result.preview.as_ref().map(|preview| preview.token),
                Some(g::enc_native_discard_preview_result(&result)),
            )
        }
        Family::Transfer => {
            let transfer = g::dec_native_transfer_request(request).map_err(|_| "invalidRequest")?;
            validate_transfer(&transfer)?;
            let result =
                gitlama_application::application::transfer::repository_session_transfer_preview(
                    session_id, generation, transfer,
                );
            (
                result.preview.as_ref().map(|preview| preview.token),
                Some(g::enc_native_transfer_preview_result(&result)),
            )
        }
        _ => later_preview(family, session_id, generation, request, patch_file)?,
    })
}

/// Previews an operation of the families added after the first six.
#[allow(clippy::too_many_lines)] // One dispatch table: request decoding per family.
fn later_preview(
    family: Family,
    session_id: u64,
    generation: u64,
    request: &Value,
    patch_file: Option<&std::path::Path>,
) -> Result<(Option<u64>, Option<Value>), Code> {
    Ok(match family {
        Family::History => {
            let mutation =
                g::dec_native_history_mutation_request(request).map_err(|_| "invalidRequest")?;
            if mutation.targets.is_empty()
                || mutation.targets.len() > STAGE_PATHS
                || !mutation.targets.iter().all(|target| text(Some(target)))
                || !bytes_text(mutation.source_name.as_deref())
            {
                return Err("invalidRequest");
            }
            with_token(g::enc_native_history_mutation_preview_result(
                &gitlama_application::application::history_mutations::repository_session_history_mutation_preview(
                    session_id, generation, mutation,
                ),
            ))
        }
        Family::Rebase => {
            let object = w::object(
                request,
                "rebase",
                &[
                    "planToken",
                    "instructions",
                    "acknowledgePublishedHistory",
                    "applyAutosquash",
                ],
            )
            .map_err(|_| "invalidRequest")?;
            let instructions = w::list_d(
                object.field("instructions"),
                g::dec_native_rebase_instruction,
            )
            .map_err(|_| "invalidRequest")?;
            if instructions.len() > STAGE_ROWS {
                return Err("invalidRequest");
            }
            with_token(g::enc_native_rebase_preview_result(
                &gitlama_application::application::rebase::repository_session_rebase_preview(
                    session_id,
                    generation,
                    w::big_d(object.field("planToken")).map_err(|_| "invalidRequest")?,
                    instructions,
                    w::bool_d(object.field("acknowledgePublishedHistory"))
                        .map_err(|_| "invalidRequest")?,
                    w::bool_d(object.field("applyAutosquash")).map_err(|_| "invalidRequest")?,
                ),
            ))
        }
        // The plan was read before; its token is what Execute runs.
        Family::Restack => {
            let object = w::object(
                request,
                "restack",
                &["planToken", "acknowledgePublishedHistory"],
            )
            .map_err(|_| "invalidRequest")?;
            w::bool_d(object.field("acknowledgePublishedHistory")).map_err(|_| "invalidRequest")?;
            (
                Some(w::big_d(object.field("planToken")).map_err(|_| "invalidRequest")?),
                None,
            )
        }
        Family::IndexLock => {
            let object =
                w::object(request, "indexLock", &["token"]).map_err(|_| "invalidRequest")?;
            (
                Some(w::big_d(object.field("token")).map_err(|_| "invalidRequest")?),
                None,
            )
        }
        Family::Bisect => {
            let object = w::object(request, "bisect", &["action", "good", "bad"])
                .map_err(|_| "invalidRequest")?;
            let action = g::dec_native_bisect_action(object.field("action"))
                .map_err(|_| "invalidRequest")?;
            let good = w::opt_d(object.field("good"), w::str_d).map_err(|_| "invalidRequest")?;
            let bad = w::opt_d(object.field("bad"), w::str_d).map_err(|_| "invalidRequest")?;
            if !text(good.as_ref()) || !text(bad.as_ref()) {
                return Err("invalidRequest");
            }
            with_token(g::enc_native_bisect_preview_result(
                &gitlama_application::application::power_tools::repository_session_bisect_preview(
                    session_id, generation, action, good, bad,
                ),
            ))
        }
        Family::SnapshotRestore => {
            let object = w::object(request, "snapshotRestore", &["snapshotId"])
                .map_err(|_| "invalidRequest")?;
            with_token(g::enc_native_named_snapshot_restore_preview_result(
                &gitlama_application::application::snapshots::repository_session_named_snapshot_restore_preview(
                    session_id,
                    generation,
                    w::big_d(object.field("snapshotId")).map_err(|_| "invalidRequest")?,
                ),
            ))
        }
        Family::Restore => {
            let object = w::object(request, "restore", &["commit", "path", "byteLimit"])
                .map_err(|_| "invalidRequest")?;
            let commit = w::str_d(object.field("commit")).map_err(|_| "invalidRequest")?;
            let path = w::bytes_d(object.field("path")).map_err(|_| "invalidRequest")?;
            if !text(Some(&commit)) || !valid_path(&path) {
                return Err("invalidRequest");
            }
            with_token(g::enc_native_restore_preview_result(
                &gitlama_application::application::restore::repository_session_restore_preview(
                    session_id,
                    generation,
                    commit,
                    path,
                    w::int_d(object.field("byteLimit")).map_err(|_| "invalidRequest")?,
                ),
            ))
        }
        Family::Patch => {
            let path = patch_file.ok_or("internal")?;
            with_token(g::enc_native_patch_apply_preview_result(
                &gitlama_application::application::patch::repository_session_patch_apply_preview(
                    session_id,
                    generation,
                    path.to_str().ok_or("storeUnavailable")?.to_owned(),
                ),
            ))
        }
        Family::Conflict => {
            decode_conflict(request)?;
            (None, None)
        }
        Family::Sequencer => {
            decode_sequencer(request)?;
            (None, None)
        }
        Family::Snapshot => {
            decode_snapshot(request)?;
            (None, None)
        }
        Family::Extension => {
            validate_extension(
                &g::dec_native_extension_mutation_request(request).map_err(|_| "invalidRequest")?,
            )?;
            (None, None)
        }
        Family::Stage
        | Family::Commit
        | Family::Refs
        | Family::Stash
        | Family::Transfer
        | Family::Discard => return Err("internal"),
    })
}

/// The core token of an encoded preview result, at its top or in its `preview`.
fn with_token(result: Value) -> (Option<u64>, Option<Value>) {
    let field = |value: &Value| {
        value
            .as_object()
            .and_then(|object| object.get("token"))
            .and_then(|token| w::big_d::<u64>(token).ok())
    };
    let token = field(&result).or_else(|| {
        result
            .as_object()
            .and_then(|object| object.get("preview"))
            .and_then(field)
    });
    (token, Some(result))
}

/// Runs a previewed or direct operation of the families added after the first six and returns
/// its encoded result.
#[allow(clippy::too_many_lines)] // One dispatch table: a core call per family and action.
fn execute_core(
    family: Family,
    session_id: u64,
    generation: u64,
    core_token: Option<u64>,
    request: &Value,
) -> Result<Value, Code> {
    let token = || core_token.ok_or("previewExpired");
    Ok(match family {
        Family::History => g::enc_native_history_mutation_execution_result(
            &gitlama_application::application::history_mutations::repository_session_history_mutation_execute(session_id, generation, token()?),
        ),
        Family::Rebase => g::enc_native_rebase_execution_result(
            &gitlama_application::application::rebase::repository_session_rebase_execute(session_id, generation, token()?),
        ),
        Family::Restack => {
            let object = w::object(
                request,
                "restack",
                &["planToken", "acknowledgePublishedHistory"],
            )
            .map_err(|_| "invalidRequest")?;
            g::enc_native_restack_execution_result(&gitlama_application::application::rebase::repository_session_restack_execute(
                session_id,
                generation,
                token()?,
                w::bool_d(object.field("acknowledgePublishedHistory"))
                    .map_err(|_| "invalidRequest")?,
            ))
        }
        Family::Bisect => g::enc_native_bisect_execution_result(
            &gitlama_application::application::power_tools::repository_session_bisect_execute(session_id, generation, token()?),
        ),
        Family::SnapshotRestore => g::enc_native_named_snapshot_execution_result(
            &gitlama_application::application::snapshots::repository_session_named_snapshot_restore_execute(
                session_id,
                generation,
                token()?,
            ),
        ),
        Family::Restore => g::enc_native_restore_result(&gitlama_application::application::restore::repository_session_restore_file(
            session_id,
            generation,
            token()?,
        )),
        Family::IndexLock => g::enc_native_index_lock_removal_result(
            &gitlama_application::application::index_lock::repository_session_remove_index_lock(session_id, generation, token()?),
        ),
        Family::Patch => g::enc_native_patch_apply_execution_result(
            &gitlama_application::application::patch::repository_session_patch_apply_execute(session_id, generation, token()?),
        ),
        Family::Conflict => {
            g::enc_native_conflict_snapshot_result(&match decode_conflict(request)? {
                ConflictAction::ChooseSide(path, fingerprint, choice) => {
                    gitlama_application::application::conflicts::repository_session_conflict_choose_side(
                        session_id,
                        generation,
                        path,
                        fingerprint,
                        choice,
                    )
                }
                ConflictAction::TakeRegion(path, fingerprint, region, choice) => {
                    gitlama_application::application::conflicts::repository_session_conflict_take_region(
                        session_id,
                        generation,
                        path,
                        fingerprint,
                        region,
                        choice,
                    )
                }
                ConflictAction::SaveResult(path, fingerprint, result) => {
                    gitlama_application::application::conflicts::repository_session_conflict_save_result(
                        session_id,
                        generation,
                        path,
                        fingerprint,
                        result,
                    )
                }
                ConflictAction::UndoResolution(path) => {
                    gitlama_application::application::conflicts::repository_session_conflict_undo_resolution(session_id, generation, path)
                }
            })
        }
        Family::Sequencer => {
            let (action, message) = decode_sequencer(request)?;
            g::enc_native_conflict_continuation_result(&match message {
                Some(message) => gitlama_application::application::conflicts::repository_session_conflict_continue_with_message(
                    session_id, generation, action, message,
                ),
                None => gitlama_application::application::conflicts::repository_session_conflict_continue(session_id, generation, action),
            })
        }
        Family::Snapshot => {
            g::enc_native_named_snapshot_execution_result(&match decode_snapshot(request)? {
                SnapshotAction::Create {
                    name,
                    include_untracked,
                    keep_index,
                } => gitlama_application::application::snapshots::repository_session_named_snapshot_create(
                    session_id,
                    generation,
                    name,
                    include_untracked,
                    keep_index,
                ),
                SnapshotAction::Delete(id) => {
                    gitlama_application::application::snapshots::repository_session_named_snapshot_delete(session_id, generation, id)
                }
                SnapshotAction::Branch(id, branch) => {
                    gitlama_application::application::snapshots::repository_session_named_snapshot_branch(
                        session_id, generation, id, branch,
                    )
                }
            })
        }
        Family::Extension => {
            g::enc_native_extension_mutation_result(&gitlama_application::application::extensions::repository_session_extension_execute(
                session_id,
                generation,
                g::dec_native_extension_mutation_request(request).map_err(|_| "invalidRequest")?,
            ))
        }
        Family::Stage
        | Family::Commit
        | Family::Refs
        | Family::Stash
        | Family::Transfer
        | Family::Discard => return Err("internal"),
    })
}

/// The outcome of an operation of the later families, from the `state` its result reports and
/// whether the evidence proves nothing changed.
/// How a family's execution ended, before the evidence decides what that means remotely.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Terminal {
    /// Completed, possibly with a refresh or recovery warning.
    Done,
    /// Ran and left work to finish: conflicts, an edit stop or an interruption.
    Partial,
    /// Refused because the previewed state changed.
    Stale,
    /// Refused or canceled before it could change anything, as far as the core knows.
    Refused,
    /// Failed.
    Failed,
    /// Git may have changed the repository but the core could not confirm it.
    Uncertain,
}

/// The one mapping from a terminal state and the before/after evidence to the recorded
/// outcome. An uncertain result is never reported as settled.
fn settle(terminal: Terminal, unchanged: bool) -> RemoteOutcome {
    match terminal {
        Terminal::Done => RemoteOutcome::Succeeded,
        Terminal::Partial => RemoteOutcome::Partial,
        Terminal::Stale => RemoteOutcome::NotApplied,
        Terminal::Refused if unchanged => RemoteOutcome::NotApplied,
        Terminal::Failed if unchanged => RemoteOutcome::Failed,
        Terminal::Refused | Terminal::Failed | Terminal::Uncertain => RemoteOutcome::Unknown,
    }
}

/// The terminal state of a family whose result arrives as wire JSON.
fn terminal_of(family: Family, result: &Value) -> Terminal {
    let object = result.as_object();
    let field = |name: &str| object.and_then(|object| object.get(name));
    match family {
        // A resolution reports a failure or the new conflict snapshot.
        Family::Conflict if field("failure").is_some_and(Value::is_null) => Terminal::Done,
        Family::IndexLock if field("removed").and_then(Value::as_bool) == Some(true) => {
            Terminal::Done
        }
        Family::Conflict | Family::IndexLock => Terminal::Failed,
        _ => match field("state").and_then(Value::as_str) {
            Some(
                "completed" | "alreadyContained" | "reconciledWithWarning" | "restored" | "aborted",
            ) => Terminal::Done,
            Some("conflict" | "interrupted" | "editStop" | "partial") => Terminal::Partial,
            Some("stale") => Terminal::Stale,
            Some("canceled") => Terminal::Refused,
            Some("outcomeUncertain") => Terminal::Uncertain,
            _ => Terminal::Failed,
        },
    }
}

#[cfg(test)]
fn outcome_of(family: Family, result: &Value, unchanged: bool) -> &'static str {
    settle(terminal_of(family, result), unchanged).name()
}

enum ConflictAction {
    ChooseSide(
        Vec<u8>,
        u64,
        gitlama_application::conflict::NativeConflictSideChoice,
    ),
    TakeRegion(
        Vec<u8>,
        u64,
        u32,
        gitlama_application::conflict::NativeConflictRegionChoice,
    ),
    SaveResult(Vec<u8>, u64, Vec<u8>),
    UndoResolution(Vec<u8>),
}

fn decode_conflict(request: &Value) -> Result<ConflictAction, Code> {
    let object = w::object(
        request,
        "conflict",
        &[
            "action",
            "path",
            "expectedFingerprint",
            "side",
            "regionIndex",
            "region",
            "result",
        ],
    )
    .map_err(|_| "invalidRequest")?;
    let path = w::bytes_d(object.field("path")).map_err(|_| "invalidRequest")?;
    if !valid_path(&path) {
        return Err("invalidRequest");
    }
    let fingerprint = || -> Result<u64, Code> {
        w::big_d(object.field("expectedFingerprint")).map_err(|_| "invalidRequest")
    };
    Ok(
        match w::str_ref(object.field("action")).map_err(|_| "invalidRequest")? {
            "chooseSide" => ConflictAction::ChooseSide(
                path,
                fingerprint()?,
                g::dec_native_conflict_side_choice(object.field("side"))
                    .map_err(|_| "invalidRequest")?,
            ),
            "takeRegion" => ConflictAction::TakeRegion(
                path,
                fingerprint()?,
                w::int_d(object.field("regionIndex")).map_err(|_| "invalidRequest")?,
                g::dec_native_conflict_region_choice(object.field("region"))
                    .map_err(|_| "invalidRequest")?,
            ),
            "saveResult" => {
                let result = w::bytes_d(object.field("result")).map_err(|_| "invalidRequest")?;
                if result.len() > CONFLICT_RESULT_BYTES {
                    return Err("invalidRequest");
                }
                ConflictAction::SaveResult(path, fingerprint()?, result)
            }
            "undoResolution" => ConflictAction::UndoResolution(path),
            _ => return Err("invalidRequest"),
        },
    )
}

fn decode_sequencer(
    request: &Value,
) -> Result<
    (
        gitlama_application::conflict::NativeConflictSequencerAction,
        Option<String>,
    ),
    Code,
> {
    let object =
        w::object(request, "sequencer", &["action", "message"]).map_err(|_| "invalidRequest")?;
    let action = g::dec_native_conflict_sequencer_action(object.field("action"))
        .map_err(|_| "invalidRequest")?;
    let message = w::opt_d(object.field("message"), w::str_d).map_err(|_| "invalidRequest")?;
    if !message_ok(message.as_ref()) {
        return Err("invalidRequest");
    }
    Ok((action, message))
}

enum SnapshotAction {
    Create {
        name: String,
        include_untracked: bool,
        keep_index: bool,
    },
    Delete(u64),
    Branch(u64, Vec<u8>),
}

fn decode_snapshot(request: &Value) -> Result<SnapshotAction, Code> {
    let object = w::object(
        request,
        "snapshot",
        &[
            "action",
            "name",
            "includeUntracked",
            "keepIndex",
            "snapshotId",
            "branch",
        ],
    )
    .map_err(|_| "invalidRequest")?;
    let id = || -> Result<u64, Code> {
        w::big_d(object.field("snapshotId")).map_err(|_| "invalidRequest")
    };
    Ok(
        match w::str_ref(object.field("action")).map_err(|_| "invalidRequest")? {
            "create" => {
                let name = w::str_d(object.field("name")).map_err(|_| "invalidRequest")?;
                if !text(Some(&name)) {
                    return Err("invalidRequest");
                }
                SnapshotAction::Create {
                    name,
                    include_untracked: w::bool_d(object.field("includeUntracked"))
                        .map_err(|_| "invalidRequest")?,
                    keep_index: w::bool_d(object.field("keepIndex"))
                        .map_err(|_| "invalidRequest")?,
                }
            }
            "delete" => SnapshotAction::Delete(id()?),
            "branch" => {
                let branch = w::bytes_d(object.field("branch")).map_err(|_| "invalidRequest")?;
                if !bytes_text(Some(&branch)) || branch.is_empty() {
                    return Err("invalidRequest");
                }
                SnapshotAction::Branch(id()?, branch)
            }
            _ => return Err("invalidRequest"),
        },
    )
}

/// Worktrees live on the host: a worktree root must be a local path there, never another
/// computer's.
fn validate_extension(
    request: &gitlama_application::extensions::NativeExtensionMutationRequest,
) -> Result<(), Code> {
    if request
        .worktree_root
        .as_ref()
        .is_some_and(|root| root.remote.is_some())
        || !bytes_text(request.path.as_deref())
        || !text(request.pattern.as_ref())
        || !text(request.reference.as_ref())
    {
        return Err("invalidRequest");
    }
    Ok(())
}

fn bytes_text(value: Option<&[u8]>) -> bool {
    value.is_none_or(|value| value.len() <= TEXT_BYTES && !value.contains(&0))
}

fn valid_path(path: &[u8]) -> bool {
    !path.is_empty() && path.len() <= STAGE_PATH_BYTES && !path.contains(&0)
}

fn message_ok(value: Option<&String>) -> bool {
    message(value)
}

/// Removes a kept patch when execution ends, however it ends.
struct PatchFile(Option<std::path::PathBuf>);

impl Drop for PatchFile {
    fn drop(&mut self) {
        if let Some(file) = self.0.take() {
            let _ = std::fs::remove_file(file);
        }
    }
}

/// Removes patches an earlier helper left behind; a preview lives two minutes.
fn remove_stale_patches(directory: &std::path::Path) {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let stale = entry
            .metadata()
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age > PREVIEW_LIFETIME * 2);
        if stale {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

/// Records the evidence after Git ran. True when every piece is readable and equal to its
/// value before: the operation provably changed nothing.
fn record_after(family: Family, workspace: &Workspace, receipt: &mut Receipt) -> bool {
    let mut unchanged = true;
    for evidence in family.evidence() {
        let after = evidence.collect(workspace);
        let before = receipt.evidence.get(&format!("{}Before", evidence.key()));
        unchanged &= !after.is_null() && before == Some(&after);
        receipt
            .evidence
            .insert(format!("{}After", evidence.key()), after);
    }
    unchanged
}

/// Transfers that change refs on the remote server.
const fn updates_server(kind: NativeTransferKind) -> bool {
    matches!(
        kind,
        NativeTransferKind::Push
            | NativeTransferKind::PushTag
            | NativeTransferKind::DeleteTag
            | NativeTransferKind::DeleteBranch
    )
}

/// Failures that end a transfer before the server can update a ref: local preconditions,
/// authentication and host keys, or the server's own refusal.
fn refused_before_update(failure: Option<NativeTransferFailureKind>) -> bool {
    use NativeTransferFailureKind as Kind;
    matches!(
        failure,
        Some(
            Kind::InvalidRequest
                | Kind::DetachedHead
                | Kind::MissingUpstream
                | Kind::DirtyWorktree
                | Kind::ConflictedWorktree
                | Kind::Stale
                | Kind::Authentication
                | Kind::CredentialBrokerUnavailable
                | Kind::HostKey
                | Kind::Rejected
                | Kind::MissingGit
        )
    )
}

fn text(value: Option<&String>) -> bool {
    value.is_none_or(|value| value.len() <= TEXT_BYTES && !value.contains('\0'))
}

fn message(value: Option<&String>) -> bool {
    value.is_none_or(|value| value.len() <= MESSAGE_BYTES && !value.contains('\0'))
}

/// Branches, tags, upstreams, remotes, checkout and reset, previewed like on this computer.
fn validate_refs(request: &NativeRefMutationRequest) -> Result<(), Code> {
    if (request.kind == NativeRefMutationKind::Reset) != request.reset_mode.is_some()
        || ![
            request.name.as_ref(),
            request.second_name.as_ref(),
            request.target.as_ref(),
            request.url.as_ref(),
        ]
        .into_iter()
        .all(text)
        || !message(request.message.as_ref())
    {
        return Err("invalidRequest");
    }
    Ok(())
}

fn validate_stash(request: &NativeStashRequest) -> Result<(), Code> {
    let path_bytes: usize = request.paths.iter().map(Vec::len).sum();
    if request.paths.len() > STAGE_PATHS
        || path_bytes > STAGE_PATH_BYTES
        || request
            .paths
            .iter()
            .any(|path| path.is_empty() || path.contains(&0))
        || ![
            request.selector.as_ref(),
            request.object_id.as_ref(),
            request.target_branch.as_ref(),
        ]
        .into_iter()
        .all(text)
        || !message(request.message.as_ref())
    {
        return Err("invalidRequest");
    }
    Ok(())
}

fn validate_discard(request: &NativeDiscardRequest) -> Result<(), Code> {
    let path_bytes: usize = request.paths.iter().map(Vec::len).sum();
    if request.paths.len() > STAGE_PATHS
        || path_bytes > STAGE_PATH_BYTES
        || request.row_ids.len() > STAGE_ROWS
        || request
            .paths
            .iter()
            .any(|path| path.is_empty() || path.contains(&0))
        || request
            .row_ids
            .iter()
            .any(|row| row.len() > TEXT_BYTES || row.contains('\0'))
    {
        return Err("invalidRequest");
    }
    Ok(())
}

/// A compound pull may create/apply a stash only with both write families authorized.
fn require_pull_stash_capability(
    connection: &Connection,
    family: Family,
    request: &Value,
) -> Result<(), Code> {
    if family == Family::Transfer
        && request["stashBeforePull"].as_bool() == Some(true)
        && !connection.allows(crate::protocol::Capability::Stash)
    {
        return Err("writeNotPermitted");
    }
    Ok(())
}

fn validate_transfer(request: &NativeTransferRequest) -> Result<(), Code> {
    if ![request.remote.as_ref(), request.branch.as_ref()]
        .into_iter()
        .all(text)
    {
        return Err("invalidRequest");
    }
    Ok(())
}

fn validate_stage(request: &NativeStagingRequest) -> Result<(), Code> {
    let path_bytes: usize = request.paths.iter().map(Vec::len).sum();
    if request.paths.len() > STAGE_PATHS
        || path_bytes > STAGE_PATH_BYTES
        || request.row_ids.len() > STAGE_ROWS
        || request
            .paths
            .iter()
            .any(|path| path.is_empty() || path.contains(&0))
    {
        return Err("invalidRequest");
    }
    Ok(())
}

/// Commits, amends included. Skipped hooks and disabled signing are the user's explicit choice,
/// as on this computer; otherwise the remote environment's identity, hooks and signing policy
/// decide.
fn validate_commit(request: &NativeCommitRequest) -> Result<(), Code> {
    // The core's own rule, so a message is accepted here exactly when it is accepted on this
    // computer.
    if gitlama_application::commit_rules::valid_commit_message(
        &request.subject,
        &request.description,
        &request.coauthors,
        request.author.as_deref(),
    ) {
        Ok(())
    } else {
        Err("invalidRequest")
    }
}

#[cfg(test)]
mod tests {
    use super::{outcome_of, Family};
    use serde_json::json;

    #[test]
    fn an_uncertain_result_is_recorded_as_unknown_for_every_family() {
        for family in [
            Family::Stage,
            Family::Commit,
            Family::Refs,
            Family::Stash,
            Family::Discard,
            Family::History,
            Family::Rebase,
            Family::Restack,
            Family::Bisect,
            Family::Sequencer,
            Family::Snapshot,
            Family::SnapshotRestore,
            Family::Restore,
            Family::Patch,
            Family::Extension,
            Family::Transfer,
        ] {
            let result = json!({ "state": "outcomeUncertain" });
            assert_eq!(outcome_of(family, &result, true), "unknown");
            assert_eq!(outcome_of(family, &result, false), "unknown");
        }
    }

    #[test]
    #[allow(clippy::too_many_lines)]
    fn every_family_reports_the_cores_uncertain_state_as_unknown() {
        use gitlama_application::dto as core;
        use gitlama_application::wire::generated as g;
        let states = [
            (
                Family::Stage,
                g::enc_native_staging_execution_state(
                    &core::NativeStagingExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Commit,
                g::enc_native_commit_execution_state(
                    &core::NativeCommitExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Refs,
                g::enc_native_ref_mutation_execution_state(
                    &core::NativeRefMutationExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Stash,
                g::enc_native_stash_execution_state(
                    &core::NativeStashExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Transfer,
                g::enc_native_transfer_execution_state(
                    &core::NativeTransferExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Discard,
                g::enc_native_discard_execution_state(
                    &core::NativeDiscardExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::History,
                g::enc_native_history_mutation_execution_state(
                    &core::NativeHistoryMutationExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Rebase,
                g::enc_native_rebase_execution_state(
                    &core::NativeRebaseExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Restack,
                g::enc_native_restack_execution_state(
                    &core::NativeRestackExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Bisect,
                g::enc_native_bisect_execution_state(
                    &core::NativeBisectExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Snapshot,
                g::enc_native_named_snapshot_execution_state(
                    &core::NativeNamedSnapshotExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::SnapshotRestore,
                g::enc_native_named_snapshot_execution_state(
                    &core::NativeNamedSnapshotExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Restore,
                g::enc_native_restore_state(&core::NativeRestoreState::OutcomeUncertain),
            ),
            (
                Family::Sequencer,
                g::enc_native_conflict_continuation_state(
                    &core::NativeConflictContinuationState::OutcomeUncertain,
                ),
            ),
            (
                Family::Patch,
                g::enc_native_patch_apply_execution_state(
                    &core::NativePatchApplyExecutionState::OutcomeUncertain,
                ),
            ),
            (
                Family::Extension,
                g::enc_native_extension_mutation_state(
                    &core::NativeExtensionMutationState::OutcomeUncertain,
                ),
            ),
        ];
        for (family, state) in states {
            let result = json!({ "state": state });
            assert_eq!(outcome_of(family, &result, true), "unknown");
            assert_eq!(outcome_of(family, &result, false), "unknown");
        }
    }

    #[test]
    fn a_reconciled_warning_is_a_success_and_a_failure_depends_on_evidence() {
        let warning = json!({ "state": "reconciledWithWarning" });
        assert_eq!(outcome_of(Family::Snapshot, &warning, false), "succeeded");
        let failed = json!({ "state": "failed" });
        assert_eq!(outcome_of(Family::Patch, &failed, true), "failed");
        assert_eq!(outcome_of(Family::Patch, &failed, false), "unknown");
    }

    #[test]
    fn the_helper_admits_what_the_core_admits_for_staging() {
        use gitlama_application::dto::{
            NativeStagingRequest, NativeStagingScope, NativeStagingSide,
        };
        let request = |paths: usize| NativeStagingRequest {
            request_id: 1,
            side: NativeStagingSide::Unstaged,
            scope: NativeStagingScope::Files,
            paths: (0..paths)
                .map(|i| format!("file-{i}").into_bytes())
                .collect(),
            row_ids: Vec::new(),
        };
        // 200 paths stage on this computer, so they stage on a host too.
        assert_eq!(super::validate_stage(&request(200)), Ok(()));
        assert_eq!(
            super::validate_stage(&request(gitlama_application::wire::contract::STAGE_PATHS)),
            Ok(())
        );
        assert_eq!(
            super::validate_stage(&request(
                gitlama_application::wire::contract::STAGE_PATHS + 1
            )),
            Err("invalidRequest")
        );
    }
}
