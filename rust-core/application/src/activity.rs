//! Application-owned, bounded projection of shared command activity.
pub use gitlama_contract::activity::*;

use devmil_git::activity::{
    ActivityCommand, ActivityEvent, ActivityId, ActivityProgress, ActivityRecord, ActivityStatus,
    BoundedActivityBytes,
};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

pub const ACTIVITY_RECORD_CAPACITY: usize = 256;
pub const ACTIVITY_STREAM_BYTE_CAPACITY: usize = 64 * 1024;
pub const ACTIVITY_PAGE_CAPACITY: u32 = 64;

static NEXT_ACTIVITY_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Default)]
struct ActivityState {
    order: VecDeque<u64>,
    records: HashMap<u64, ActivityRecord>,
    evicted_through_id: Option<u64>,
}

#[derive(Clone, Default)]
pub struct ActivityStore {
    inner: Arc<Mutex<ActivityState>>,
}

impl ActivityStore {
    pub fn sink(&self) -> Arc<dyn Fn(ActivityEvent) + Send + Sync> {
        let store = self.clone();
        Arc::new(move |event| store.publish(event))
    }

    pub fn page(&self, maximum_records: u32) -> Option<NativeActivityPage> {
        if maximum_records == 0 || maximum_records > ACTIVITY_PAGE_CAPACITY {
            return None;
        }
        let state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let skip = state.order.len().saturating_sub(maximum_records as usize);
        let records = state
            .order
            .iter()
            .skip(skip)
            .filter_map(|id| state.records.get(id))
            .map(project_record)
            .collect();
        Some(NativeActivityPage {
            records,
            evicted_through_id: state.evicted_through_id,
        })
    }

    pub(crate) fn operation_records(&self) -> NativeActivityPage {
        let state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        NativeActivityPage {
            records: state
                .order
                .iter()
                .filter_map(|id| state.records.get(id))
                .map(project_record)
                .collect(),
            evicted_through_id: state.evicted_through_id,
        }
    }

    pub fn record(&self, id: u64) -> NativeActivityPage {
        let state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        NativeActivityPage {
            records: state
                .records
                .get(&id)
                .map(project_record)
                .into_iter()
                .collect(),
            evicted_through_id: state.evicted_through_id,
        }
    }

    fn publish(&self, event: ActivityEvent) {
        let mut state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match event {
            ActivityEvent::Created(record) => insert_record(&mut state, bounded_record(record)),
            ActivityEvent::Output { id, stream, bytes } => {
                if let Some(record) = state.records.get_mut(&id.get()) {
                    record.append_output(stream, &bytes, ACTIVITY_STREAM_BYTE_CAPACITY);
                }
            }
            ActivityEvent::Progress { id, progress } => {
                if let Some(record) = state.records.get_mut(&id.get()) {
                    record.set_progress(progress);
                }
            }
            ActivityEvent::Finished(record) => {
                let id = record.id.get();
                if let Some(existing) = state.records.get_mut(&id) {
                    *existing = bounded_record(record);
                } else {
                    insert_record(&mut state, bounded_record(record));
                }
            }
        }
    }
}

pub fn allocate_activity_id() -> ActivityId {
    loop {
        let value = NEXT_ACTIVITY_ID.fetch_add(1, Ordering::Relaxed);
        if let Ok(id) = ActivityId::new(value) {
            return id;
        }
    }
}

/// What an operation the application ran was for. A use case registers it where it allocates
/// the activity of a command that changes something; the operation center reads it instead of
/// guessing from the recorded arguments. Commands without an intent are background reads.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OperationIntent {
    Fetch,
    Pull,
    Push,
    Initialize,
    Clone,
    /// Any other change to a repository: staging, commits, refs, stashes, history rewrites,
    /// worktrees, submodules, custom commands.
    Change,
}

/// Who asked for an operation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OperationOrigin {
    User,
    /// The application, on its own: a periodic fetch.
    Background,
}

/// Registered intents, oldest first; bounded like the activity records they describe.
const OPERATION_INTENT_CAPACITY: usize = 4096;

#[derive(Default)]
struct OperationIntents {
    order: VecDeque<u64>,
    intents: HashMap<u64, (OperationIntent, OperationOrigin)>,
}

