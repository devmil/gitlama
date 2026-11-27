//! The logbook (operation center) and the activity island: the
//! application's operations with Cancel, Retry and Dismiss, each entry's
//! command and output on demand, and the active repository's activity.

use crate::plumbing::Commands;
use gitlama_contract::activity::{NativeActivityRecord, NativeActivityStatus};
use gitlama_contract::dto::{
    NativeOperationCenterAction, NativeOperationCenterOrigin, NativeOperationCenterSnapshot,
    NativeOperationCenterState,
};
use gitlama_workbench::app::Services;
use gitlama_workbench::operations::{entry_key, present};
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

fn state_name(state: NativeOperationCenterState) -> &'static str {
    match state {
        NativeOperationCenterState::Running => "running",
        NativeOperationCenterState::Attention => "attention",
        NativeOperationCenterState::Warning => "warning",
        NativeOperationCenterState::Succeeded => "succeeded",
        NativeOperationCenterState::Failed => "failed",
        NativeOperationCenterState::Canceled => "canceled",
    }
}

fn action_name(action: NativeOperationCenterAction) -> &'static str {
    match action {
        NativeOperationCenterAction::Refresh => "refresh",
        NativeOperationCenterAction::Initialize => "initialize",
        NativeOperationCenterAction::Clone => "clone",
        NativeOperationCenterAction::Fetch => "fetch",
        NativeOperationCenterAction::Pull => "pull",
        NativeOperationCenterAction::Push => "push",
        NativeOperationCenterAction::Other => "other",
    }
}

fn status_name(status: NativeActivityStatus) -> &'static str {
    match status {
        NativeActivityStatus::Running => "running",
        NativeActivityStatus::Succeeded => "succeeded",
        NativeActivityStatus::Canceled => "canceled",
        NativeActivityStatus::Failed
        | NativeActivityStatus::TimedOut
        | NativeActivityStatus::LaunchError => "failed",
    }
}

/// A record's command and output (its stdout, then its stderr).
pub fn record_value(record: &NativeActivityRecord) -> Value {
    let mut output = Vec::new();
    if !record.stdout.is_empty() {
        output.push(String::from_utf8_lossy(&record.stdout).into_owned());
    }
    if !record.stderr.is_empty() {
        output.push(String::from_utf8_lossy(&record.stderr).into_owned());
    }
    json!({
        "id": record.id.to_string(),
        "executable": record.executable,
        "arguments": record.arguments.join(" "),
        "started": record.started_at_unix_ms,
        "status": status_name(record.status),
        "output": output.join("\n"),
    })
}

/// The logbook's rows: entries in center order, quiet background fetches
/// folded together; `label` names an entry's repository.
pub fn project(
    snapshot: &NativeOperationCenterSnapshot,
    services: &Services,
    label: impl Fn(u64, u64) -> Option<String>,
) -> Value {
    let rows: Vec<Value> = present(&snapshot.entries)
        .into_iter()
        .map(|(index, count)| {
            let entry = &snapshot.entries[index];
            json!({
                "key": entry_key(entry).to_string(),
                "session": entry.session_id.map(|session| session.to_string()),
                "count": count,
                "state": state_name(entry.state),
                "origin": match entry.origin {
                    NativeOperationCenterOrigin::User => "user",
                    NativeOperationCenterOrigin::Background => "background",
                },
                "action": action_name(entry.action),
                "repository": entry.session_id.map(|session| label(session, entry.generation).unwrap_or_else(|| format!("#{session}"))),
                "started": entry.started_at_unix_ms,
                "elapsed": entry.finished_at_unix_ms.map(|finished| finished.saturating_sub(entry.started_at_unix_ms)),
                "progress": entry.progress.as_ref().and_then(|progress| {
                    let total = progress.total.filter(|total| *total > 0)?;
                    Some(json!({"phase": progress.phase, "percent": (100.0 * progress.completed as f64 / total as f64).round() as u64}))
                }),
                "canCancel": services.operations.can_cancel(entry),
                "canRetry": entry.can_retry,
                "hasDetails": entry.has_details && entry.activity_id.is_some() && entry.session_id.is_some(),
            })
        })
        .collect();
    json!({
        "entries": rows,
        "running": snapshot.running_count,
        "failed": snapshot.failed_count,
        "warning": snapshot.warning_count,
        "attention": snapshot.attention_count,
    })
}

#[qobject(ConvertToCamelCase)]
mod operations_state {
    use super::*;

