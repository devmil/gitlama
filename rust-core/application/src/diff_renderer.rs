//! Contained plain-text diff renderer processes.
pub use gitlama_contract::diff_renderer::*;

use crate::activity::{allocate_activity_id, ActivityStore};
use crate::domain::path_identity::native_path;
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument, SemanticTimeout};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

/// Checks the stored diff renderer section.
pub(crate) fn validate_settings(
    renderer: Option<&NativeDiffRendererSettings>,
) -> Result<(), &'static str> {
    if renderer.is_some_and(|renderer| {
        renderer.id.is_empty()
            || renderer.id.len() > 80
            || renderer.title.is_empty()
            || renderer.title.len() > 256
            || renderer.id.chars().any(char::is_control)
            || renderer.title.chars().any(char::is_control)
            || renderer.arguments.len() > 64
            || renderer
                .arguments
                .iter()
                .any(|value| value.contains('\0') || value.len() > 16 * 1024)
    }) {
        return Err("diff_renderer");
    }
    Ok(())
}

pub const MAX_RENDERER_INPUT_BYTES: usize = 8 * 1024 * 1024;
const MAX_RENDERER_OUTPUT_BYTES: usize = 64 * 1024;
const DISCOVERY_OUTPUT_BYTES: usize = 4 * 1024;
const PREVIEW_CAPACITY: usize = 8;
const PROTOCOL: &str = "gitlama-diff-renderer-v1";

struct Preview {
    definition: NativeDiffRendererDefinition,
    executable: PathBuf,
    worktree: PathBuf,
    request_id: u64,
    input: Vec<u8>,
    receiver: Option<Receiver<ThreadResult>>,
}

struct ThreadResult {
    title: String,
    text: Option<String>,
    activity_ids: Vec<String>,
    failure: Option<NativeDiffRendererFailureKind>,
}

static REGISTRY: OnceLock<Mutex<PreviewStore<Preview>>> = OnceLock::new();

fn lock_registry() -> std::sync::MutexGuard<'static, PreviewStore<Preview>> {
    crate::preview_store::lock(
        REGISTRY.get_or_init(|| Mutex::new(PreviewStore::new(PREVIEW_CAPACITY))),
    )
}

pub(crate) fn preview(
    session_id: u64,
    request_id: u64,
    worktree: PathBuf,
    input: Vec<u8>,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    let executable = match validate(&definition) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    if input.len() > MAX_RENDERER_INPUT_BYTES {
        return preview_failure(NativeDiffRendererFailureKind::InputTooLarge);
    }
    let input_bytes = input.len() as u64;
    let token = lock_registry().issue(
        session_id,
        Preview {
            definition: definition.clone(),
            executable: executable.clone(),
            worktree,
            request_id,
            input,
            receiver: None,
        },
    );
    let preview = NativeDiffRendererPreview {
        token,
        title: definition.title.clone(),
        executable: executable.to_string_lossy().into_owned(),
        capability_arguments: definition
            .arguments
            .iter()
            .cloned()
            .chain(["--gitlama-capabilities".to_owned()])
            .collect(),
        arguments: definition
            .arguments
            .iter()
            .cloned()
            .chain(["--gitlama-render=text/plain".to_owned()])
            .collect(),
        protocol: PROTOCOL.to_owned(),
        media_type: "text/plain".to_owned(),
        input_bytes,
        output_limit_bytes: MAX_RENDERER_OUTPUT_BYTES as u64,
        timeout_seconds: 5,
    };
    NativeDiffRendererPreviewResult {
        preview: Some(preview),
        failure: None,
    }
}

pub(crate) fn validate_definition(
    definition: NativeDiffRendererDefinition,
    worktree: PathBuf,
    activity: ActivityStore,
) -> NativeDiffRendererPreviewResult {
    let executable = match validate(&definition) {
        Ok(value) => value,
        Err(kind) => return preview_failure(kind),
    };
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut result = ActivityGitRunner::run_private(
        command(
            &definition,
            &executable,
            "--gitlama-capabilities",
            Duration::from_secs(2),
            DISCOVERY_OUTPUT_BYTES,
        )
        .current_dir(worktree),
        allocate_activity_id(),
        Some(&cancellation),
        &mut publish,
    );
    if let Err(kind) = classify(
        &result.activity.status,
        result.stdout.truncated || result.stderr.truncated,
    ) {
        return preview_failure(kind);
    }
    if result.stdout.take_bytes().as_slice() != format!("{PROTOCOL}\nmedia=text/plain\n").as_bytes()
    {
        return preview_failure(NativeDiffRendererFailureKind::InvalidCapability);
    }
    NativeDiffRendererPreviewResult {
        preview: Some(NativeDiffRendererPreview {
            token: 0,
            title: definition.title,
            executable: executable.to_string_lossy().into_owned(),
            capability_arguments: definition
                .arguments
                .iter()
                .cloned()
                .chain(["--gitlama-capabilities".to_owned()])
                .collect(),
            arguments: definition
                .arguments
                .into_iter()
                .chain(["--gitlama-render=text/plain".to_owned()])
                .collect(),
            protocol: PROTOCOL.to_owned(),
            media_type: "text/plain".to_owned(),
            input_bytes: 0,
            output_limit_bytes: DISCOVERY_OUTPUT_BYTES as u64,
            timeout_seconds: 2,
        }),
        failure: None,
    }
}