fn operation_intents() -> std::sync::MutexGuard<'static, OperationIntents> {
    static INTENTS: std::sync::OnceLock<Mutex<OperationIntents>> = std::sync::OnceLock::new();
    INTENTS
        .get_or_init(|| Mutex::new(OperationIntents::default()))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Allocates the activity of a command a use case runs for `intent`, on the user's behalf.
pub fn allocate_operation_id(intent: OperationIntent) -> ActivityId {
    allocate_operation_id_from(intent, OperationOrigin::User)
}

/// [`allocate_operation_id`] for an operation `origin` started.
pub fn allocate_operation_id_from(intent: OperationIntent, origin: OperationOrigin) -> ActivityId {
    let id = allocate_activity_id();
    let mut intents = operation_intents();
    intents.order.push_back(id.get());
    intents.intents.insert(id.get(), (intent, origin));
    while intents.order.len() > OPERATION_INTENT_CAPACITY {
        if let Some(oldest) = intents.order.pop_front() {
            intents.intents.remove(&oldest);
        }
    }
    id
}

/// The intent registered for the activity `id`, if a use case registered one.
pub fn operation_intent(id: u64) -> Option<(OperationIntent, OperationOrigin)> {
    operation_intents().intents.get(&id).copied()
}

pub(crate) fn next_activity_id() -> u64 {
    NEXT_ACTIVITY_ID.load(Ordering::Relaxed)
}

fn insert_record(state: &mut ActivityState, record: ActivityRecord) {
    let id = record.id.get();
    if !state.records.contains_key(&id) {
        state.order.push_back(id);
    }
    state.records.insert(id, record);
    while state.order.len() > ACTIVITY_RECORD_CAPACITY {
        if let Some(evicted) = state.order.pop_front() {
            state.records.remove(&evicted);
            state.evicted_through_id = Some(
                state
                    .evicted_through_id
                    .map_or(evicted, |previous| previous.max(evicted)),
            );
        }
    }
}

fn bounded_record(mut record: ActivityRecord) -> ActivityRecord {
    record.stdout = bounded_bytes(record.stdout, ACTIVITY_STREAM_BYTE_CAPACITY);
    record.stderr = bounded_bytes(record.stderr, ACTIVITY_STREAM_BYTE_CAPACITY);
    record
}

fn bounded_bytes(mut source: BoundedActivityBytes, limit: usize) -> BoundedActivityBytes {
    if source.bytes.len() > limit {
        source.bytes.truncate(limit);
        source.truncated = true;
    }
    source
}

fn project_record(record: &ActivityRecord) -> NativeActivityRecord {
    let (status, exit_code) = match &record.status {
        ActivityStatus::Running => (NativeActivityStatus::Running, None),
        ActivityStatus::Succeeded { exit_code } => {
            (NativeActivityStatus::Succeeded, Some(*exit_code))
        }
        ActivityStatus::Failed { exit_code } => (NativeActivityStatus::Failed, *exit_code),
        ActivityStatus::Canceled { exit_code } => (NativeActivityStatus::Canceled, *exit_code),
        ActivityStatus::TimedOut { exit_code, .. } => (NativeActivityStatus::TimedOut, *exit_code),
        ActivityStatus::LaunchError { .. } => (NativeActivityStatus::LaunchError, None),
    };
    NativeActivityRecord {
        id: record.id.get(),
        executable: safe_executable(&record.command),
        arguments: record
            .command
            .arguments
            .iter()
            .map(|argument| argument.display.clone())
            .collect(),
        started_at_unix_ms: record.started_at_unix_ms,
        finished_at_unix_ms: record.finished_at_unix_ms,
        status,
        exit_code,
        stdout: record.stdout.bytes.clone(),
        stdout_total_bytes: record.stdout.total_bytes,
        stdout_truncated: record.stdout.truncated,
        stderr: record.stderr.bytes.clone(),
        stderr_total_bytes: record.stderr.total_bytes,
        stderr_truncated: record.stderr.truncated,
        progress: record.last_progress.as_ref().map(project_progress),
    }
}

fn safe_executable(command: &ActivityCommand) -> String {
    std::path::Path::new(&command.executable)
        .file_name()
        .and_then(std::ffi::OsStr::to_str)
        .unwrap_or("git")
        .to_owned()
}

