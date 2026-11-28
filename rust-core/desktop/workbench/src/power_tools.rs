//! Power tools of the active repository: a search through every commit's changes and
//! the repository's statistics, both polled jobs, and bisect, whose every
//! step is confirmed with its Git command first.

use crate::backend::SessionCalls;
use crate::navigator::Navigator;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::rt;
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::power_tools::{
    NativeBisectAction, NativeBisectExecutionState, NativeBisectState,
    NativeDiffContentSearchResult, NativeDiffSearchOptions, NativeDiffSearchScope,
    NativePowerJobStartResult, NativePowerJobState, NativeRepositoryStatisticsResult,
    NativeSearchCompleteness,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

const POLL: Duration = Duration::from_millis(50);
const MAXIMUM_COMMITS: u32 = 10_000;

/// The panel's state.
#[derive(Clone, Debug, Default)]
pub struct Panel {
    pub search_running: bool,
    pub search: Option<NativeDiffContentSearchResult>,
    pub statistics_running: bool,
    pub statistics: Option<NativeRepositoryStatisticsResult>,
    pub bisect: Option<NativeBisectState>,
    pub bisect_busy: bool,
    pub failed: bool,
    /// The references bisect can start from, with their commits.
    pub choices: Vec<(String, String)>,
}

pub struct PowerTools {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    settings: Rc<SettingsService>,
    navigator: Rc<Navigator>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    panel: RefCell<Panel>,
    /// Which panel shown owns the state; a panel that closes after another
    /// opened leaves it alone.
    owner: Cell<u64>,
    search_run: Cell<u64>,
    statistics_run: Cell<u64>,
}

/// A commit ID shortened for reading; anything else unchanged.
pub fn short_commit(commit: &str) -> String {
    let hex = (40..=64).contains(&commit.len())
        && commit
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'));
    if hex {
        commit[..10].to_owned()
    } else {
        commit.to_owned()
    }
}

fn action_name(action: NativeBisectAction) -> &'static str {
    match action {
        NativeBisectAction::Start => "start",
        NativeBisectAction::Good => "good",
        NativeBisectAction::Bad => "bad",
        NativeBisectAction::Skip => "skip",
        NativeBisectAction::Reset => "reset",
    }
}

pub fn bisect_action(name: &str) -> Option<NativeBisectAction> {
    Some(match name {
        "start" => NativeBisectAction::Start,
        "good" => NativeBisectAction::Good,
        "bad" => NativeBisectAction::Bad,
        "skip" => NativeBisectAction::Skip,
        "reset" => NativeBisectAction::Reset,
        _ => return None,
    })
}

/// The references a bisect field offers, each with the commit it names:
/// HEAD, local branches, remote-tracking branches, then tags.
/// Every reference a reference field offers:
/// HEAD, branches, remote branches, tags and the loaded commits, each as
/// {value, description, icon}.
pub fn reference_choice_values(
    snapshot: &gitlama_contract::dto::NativeRepositorySnapshot,
    commits: &[gitlama_contract::dto::NativeHistoryRow],
) -> Value {
    use gitlama_contract::dto::NativeHistoryNodeShape;
    let text = |bytes: &[u8]| String::from_utf8_lossy(bytes).into_owned();
    let refs = &snapshot.refs;
    let mut choices = vec![json!({"value": "HEAD", "description": "", "icon": "locate"})];
    choices.extend(refs.branches.iter().map(|branch| {
        json!({"value": text(&branch.name), "description": branch.target, "icon": "branch"})
    }));
    for remote in &refs.remotes {
        let prefix = text(&remote.name);
        choices.extend(remote.branches.iter().map(|branch| {
            json!({
                "value": format!("{prefix}/{}", text(&branch.name)),
                "description": branch.target,
                "icon": "cloud",
            })
        }));
    }
    choices.extend(
        refs.tags
            .iter()
            .map(|tag| json!({"value": text(&tag.name), "description": tag.target, "icon": "tag"})),
    );
    choices.extend(
        commits
            .iter()
            .filter(|row| {
                !matches!(
                    row.shape,
                    NativeHistoryNodeShape::Wip | NativeHistoryNodeShape::WipConflict
                )
            })
            .map(|row| {
                json!({
                    "value": row.object_id,
                    "description": text(&row.subject),
                    "icon": "git-commit-horizontal",
                })
            }),
    );
    Value::Array(choices)
}