pub(crate) fn execute(
    session_id: u64,
    token: u64,
    current_request_id: u64,
    activity: ActivityStore,
) -> NativeDiffRendererResult {
    let mut registry = lock_registry();
    let Some(owned) = registry.get_mut(session_id, token) else {
        return fallback(NativeDiffRendererFailureKind::Stale);
    };
    if owned.value.request_id != current_request_id || owned.running {
        return fallback(NativeDiffRendererFailureKind::Stale);
    }
    owned.running = true;
    let preview = &mut owned.value;
    let definition = preview.definition.clone();
    let executable = preview.executable.clone();
    let worktree = preview.worktree.clone();
    let input = preview.input.clone();
    let cancellation = Arc::clone(&owned.cancellation);
    let (sender, receiver) = mpsc::sync_channel(1);
    owned.value.receiver = Some(receiver);
    std::thread::spawn(move || {
        let result = run(
            definition,
            executable,
            worktree,
            input,
            cancellation,
            activity,
        );
        let _ = sender.send(result);
    });
    pending()
}

pub(crate) fn request_id(session_id: u64, token: u64) -> Option<u64> {
    lock_registry()
        .get(session_id, token)
        .map(|owned| owned.value.request_id)
}

pub(crate) fn poll(session_id: u64, token: u64) -> NativeDiffRendererResult {
    let mut registry = lock_registry();
    let Some(owned) = registry.get(session_id, token) else {
        return fallback(NativeDiffRendererFailureKind::Stale);
    };
    let Some(receiver) = owned.value.receiver.as_ref() else {
        return fallback(NativeDiffRendererFailureKind::Stale);
    };
    let result = match receiver.try_recv() {
        Ok(result) => result,
        Err(TryRecvError::Empty) => return pending(),
        Err(TryRecvError::Disconnected) => {
            registry.finish(session_id, token);
            return fallback(NativeDiffRendererFailureKind::ProcessFailed);
        }
    };
    registry.finish(session_id, token);
    if let Some(kind) = result.failure {
        return NativeDiffRendererResult {
            state: if kind == NativeDiffRendererFailureKind::Canceled {
                NativeDiffRendererState::Canceled
            } else {
                NativeDiffRendererState::Fallback
            },
            title: Some(result.title),
            text: None,
            accessibility_text: None,
            activity_ids: result.activity_ids,
            failure: Some(NativeDiffRendererFailure { kind }),
        };
    }
    NativeDiffRendererResult {
        state: NativeDiffRendererState::Ready,
        title: Some(result.title),
        accessibility_text: result.text.clone(),
        text: result.text,
        activity_ids: result.activity_ids,
        failure: None,
    }
}

/// Cancels and drops a preview or a running renderer; its result is never collected.
pub(crate) fn cancel(session_id: u64, token: u64) -> bool {
    let mut registry = lock_registry();
    let Some(owned) = registry.get(session_id, token) else {
        return false;
    };
    owned.cancellation.store(true, Ordering::Release);
    registry.finish(session_id, token);
    true
}

pub(crate) fn dismiss_session(session_id: u64) {
    lock_registry().discard_session(session_id);
}

fn validate(
    definition: &NativeDiffRendererDefinition,
) -> Result<PathBuf, NativeDiffRendererFailureKind> {
    if definition.id.is_empty()
        || definition.id.len() > 80
        || definition.title.is_empty()
        || definition.title.len() > 256
        || definition.id.chars().any(char::is_control)
        || definition.title.chars().any(char::is_control)
        || definition.arguments.len() > 64
        || definition
            .arguments
            .iter()
            .any(|value| value.contains('\0') || value.len() > 16 * 1024)
    {
        return Err(NativeDiffRendererFailureKind::InvalidDefinition);
    }
    let executable = native_path(&definition.executable)
        .ok_or(NativeDiffRendererFailureKind::InvalidDefinition)?;
    if !executable.is_absolute() || !executable.is_file() {
        return Err(NativeDiffRendererFailureKind::Unavailable);
    }
    Ok(executable)
}