fn project_progress(progress: &ActivityProgress) -> NativeActivityProgress {
    NativeActivityProgress {
        phase: progress.phase.clone(),
        completed: progress.completed,
        total: progress.total,
        unit: progress.unit.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use devmil_git::activity::{ActivityArgument, ActivityCommand, ActivityStream};
    use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};

    fn record(id: u64) -> ActivityRecord {
        ActivityRecord::started(
            ActivityId::new(id).unwrap(),
            ActivityCommand {
                executable: "/private/tooling/git".into(),
                arguments: vec![ActivityArgument {
                    display: "[REDACTED]".into(),
                    redacted: true,
                    native_lossless: true,
                }],
                environment: Vec::new(),
                working_directory: Some("/private/repository".into()),
                stdin_bytes: 0,
            },
            10,
        )
    }

    #[test]
    fn bounds_output_and_does_not_project_private_process_fields() {
        let store = ActivityStore::default();
        let mut finished = record(1);
        finished.append_output(
            ActivityStream::Stdout,
            &vec![b'x'; ACTIVITY_STREAM_BYTE_CAPACITY + 10],
            ACTIVITY_STREAM_BYTE_CAPACITY + 10,
        );
        finished.finish(ActivityStatus::Succeeded { exit_code: 0 }, 20);
        store.publish(ActivityEvent::Finished(finished));
        let page = store.page(1).unwrap();
        let projected = &page.records[0];
        assert_eq!(projected.executable, "git");
        assert_eq!(projected.arguments, ["[REDACTED]"]);
        assert_eq!(projected.stdout.len(), ACTIVITY_STREAM_BYTE_CAPACITY);
        assert!(projected.stdout_truncated);
        let debug = format!("{projected:?}");
        assert!(!debug.contains("/private/repository"));
        assert!(!debug.contains("/private/tooling"));
    }

    #[test]
    fn evicts_old_details_but_preserves_the_link_boundary() {
        let store = ActivityStore::default();
        for id in 1..=(ACTIVITY_RECORD_CAPACITY as u64 + 2) {
            store.publish(ActivityEvent::Created(record(id)));
        }
        let page = store.page(ACTIVITY_PAGE_CAPACITY).unwrap();
        assert_eq!(page.evicted_through_id, Some(2));
        assert_eq!(page.records.last().unwrap().id, 258);
        assert!(page.records.iter().all(|entry| entry.id > 2));
    }

    #[test]
    fn loads_retained_record_outside_recent_activity_page() {
        let store = ActivityStore::default();
        for id in 1..=65 {
            store.publish(ActivityEvent::Created(record(id)));
        }
        assert!(store
            .page(ACTIVITY_PAGE_CAPACITY)
            .unwrap()
            .records
            .iter()
            .all(|entry| entry.id != 1));
        assert_eq!(store.record(1).records[0].id, 1);
        assert!(store.record(66).records.is_empty());
    }

    #[test]
    fn rejects_unbounded_page_requests() {
        let store = ActivityStore::default();
        assert!(store.page(0).is_none());
        assert!(store.page(ACTIVITY_PAGE_CAPACITY + 1).is_none());
    }

    #[test]
    fn shared_redaction_survives_application_storage_and_projection() {
        const SENTINEL: &str = "https://user:private-token@example.invalid/repository";
        let store = ActivityStore::default();
        let forwarded = store.clone();
        let command = GitProcessCommand::git("git")
            .arg(ProcessArgument::visible("--gitlama-invalid-option"))
            .arg(ProcessArgument::redacted(SENTINEL, "[REDACTED]"));
        let mut sink = move |event| forwarded.publish(event);

        ActivityGitRunner::run(command, ActivityId::new(900).unwrap(), None, &mut sink);

        let projected = format!("{:?}", store.page(1).unwrap());
        assert!(!projected.contains("private-token"));
        assert!(!projected.contains("user:"));
        assert!(projected.contains("[REDACTED]"));
    }

    #[test]
    fn launch_failure_detail_is_not_part_of_the_bridge_model() {
        let store = ActivityStore::default();
        let mut failed = record(901);
        failed.finish(
            ActivityStatus::LaunchError {
                message: "private launch path and sentinel credential".into(),
            },
            20,
        );
        store.publish(ActivityEvent::Finished(failed));

        let projected = format!("{:?}", store.page(1).unwrap());
        assert!(!projected.contains("private launch path"));
        assert!(!projected.contains("sentinel credential"));
        assert!(projected.contains("LaunchError"));
    }
}