pub fn reference_choices(
    snapshot: &gitlama_contract::dto::NativeRepositorySnapshot,
) -> Vec<(String, String)> {
    let text = |bytes: &[u8]| String::from_utf8_lossy(bytes).into_owned();
    let refs = &snapshot.refs;
    let head = snapshot
        .status
        .as_ref()
        .and_then(|status| status.head_object_id.clone());
    head.map(|head| ("HEAD".to_owned(), head))
        .into_iter()
        .chain(
            refs.branches
                .iter()
                .map(|branch| (text(&branch.name), branch.target.clone())),
        )
        .chain(refs.remotes.iter().flat_map(|remote| {
            let prefix = text(&remote.name);
            remote.branches.iter().map(move |branch| {
                (
                    format!("{prefix}/{}", String::from_utf8_lossy(&branch.name)),
                    branch.target.clone(),
                )
            })
        }))
        .chain(
            refs.tags
                .iter()
                .map(|tag| (text(&tag.name), tag.target.clone())),
        )
        .collect()
}

/// The commit `value` names: a listed reference's target, else `value`.
pub fn resolve_reference(choices: &[(String, String)], value: &str) -> String {
    let value = value.trim();
    choices
        .iter()
        .find(|(name, _)| name == value)
        .map_or_else(|| value.to_owned(), |(_, target)| target.clone())
}

enum Job<T> {
    Done(T),
    Superseded,
    Failed,
}