fn run(
    definition: NativeDiffRendererDefinition,
    executable: PathBuf,
    worktree: PathBuf,
    input: Vec<u8>,
    cancellation: Arc<AtomicBool>,
    activity: ActivityStore,
) -> ThreadResult {
    let mut ids = Vec::new();
    let discovery = command(
        &definition,
        &executable,
        "--gitlama-capabilities",
        Duration::from_secs(2),
        DISCOVERY_OUTPUT_BYTES,
    )
    .current_dir(&worktree);
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut discovered = ActivityGitRunner::run_private(
        discovery,
        allocate_activity_id(),
        Some(cancellation.as_ref()),
        &mut publish,
    );
    ids.push(discovered.activity.id.get().to_string());
    if let Err(kind) = classify(
        &discovered.activity.status,
        discovered.stdout.truncated || discovered.stderr.truncated,
    ) {
        return thread_failure(definition.title, ids, kind);
    }
    let capability = discovered.stdout.take_bytes();
    if capability.as_slice() != format!("{PROTOCOL}\nmedia=text/plain\n").as_bytes() {
        return thread_failure(
            definition.title,
            ids,
            NativeDiffRendererFailureKind::InvalidCapability,
        );
    }
    let render = command(
        &definition,
        &executable,
        "--gitlama-render=text/plain",
        Duration::from_secs(5),
        MAX_RENDERER_OUTPUT_BYTES,
    )
    .current_dir(worktree)
    .stdin_bytes(input);
    let mut rendered = ActivityGitRunner::run_private(
        render,
        allocate_activity_id(),
        Some(cancellation.as_ref()),
        &mut publish,
    );
    ids.push(rendered.activity.id.get().to_string());
    if let Err(kind) = classify(
        &rendered.activity.status,
        rendered.stdout.truncated || rendered.stderr.truncated,
    ) {
        return thread_failure(definition.title, ids, kind);
    }
    let bytes = rendered.stdout.take_bytes();
    let Ok(text) = String::from_utf8(bytes) else {
        return thread_failure(
            definition.title,
            ids,
            NativeDiffRendererFailureKind::InvalidCapability,
        );
    };
    let text = inert_text(&text);
    ThreadResult {
        title: definition.title,
        text: Some(text),
        activity_ids: ids,
        failure: None,
    }
}

fn command(
    definition: &NativeDiffRendererDefinition,
    executable: &Path,
    mode: &'static str,
    timeout: Duration,
    output_limit: usize,
) -> GitProcessCommand {
    GitProcessCommand::new(executable.as_os_str())
        .args(
            definition
                .arguments
                .iter()
                .map(|value| ProcessArgument::redacted(value, "[RENDERER_ARGUMENT]")),
        )
        .arg(ProcessArgument::visible(mode))
        .output_limit(output_limit)
        .semantic_timeout(
            SemanticTimeout::new(timeout, "diff renderer").expect("constant timeout is valid"),
        )
        .redact_output()
}

fn classify(status: &ActivityStatus, truncated: bool) -> Result<(), NativeDiffRendererFailureKind> {
    if truncated {
        return Err(NativeDiffRendererFailureKind::OutputTooLarge);
    }
    match status {
        ActivityStatus::Succeeded { .. } => Ok(()),
        ActivityStatus::Canceled { .. } => Err(NativeDiffRendererFailureKind::Canceled),
        ActivityStatus::TimedOut { .. } => Err(NativeDiffRendererFailureKind::TimedOut),
        ActivityStatus::LaunchError { .. } => Err(NativeDiffRendererFailureKind::LaunchFailed),
        _ => Err(NativeDiffRendererFailureKind::ProcessFailed),
    }
}

fn inert_text(source: &str) -> String {
    let mut output = String::with_capacity(source.len());
    for character in source.chars() {
        match character {
            '\n' | '\t' => output.push(character),
            value if value.is_control() => {
                use std::fmt::Write as _;
                let _ = write!(output, "\\u{{{:x}}}", u32::from(value));
            }
            value => output.push(value),
        }
    }
    output
}

fn thread_failure(
    title: String,
    activity_ids: Vec<String>,
    kind: NativeDiffRendererFailureKind,
) -> ThreadResult {
    ThreadResult {
        title,
        text: None,
        activity_ids,
        failure: Some(kind),
    }
}