    #[derive(Default)]
    pub struct OperationsState {
        pub commands: Option<Commands>,
        /// {entries: [...], running, failed, warning, attention}.
        pub(crate) center: Value,
        /// The active repository's recent activity: [record, ...].
        pub(crate) activity: Value,
    }

    impl OperationsState {
        qproperty!("center", Member = center, Notify = center_changed);
        qproperty!("activity", Member = activity, Notify = activity_changed);

        #[qsignal]
        pub fn center_changed(&mut self);
        #[qsignal]
        pub fn activity_changed(&mut self);
        /// An entry's command and output arrived: `record` is null when it
        /// is unavailable, `expired` when it was evicted.
        #[qsignal]
        pub fn details_loaded(&mut self, key: String, record: Value, expired: bool);

        #[qslot]
        fn cancel(&self, key: String) {
            let Ok(key) = key.parse::<u64>() else { return };
            self.spawn(move |services| {
                let operations = Rc::clone(&services.operations);
                async move { operations.cancel(key).await }
            });
        }

        #[qslot]
        fn retry(&self, key: String) {
            let Ok(key) = key.parse::<u64>() else { return };
            self.spawn(move |services| {
                let operations = Rc::clone(&services.operations);
                async move { operations.retry(key).await }
            });
        }

        #[qslot]
        fn dismiss(&self, key: String) {
            let Ok(key) = key.parse::<u64>() else { return };
            self.spawn(move |services| {
                let operations = Rc::clone(&services.operations);
                async move { operations.dismiss(key).await }
            });
        }

        #[qslot]
        fn dismiss_all(&self) {
            self.spawn(|services| {
                let operations = Rc::clone(&services.operations);
                async move { operations.dismiss_all().await }
            });
        }

        /// Cancels (or retries) the newest entry that can; false when none.
        #[qslot]
        fn run_latest(&self, retry: bool) {
            self.with_services(move |services| {
                let operations = Rc::clone(&services.operations);
                if let Some(key) = operations.latest(retry) {
                    rt::spawn_detached(async move {
                        if retry {
                            operations.retry(key).await;
                        } else {
                            operations.cancel(key).await;
                        }
                    });
                }
            });
        }

        /// Loads an entry's command and output.
        #[qslot]
        fn load_details(&self, key: String) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Ok(numeric) = key.parse::<u64>() else {
                    return;
                };
                let snapshot = services.operations.current();
                let Some(entry) = snapshot
                    .entries
                    .iter()
                    .find(|entry| entry_key(entry) == numeric)
                    .cloned()
                else {
                    return;
                };
                let (Some(session), Some(activity)) = (entry.session_id, entry.activity_id) else {
                    return;
                };
                let calls = Rc::clone(&services.calls);
                let state = Rc::clone(&driver.operations);
                rt::spawn_detached(async move {
                    let result = calls
                        .repository_session_activity_record(session, entry.generation, activity)
                        .await;
                    let page = result.ok().and_then(|result| result.page);
                    let record = page
                        .as_ref()
                        .and_then(|page| page.records.iter().find(|record| record.id == activity));
                    let expired = record.is_none()
                        && page
                            .as_ref()
                            .and_then(|page| page.evicted_through_id)
                            .is_some_and(|through| activity <= through);
                    let value = record.map_or(Value::Null, record_value);
                    state.borrow_mut().details_loaded(key, value, expired);
                });
            });
        }

        /// Reads the active repository's recent activity.
        #[qslot]
        fn load_activity(&self) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let state = Rc::clone(&driver.operations);
                let Some(identity) = services.workspace.current().map(|session| session.identity)
                else {
                    let mut shown = state.borrow_mut();
                    shown.activity = json!([]);
                    shown.activity_changed();
                    return;
                };
                let calls = Rc::clone(&services.calls);
                rt::spawn_detached(async move {
                    let Ok(result) = calls
                        .repository_session_activity(identity.native_id, identity.generation, 64)
                        .await
                    else {
                        return;
                    };
                    let Some(page) = result.page else { return };
                    let records = Value::Array(page.records.iter().map(record_value).collect());
                    let mut shown = state.borrow_mut();
                    if shown.activity != records {
                        shown.activity = records;
                        shown.activity_changed();
                    }
                });
            });
        }
    }

    impl OperationsState {
        fn with_services(&self, action: impl FnOnce(&Services) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        action(&services);
                    }
                });
            }
        }

        fn spawn<F, Fut>(&self, start: F)
        where
            F: FnOnce(&Services) -> Fut + 'static,
            Fut: std::future::Future<Output = ()> + 'static,
        {
            self.with_services(move |services| rt::spawn_detached(start(services)));
        }
    }
}

pub use operations_state::OperationsState;