impl PowerTools {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        settings: Rc<SettingsService>,
        navigator: Rc<Navigator>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            settings,
            navigator,
            prompts,
            notices,
            notifier,
            panel: RefCell::new(Panel::default()),
            owner: Cell::new(0),
            search_run: Cell::new(0),
            statistics_run: Cell::new(0),
        })
    }

    pub fn panel(&self) -> Panel {
        self.panel.borrow().clone()
    }

    fn update(&self, change: impl FnOnce(&mut Panel)) {
        change(&mut self.panel.borrow_mut());
        self.notifier.notify(Topics::OPERATIONS);
    }

    fn session(&self) -> Option<(u64, u64)> {
        self.workspace
            .current()
            .map(|session| (session.identity.native_id, session.identity.generation))
    }

    fn stop_jobs(&self) {
        self.search_run.set(self.search_run.get() + 1);
        self.statistics_run.set(self.statistics_run.get() + 1);
    }

    /// A panel opened: it starts empty and reads the bisect state.
    pub async fn open(&self, owner: u64) {
        self.owner.set(owner);
        self.stop_jobs();
        let choices = self
            .workspace
            .current()
            .map(|session| reference_choices(&session.snapshot))
            .unwrap_or_default();
        self.update(|panel| {
            *panel = Panel {
                choices,
                ..Panel::default()
            }
        });
        let Some((session, generation)) = self.session() else {
            return;
        };
        let result = self
            .calls
            .repository_session_bisect_state(session, generation)
            .await;
        if self.owner.get() != owner {
            return;
        }
        self.update(|panel| match result {
            Ok(result) if result.failure.is_none() && result.state.is_some() => {
                panel.bisect = result.state
            }
            _ => panel.failed = true,
        });
    }

    /// The panel `owner` closed: its jobs stop.
    pub fn close(&self, owner: u64) {
        if self.owner.get() == owner {
            self.stop_jobs();
            self.update(|panel| *panel = Panel::default());
        }
    }

    /// Polls the job `start` began until it ends or `run` is superseded,
    /// then cancels it.
    async fn poll<T, P>(
        &self,
        session: u64,
        generation: u64,
        started: Result<NativePowerJobStartResult, ()>,
        run: &Cell<u64>,
        expected: u64,
        poll: impl Fn(u64) -> P,
        state: impl Fn(&T) -> NativePowerJobState,
    ) -> Job<T>
    where
        P: std::future::Future<Output = Result<T, ()>>,
    {
        let token = match started {
            Ok(NativePowerJobStartResult {
                token: Some(token),
                failure: None,
            }) => token,
            _ => {
                return if run.get() == expected {
                    Job::Failed
                } else {
                    Job::Superseded
                };
            }
        };
        loop {
            if run.get() != expected {
                let _ = self
                    .calls
                    .repository_session_power_job_cancel(session, generation, token)
                    .await;
                return Job::Superseded;
            }
            match poll(token).await {
                Ok(result) if state(&result) == NativePowerJobState::Pending => {
                    rt::sleep(POLL).await
                }
                Ok(result) => {
                    return if run.get() == expected {
                        Job::Done(result)
                    } else {
                        Job::Superseded
                    };
                }
                Err(()) => {
                    return if run.get() == expected {
                        Job::Failed
                    } else {
                        Job::Superseded
                    };
                }
            }
        }
    }

    pub async fn search(&self, query: String, case_sensitive: bool, current_branch: bool) {
        if query.trim().is_empty() || self.panel.borrow().search_running {
            return;
        }
        let Some((session, generation)) = self.session() else {
            return;
        };
        let run = self.search_run.get() + 1;
        self.search_run.set(run);
        self.update(|panel| {
            panel.search_running = true;
            panel.search = None;
            panel.failed = false;
        });
        let options = NativeDiffSearchOptions {
            query,
            maximum_commits: MAXIMUM_COMMITS,
            case_sensitive,
            scope: if current_branch {
                NativeDiffSearchScope::CurrentBranch
            } else {
                NativeDiffSearchScope::AllRefs
            },
            other_refs: self
                .settings
                .with(|document| document.appearance.history_other_refs),
        };
        let started = self
            .calls
            .repository_session_diff_content_search_start_configured(session, generation, options)
            .await
            .map_err(|_| ());
        let calls = Rc::clone(&self.calls);
        let job = self
            .poll(
                session,
                generation,
                started,
                &self.search_run,
                run,
                |token| {
                    let calls = Rc::clone(&calls);
                    async move {
                        calls
                            .repository_session_diff_content_search_poll(session, generation, token)
                            .await
                            .map_err(|_| ())
                    }
                },
                |result: &NativeDiffContentSearchResult| result.state,
            )
            .await;
        match job {
            Job::Superseded => {}
            Job::Failed => self.update(|panel| {
                panel.search_running = false;
                panel.failed = true;
            }),
            Job::Done(result) => self.update(|panel| {
                panel.search_running = false;
                panel.failed = result.state == NativePowerJobState::Failed;
                panel.search = Some(result);
            }),
        }
    }

    pub fn cancel_search(&self) {
        if self.panel.borrow().search_running {
            self.search_run.set(self.search_run.get() + 1);
            self.update(|panel| panel.search_running = false);
        }
    }

    pub async fn statistics(&self) {
        if self.panel.borrow().statistics_running {
            return;
        }
        let Some((session, generation)) = self.session() else {
            return;
        };
        let run = self.statistics_run.get() + 1;
        self.statistics_run.set(run);
        self.update(|panel| {
            panel.statistics_running = true;
            panel.statistics = None;
            panel.failed = false;
        });
        let started = self
            .calls
            .repository_session_statistics_start(session, generation)
            .await
            .map_err(|_| ());
        let calls = Rc::clone(&self.calls);
        let job = self
            .poll(
                session,
                generation,
                started,
                &self.statistics_run,
                run,
                |token| {
                    let calls = Rc::clone(&calls);
                    async move {
                        calls
                            .repository_session_statistics_poll(session, generation, token)
                            .await
                            .map_err(|_| ())
                    }
                },
                |result: &NativeRepositoryStatisticsResult| result.state,
            )
            .await;
        match job {
            Job::Superseded => {}
            Job::Failed => self.update(|panel| {
                panel.statistics_running = false;
                panel.failed = true;
            }),
            Job::Done(result) => self.update(|panel| {
                panel.statistics_running = false;
                panel.failed = result.state == NativePowerJobState::Failed;
                panel.statistics = Some(result);
            }),
        }
    }

    /// One bisect step: its command is previewed and confirmed, then run.
    pub async fn bisect(&self, action: NativeBisectAction, good: String, bad: String) {
        if self.panel.borrow().bisect_busy {
            return;
        }
        let Some((session, generation)) = self.session() else {
            return;
        };
        self.update(|panel| {
            panel.bisect_busy = true;
            panel.failed = false;
        });
        let (good, bad) = match action {
            NativeBisectAction::Start => {
                let choices = self
                    .workspace
                    .current()
                    .map(|session| reference_choices(&session.snapshot))
                    .unwrap_or_default();
                (
                    Some(resolve_reference(&choices, &good)),
                    Some(resolve_reference(&choices, &bad)),
                )
            }
            _ => (None, None),
        };
        let preview = match self
            .calls
            .repository_session_bisect_preview(session, generation, action, good, bad)
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                _ => {
                    return self.update(|panel| {
                        panel.bisect_busy = false;
                        panel.failed = true;
                    });
                }
            },
            Err(_) => {
                return self.update(|panel| {
                    panel.bisect_busy = false;
                    panel.failed = true;
                });
            }
        };
        let command = std::iter::once("git".to_owned())
            .chain(preview.arguments.iter().cloned())
            .collect::<Vec<_>>()
            .join(" ");
        let answer = self
            .prompts
            .ask(
                "confirmBisect",
                json!({"action": action_name(action), "command": command}),
            )
            .await;
        if answer != Some(Value::Bool(true)) {
            let _ = self
                .calls
                .repository_session_bisect_cancel_preview(session, generation, preview.token)
                .await;
            return self.update(|panel| panel.bisect_busy = false);
        }
        let result = self
            .calls
            .repository_session_bisect_execute(session, generation, preview.token)
            .await;
        if let Some(session) = self.workspace.current() {
            let _ = self.workspace.refresh_if_open(session.identity).await;
        }
        match result {
            Ok(result) => {
                if result.state == NativeBisectExecutionState::OutcomeUncertain {
                    self.notices.error("mutationOutcomeUncertain", Value::Null);
                }
                self.update(|panel| {
                    panel.bisect_busy = false;
                    if result.bisect.is_some() {
                        panel.bisect = result.bisect;
                    }
                    panel.failed = !matches!(
                        result.state,
                        NativeBisectExecutionState::Completed
                            | NativeBisectExecutionState::OutcomeUncertain
                    );
                });
            }
            Err(_) => self.update(|panel| {
                panel.bisect_busy = false;
                panel.failed = true;
            }),
        }
    }

    /// Shows a found commit in History.
    pub async fn reveal(&self, commit: String) {
        self.navigator.show_commit(commit, None, true, false).await;
    }
}