fn preview_failure(kind: NativeDiffRendererFailureKind) -> NativeDiffRendererPreviewResult {
    NativeDiffRendererPreviewResult {
        preview: None,
        failure: Some(NativeDiffRendererFailure { kind }),
    }
}

fn pending() -> NativeDiffRendererResult {
    NativeDiffRendererResult {
        state: NativeDiffRendererState::Pending,
        title: None,
        text: None,
        accessibility_text: None,
        activity_ids: Vec::new(),
        failure: None,
    }
}

fn fallback(kind: NativeDiffRendererFailureKind) -> NativeDiffRendererResult {
    NativeDiffRendererResult {
        state: NativeDiffRendererState::Fallback,
        title: None,
        text: None,
        accessibility_text: None,
        activity_ids: Vec::new(),
        failure: Some(NativeDiffRendererFailure { kind }),
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::domain::path_identity::native_path_identity;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::process::{Command, Stdio};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::thread;
    use std::time::{Duration, Instant};

    static NEXT_TEST_ID: AtomicU64 = AtomicU64::new(10_000);

    struct Fixture {
        path: PathBuf,
        session_id: u64,
    }

    impl Fixture {
        fn new() -> Self {
            let session_id = NEXT_TEST_ID.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "gitlama-renderer-{}-{session_id}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self { path, session_id }
        }

        fn definition(&self, source: &str) -> NativeDiffRendererDefinition {
            let executable = self.path.join("renderer.sh");
            fs::write(&executable, source).unwrap();
            let mut permissions = fs::metadata(&executable).unwrap().permissions();
            permissions.set_mode(0o700);
            fs::set_permissions(&executable, permissions).unwrap();
            NativeDiffRendererDefinition {
                id: "test-renderer".to_owned(),
                title: "Test renderer".to_owned(),
                executable: native_path_identity(&executable),
                arguments: vec!["literal argument; never shell-evaluated".to_owned()],
            }
        }

        fn start(
            &self,
            definition: NativeDiffRendererDefinition,
            input: &[u8],
            activity: ActivityStore,
        ) -> (u64, NativeDiffRendererResult) {
            let result = preview(
                self.session_id,
                77,
                self.path.clone(),
                input.to_vec(),
                definition,
            );
            let preview = result
                .preview
                .unwrap_or_else(|| panic!("{:?}", result.failure));
            let started = execute(self.session_id, preview.token, 77, activity);
            assert_eq!(started.state, NativeDiffRendererState::Pending);
            (preview.token, started)
        }

        fn await_result(&self, token: u64, timeout: Duration) -> NativeDiffRendererResult {
            let deadline = Instant::now() + timeout;
            loop {
                let result = poll(self.session_id, token);
                if result.state != NativeDiffRendererState::Pending {
                    return result;
                }
                assert!(Instant::now() < deadline, "renderer did not settle");
                thread::sleep(Duration::from_millis(10));
            }
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            dismiss_session(self.session_id);
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn script(render: &str) -> String {
        format!(
            "#!/bin/sh\nmode=''\nfor argument do mode=$argument; done\ncase \"$mode\" in\n  --gitlama-capabilities) printf 'gitlama-diff-renderer-v1\\nmedia=text/plain\\n' ;;\n  --gitlama-render=text/plain) {render} ;;\n  *) exit 64 ;;\nesac\n"
        )
    }

    fn process_exists(pid: u32) -> bool {
        Command::new("kill")
            .args(["-0", &pid.to_string()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|status| status.success())
    }

    #[test]
    fn renderer_is_plain_text_bounded_private_and_accessible() {
        let fixture = Fixture::new();
        let activity = ActivityStore::default();
        let definition = fixture.definition(&script(
            "cat; printf '<script>import QtQuick</script>\\001'",
        ));
        let validation =
            validate_definition(definition.clone(), fixture.path.clone(), activity.clone());
        let validated = validation.preview.unwrap();
        assert_eq!(validated.media_type, "text/plain");
        assert_eq!(
            validated.capability_arguments.last().unwrap(),
            "--gitlama-capabilities"
        );
        assert_eq!(
            validated.arguments.last().unwrap(),
            "--gitlama-render=text/plain"
        );

        let (token, _) = fixture.start(definition, b"+literal input\n", activity.clone());
        let result = fixture.await_result(token, Duration::from_secs(3));
        assert_eq!(result.state, NativeDiffRendererState::Ready);
        let text = result.text.unwrap();
        assert_eq!(result.accessibility_text.as_deref(), Some(text.as_str()));
        assert!(text.contains("<script>import QtQuick</script>"));
        assert!(text.ends_with("\\u{1}"));
        let records = activity.operation_records().records;
        assert_eq!(records.len(), 3);
        assert!(records.iter().all(|record| {
            !record
                .stdout
                .windows(b"literal input".len())
                .any(|value| value == b"literal input")
                && !record
                    .stdout
                    .windows(b"<script>".len())
                    .any(|value| value == b"<script>")
                && !record
                    .stderr
                    .windows(b"literal input".len())
                    .any(|value| value == b"literal input")
        }));
        assert!(records.iter().all(|record| {
            record.arguments.iter().all(|argument| {
                argument == "[RENDERER_ARGUMENT]" || argument.starts_with("--gitlama-")
            })
        }));
    }

    #[test]
    fn renderer_crash_oversize_and_malformed_output_fail_closed() {
        let cases = [
            ("exit 23", NativeDiffRendererFailureKind::ProcessFailed),
            (
                "head -c 70000 /dev/zero | tr '\\000' x",
                NativeDiffRendererFailureKind::OutputTooLarge,
            ),
        ];
        for (render, expected) in cases {
            let fixture = Fixture::new();
            let definition = fixture.definition(&script(render));
            let (token, _) = fixture.start(definition, b"input", ActivityStore::default());
            let result = fixture.await_result(token, Duration::from_secs(3));
            assert_eq!(result.state, NativeDiffRendererState::Fallback);
            assert_eq!(result.failure.unwrap().kind, expected);
        }

        let fixture = Fixture::new();
        fs::write(fixture.path.join("invalid-utf8"), [0xff]).unwrap();
        let definition = fixture.definition(&script("cat invalid-utf8"));
        let (token, _) = fixture.start(definition, b"input", ActivityStore::default());
        let result = fixture.await_result(token, Duration::from_secs(3));
        assert_eq!(result.state, NativeDiffRendererState::Fallback);
        assert_eq!(
            result.failure.unwrap().kind,
            NativeDiffRendererFailureKind::InvalidCapability
        );

        let fixture = Fixture::new();
        let malformed = fixture
            .definition("#!/bin/sh\nprintf 'gitlama-diff-renderer-v1\\nmedia=text/html\\n'\n");
        let failure =
            validate_definition(malformed, fixture.path.clone(), ActivityStore::default())
                .failure
                .unwrap();
        assert_eq!(
            failure.kind,
            NativeDiffRendererFailureKind::InvalidCapability
        );
    }

    #[test]
    fn stalled_renderer_times_out() {
        let fixture = Fixture::new();
        let definition = fixture.definition(&script("sleep 20"));
        let (token, _) = fixture.start(definition, b"input", ActivityStore::default());
        let result = fixture.await_result(token, Duration::from_secs(8));
        assert_eq!(result.state, NativeDiffRendererState::Fallback);
        assert_eq!(
            result.failure.unwrap().kind,
            NativeDiffRendererFailureKind::TimedOut
        );
    }

    #[test]
    fn dismiss_session_reaps_renderer_and_its_child() {
        let fixture = Fixture::new();
        let parent_file = fixture.path.join("parent.pid");
        let child_file = fixture.path.join("child.pid");
        let render = format!(
            "sleep 20 & child=$!; printf '%s' $$ > '{}'; printf '%s' $child > '{}'; wait $child",
            parent_file.display(),
            child_file.display()
        );
        let definition = fixture.definition(&script(&render));
        let (_token, _) = fixture.start(definition, b"input", ActivityStore::default());
        let marker_deadline = Instant::now() + Duration::from_secs(3);
        while (!parent_file.exists() || !child_file.exists()) && Instant::now() < marker_deadline {
            thread::sleep(Duration::from_millis(10));
        }
        let parent = fs::read_to_string(&parent_file)
            .unwrap()
            .parse::<u32>()
            .unwrap();
        let child = fs::read_to_string(&child_file)
            .unwrap()
            .parse::<u32>()
            .unwrap();
        dismiss_session(fixture.session_id);
        let deadline = Instant::now() + Duration::from_secs(3);
        while (process_exists(parent) || process_exists(child)) && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(20));
        }
        assert!(!process_exists(parent));
        assert!(!process_exists(child));
    }
}

crate::family_failures!(NativeDiffRendererFailureKind, "diffRenderer", {
    InvalidDefinition => InvalidRequest,
    Unavailable => Unavailable,
    InvalidCapability => InvalidRequest,
    InputTooLarge => TooLarge,
    OutputTooLarge => TooLarge,
    LaunchFailed => Unavailable,
    ProcessFailed => Git,
    TimedOut => TimedOut,
    Canceled => Canceled,
    Stale => Stale,
});
