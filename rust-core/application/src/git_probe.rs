//! Runs the shared read-only probes through the activity runner, so even small reads get
//! process-tree ownership, bounded output, a deadline and cancellation.
use crate::activity::allocate_activity_id;
use devmil_git::activity::{ActivityEvent, ActivityId};
use devmil_git::cancellation::Cancellation;
use devmil_git::loading::CommandExecutor;
use devmil_git::process::{
    ActivityGitRunner, GitProcessCommand, PrivateActivityResult, SemanticTimeout,
};
use std::time::Duration;

/// How long one probe may run.
pub(crate) const PROBE_DEADLINE: Duration = Duration::from_secs(30);

/// Runs probe commands privately: their output is parsed, not published. A publishing executor
/// still records each probe as an activity of the running operation.
pub(crate) struct ProbeExecutor<'a> {
    cancellation: Option<&'a dyn Cancellation>,
    publish: Option<&'a dyn Fn(ActivityEvent)>,
    record: Option<&'a mut dyn FnMut(ActivityId)>,
}

impl<'a> ProbeExecutor<'a> {
    pub(crate) const fn new(cancellation: Option<&'a dyn Cancellation>) -> Self {
        Self {
            cancellation,
            publish: None,
            record: None,
        }
    }

    /// Publishes each probe's activity to `publish` and reports its identifier to `record`.
    pub(crate) fn publishing(
        cancellation: Option<&'a dyn Cancellation>,
        publish: &'a dyn Fn(ActivityEvent),
        record: &'a mut dyn FnMut(ActivityId),
    ) -> Self {
        Self {
            cancellation,
            publish: Some(publish),
            record: Some(record),
        }
    }
}

impl CommandExecutor for ProbeExecutor<'_> {
    fn execute(&mut self, command: GitProcessCommand) -> PrivateActivityResult {
        let command = match SemanticTimeout::new(PROBE_DEADLINE, "git probe") {
            Ok(timeout) => command.semantic_timeout(timeout),
            Err(_) => command,
        };
        let id = allocate_activity_id();
        if let Some(record) = self.record.as_mut() {
            record(id);
        }
        let publish = self.publish;
        ActivityGitRunner::run_private(command, id, self.cancellation, &mut |event| {
            if let Some(publish) = publish {
                publish(event);
            }
        })
    }
}

/// Runs a shared probe in `worktree` and publishes it as an activity of `activity`.
pub(crate) fn run_published_probe<T>(
    activity: &crate::activity::ActivityStore,
    probe: impl FnOnce(&mut crate::git_probe::ProbeExecutor<'_>) -> T,
) -> T {
    let sink = activity.sink();
    let publish = |event| sink(event);
    let mut record = |_| {};
    probe(&mut crate::git_probe::ProbeExecutor::publishing(
        None,
        &publish,
        &mut record,
    ))
}