/// The panel as the presentation shows it.
pub fn panel_value(panel: &Panel) -> Value {
    let search = panel.search.as_ref().map(|search| {
        json!({
            "examined": search.examined_commits,
            "completeness": match search.completeness {
                Some(NativeSearchCompleteness::CommitLimitReached) => "commits",
                Some(NativeSearchCompleteness::ResultLimitReached) => "results",
                _ => "complete",
            },
            "matches": search.matches.iter().map(|found| json!({
                "commit": found.commit,
                "short": short_commit(&found.commit),
                "summary": found.summary,
            })).collect::<Vec<_>>(),
        })
    });
    let statistics = panel.statistics.as_ref().map(|statistics| {
        json!({
            "commits": statistics.commit_count,
            "branches": statistics.local_branch_count,
            "tags": statistics.tag_count,
            "changedFiles": statistics.changed_path_count,
            "incomplete": statistics.incomplete,
        })
    });
    let bisect = panel.bisect.as_ref().map(|bisect| {
        json!({
            "active": bisect.active,
            "current": bisect.current.as_deref().map(short_commit),
            "steps": bisect.timeline.len(),
            "remaining": bisect.remaining_steps.unwrap_or(0),
        })
    });
    json!({
        "searchRunning": panel.search_running,
        "statisticsRunning": panel.statistics_running,
        "bisectBusy": panel.bisect_busy,
        "busy": panel.search_running || panel.statistics_running || panel.bisect_busy,
        "failed": panel.failed,
        "search": search,
        "statistics": statistics,
        "bisect": bisect,
        "names": panel.choices.iter().map(|(name, _)| name).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commit_ids_shorten_for_reading() {
        assert_eq!(short_commit(&"a".repeat(40)), "aaaaaaaaaa");
        assert_eq!(short_commit("HEAD~2"), "HEAD~2");
        assert_eq!(short_commit(&"A".repeat(40)), "A".repeat(40));
    }

    #[test]
    fn bisect_actions_round_trip() {
        for name in ["start", "good", "bad", "skip", "reset"] {
            assert_eq!(action_name(bisect_action(name).unwrap()), name);
        }
        assert!(bisect_action("run").is_none());
    }

    #[test]
    fn references_resolve_to_their_commits() {
        let choices = vec![
            ("HEAD".to_owned(), "a".repeat(40)),
            ("main".to_owned(), "b".repeat(40)),
        ];
        assert_eq!(resolve_reference(&choices, " main "), "b".repeat(40));
        assert_eq!(resolve_reference(&choices, "HEAD"), "a".repeat(40));
        assert_eq!(resolve_reference(&choices, &"c".repeat(40)), "c".repeat(40));
    }

    #[test]
    fn an_empty_panel_has_nothing_to_show() {
        let value = panel_value(&Panel::default());
        assert_eq!(value["busy"], false);
        assert!(value["search"].is_null());
        assert!(value["bisect"].is_null());
    }
}
