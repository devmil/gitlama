//! A pull request review: the changed files with their provider patches,
//! review threads and checks, a review text with line comments kept as a
//! draft, and a review or check re-run submitted only after the person
//! authorizes the exact request.

use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::rt;
use gitlama_contract::hosting::NativeHostingConnection;
use gitlama_contract::hosting_review::{
    NativeHostingInlineDraft, NativeHostingReviewAction, NativeHostingReviewDraft,
    NativeHostingReviewFailure, NativeHostingReviewPage, NativeHostingReviewSubmitState,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::collections::BTreeMap;
use std::rc::Rc;

/// The draft key of a review.
pub fn draft_key(connection_id: &str, repository: &str, pull_request: u64) -> String {
    format!(
        "{}:{connection_id}{}:{repository}:{pull_request}",
        connection_id.len(),
        repository.len()
    )
}

/// The status letter of a provider patch.
pub fn diff_status(patch: &str) -> &'static str {
    let header = |marker: &str| patch.starts_with(marker) || patch.contains(&format!("\n{marker}"));
    if header("new file mode") {
        "A"
    } else if header("deleted file mode") {
        "D"
    } else if header("rename from") {
        "R"
    } else {
        "M"
    }
}

pub fn failure_name(failure: NativeHostingReviewFailure) -> &'static str {
    use NativeHostingReviewFailure as F;
    match failure {
        F::InvalidRequest => "invalidRequest",
        F::IntegrationDisabled => "integrationDisabled",
        F::CredentialMissing => "credentialMissing",
        F::CredentialUnreadable => "credentialUnreadable",
        F::CredentialExpired => "credentialExpired",
        F::Unauthorized => "unauthorized",
        F::PermissionDenied => "permissionDenied",
        F::RateLimited => "rateLimited",
        F::MalformedResponse => "malformedResponse",
        F::Unavailable => "unavailable",
        F::Canceled => "canceled",
        F::Unsupported => "unsupported",
        F::MovedBase => "movedBase",
        F::StaleAuthorization => "staleAuthorization",
        F::Uncertain => "uncertain",
        F::DraftStorage => "draftStorage",
    }
}

pub fn action_name(action: NativeHostingReviewAction) -> &'static str {
    match action {
        NativeHostingReviewAction::Comment => "comment",
        NativeHostingReviewAction::Approve => "approve",
        NativeHostingReviewAction::RequestChanges => "requestChanges",
    }
}

pub fn action_of(name: &str) -> NativeHostingReviewAction {
    match name {
        "approve" => NativeHostingReviewAction::Approve,
        "requestChanges" => NativeHostingReviewAction::RequestChanges,
        _ => NativeHostingReviewAction::Comment,
    }
}

/// Adds the rows of `next` to `current`, keeping each stable id once in
/// its first position.
fn merge<T: Clone>(current: &[T], next: &[T], id: impl Fn(&T) -> &str) -> Vec<T> {
    let mut order: Vec<String> = Vec::new();
    let mut rows: BTreeMap<String, T> = BTreeMap::new();
    for row in current.iter().chain(next) {
        let key = id(row).to_owned();
        if !rows.contains_key(&key) {
            order.push(key.clone());
        }
        rows.insert(key, row.clone());
    }
    order
        .into_iter()
        .filter_map(|key| rows.remove(&key))
        .collect()
}

#[derive(Clone, Debug)]
struct Review {
    connection_id: String,
    repository: String,
    number: u64,
    head_sha: String,
    page: Option<NativeHostingReviewPage>,
    selected: Option<String>,
    inline: Vec<NativeHostingInlineDraft>,
    action: NativeHostingReviewAction,
    body: String,
    failure: Option<NativeHostingReviewFailure>,
    loading: bool,
    busy: bool,
    completed: bool,
    /// Folders folded in the files tree.
    collapsed: std::collections::HashSet<String>,
}

/// The configured provider connections.
pub type Connections = Box<dyn Fn() -> Vec<NativeHostingConnection>>;

pub struct HostingReview {
    connections: Connections,
    prompts: Rc<Prompts>,
    notifier: Notifier,
    review: RefCell<Option<Review>>,
    /// Bumps with every opened review, so a late answer of a closed one is dropped.
    sequence: Cell<u64>,
}

impl HostingReview {
    pub fn new(connections: Connections, prompts: Rc<Prompts>, notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            connections,
            prompts,
            notifier,
            review: RefCell::new(None),
            sequence: Cell::new(0),
        })
    }

    fn changed(&self) {
        self.notifier.notify(Topics::HOSTING);
    }

    fn update(&self, sequence: u64, change: impl FnOnce(&mut Review)) {
        if sequence != self.sequence.get() {
            return;
        }
        if let Some(review) = self.review.borrow_mut().as_mut() {
            change(review);
        }
        self.changed();
    }

    fn connection(&self, id: &str) -> Result<NativeHostingConnection, NativeHostingReviewFailure> {
        (self.connections)()
            .into_iter()
            .find(|connection| connection.id == id && connection.enabled)
            .ok_or(NativeHostingReviewFailure::IntegrationDisabled)
    }

    /// Opens the review of pull request `number` at `head_sha`, with its
    /// saved draft when the draft was written for the same head.
    pub async fn open(
        &self,
        connection_id: String,
        repository: String,
        number: u64,
        head_sha: String,
    ) {
        let sequence = self.sequence.get() + 1;
        self.sequence.set(sequence);
        *self.review.borrow_mut() = Some(Review {
            connection_id: connection_id.clone(),
            repository: repository.clone(),
            number,
            head_sha: head_sha.clone(),
            page: None,
            selected: None,
            inline: Vec::new(),
            action: NativeHostingReviewAction::Comment,
            body: String::new(),
            failure: None,
            loading: true,
            busy: false,
            completed: false,
            collapsed: Default::default(),
        });
        self.changed();
        let connection = match self.connection(&connection_id) {
            Ok(connection) => connection,
            Err(failure) => {
                return self.update(sequence, |review| {
                    review.loading = false;
                    review.failure = Some(failure);
                });
            }
        };
        let key = draft_key(&connection_id, &repository, number);
        let (load, draft) = futures::join!(
            rt::blocking({
                let (repository, head_sha) = (repository.clone(), head_sha.clone());
                move || {
                    gitlama_core::api::hosting_review_load(
                        connection, repository, number, head_sha, None,
                    )
                }
            }),
            rt::blocking(move || gitlama_core::api::hosting_review_draft_load(key)),
        );
        self.update(sequence, |review| {
            review.loading = false;
            match (load.page, load.failure) {
                (Some(page), None) => {
                    review.selected = page.diffs.first().map(|diff| diff.stable_id.clone());
                    if let Some(draft) = draft.draft.filter(|draft| draft.head_sha == page.head_sha)
                    {
                        review.action = draft.action;
                        review.inline = draft.inline_comments;
                        review.body = draft.body;
                    }
                    review.page = Some(page);
                }
                (_, failure) => {
                    review.failure =
                        Some(failure.unwrap_or(NativeHostingReviewFailure::Unavailable))
                }
            }
        });
    }

    /// Shows an already loaded page (tests and development screenshots).
    pub fn show_page(&self, page: NativeHostingReviewPage) {
        let sequence = self.sequence.get() + 1;
        self.sequence.set(sequence);
        *self.review.borrow_mut() = Some(Review {
            connection_id: page.connection_id.clone(),
            repository: page.repository.clone(),
            number: page.pull_request,
            head_sha: page.head_sha.clone(),
            selected: page.diffs.first().map(|diff| diff.stable_id.clone()),
            page: Some(page),
            inline: Vec::new(),
            action: NativeHostingReviewAction::Comment,
            body: String::new(),
            failure: None,
            loading: false,
            busy: false,
            completed: false,
            collapsed: Default::default(),
        });
        self.changed();
    }

    /// Folds or unfolds folder `identity` of the files tree.
    pub fn toggle_folder(&self, identity: String) {
        let sequence = self.sequence.get();
        self.update(sequence, |review| {
            if !review.collapsed.remove(&identity) {
                review.collapsed.insert(identity);
            }
        });
    }

    /// Loads the next page of files, threads and checks.
    pub async fn load_more(&self) {
        let sequence = self.sequence.get();
        let Some((connection_id, repository, number, head_sha, next)) =
            self.review.borrow().as_ref().and_then(|review| {
                let page = review.page.as_ref()?;
                (!review.loading).then_some(())?;
                Some((
                    review.connection_id.clone(),
                    review.repository.clone(),
                    review.number,
                    page.head_sha.clone(),
                    page.next_page.clone()?,
                ))
            })
        else {
            return;
        };
        self.update(sequence, |review| {
            review.loading = true;
            review.failure = None;
        });
        let connection = match self.connection(&connection_id) {
            Ok(connection) => connection,
            Err(failure) => {
                return self.update(sequence, |review| {
                    review.loading = false;
                    review.failure = Some(failure);
                });
            }
        };
        let result = rt::blocking({
            let head_sha = head_sha.clone();
            move || {
                gitlama_core::api::hosting_review_load(
                    connection,
                    repository,
                    number,
                    head_sha,
                    Some(next),
                )
            }
        })
        .await;
        self.update(sequence, |review| {
            review.loading = false;
            let Some(current) = review.page.as_mut() else {
                return;
            };
            match (result.page, result.failure) {
                (Some(next), None)
                    if next.connection_id == current.connection_id
                        && next.repository == current.repository
                        && next.pull_request == current.pull_request
                        && next.head_sha == current.head_sha =>
                {
                    current.diffs = merge(&current.diffs, &next.diffs, |diff| &diff.stable_id);
                    current.threads =
                        merge(&current.threads, &next.threads, |thread| &thread.stable_id);
                    current.checks = merge(&current.checks, &next.checks, |check| &check.stable_id);
                    current.next_page = next.next_page;
                    current.incomplete = next.incomplete;
                    if review.selected.is_none() {
                        review.selected = current.diffs.first().map(|diff| diff.stable_id.clone());
                    }
                }
                (Some(_), None) => review.failure = Some(NativeHostingReviewFailure::MovedBase),
                (_, failure) => {
                    review.failure =
                        Some(failure.unwrap_or(NativeHostingReviewFailure::Unavailable))
                }
            }
        });
    }

    pub fn select(&self, stable_id: String) {
        let sequence = self.sequence.get();
        self.update(sequence, |review| review.selected = Some(stable_id));
    }

    pub fn set_action(&self, action: NativeHostingReviewAction) {
        let sequence = self.sequence.get();
        self.update(sequence, |review| review.action = action);
    }

    pub fn set_body(&self, body: String) {
        if let Some(review) = self.review.borrow_mut().as_mut() {
            review.body = body;
        }
    }

    /// Adds a line comment, or replaces the one on the same line.
    pub fn add_inline(&self, anchor_id: String, path: String, line: u64, body: String) {
        let sequence = self.sequence.get();
        self.update(sequence, |review| {
            let existing = review
                .inline
                .iter()
                .position(|draft| draft.path == path && draft.line == line);
            let stable_id = existing.map_or_else(
                || format!("draft:{anchor_id}"),
                |index| review.inline[index].stable_id.clone(),
            );
            if let Some(index) = existing {
                review.inline.remove(index);
            }
            review.inline.push(NativeHostingInlineDraft {
                stable_id,
                path,
                line,
                body,
            });
        });
    }

    pub fn remove_inline(&self, stable_id: String) {
        let sequence = self.sequence.get();
        self.update(sequence, |review| {
            review.inline.retain(|draft| draft.stable_id != stable_id)
        });
    }

    /// Keeps the review text and line comments for this pull request's head.
    pub async fn save_draft(&self) {
        let sequence = self.sequence.get();
        let Some(draft) = self.review.borrow().as_ref().and_then(|review| {
            let page = review.page.as_ref()?;
            Some(NativeHostingReviewDraft {
                key: draft_key(&review.connection_id, &review.repository, review.number),
                connection_id: review.connection_id.clone(),
                repository: review.repository.clone(),
                pull_request: review.number,
                head_sha: page.head_sha.clone(),
                action: review.action,
                body: review.body.clone(),
                inline_comments: review.inline.clone(),
                updated_at: 0,
            })
        }) else {
            return;
        };
        let result =
            rt::blocking(move || gitlama_core::api::hosting_review_draft_save(draft)).await;
        if let Some(failure) = result.failure {
            self.update(sequence, |review| review.failure = Some(failure));
        }
    }

    /// Previews the review, asks the person to authorize the exact request
    /// and submits it; a submitted review ends the workspace.
    pub async fn submit(&self) {
        let sequence = self.sequence.get();
        let Some(review) = self.review.borrow().clone().filter(|review| !review.busy) else {
            return;
        };
        self.update(sequence, |review| {
            review.busy = true;
            review.failure = None;
        });
        let outcome = self.submit_review(&review).await;
        match outcome {
            Ok(true) => {
                let key = draft_key(&review.connection_id, &review.repository, review.number);
                rt::blocking(move || gitlama_core::api::hosting_review_draft_delete(key)).await;
                self.update(sequence, |review| {
                    review.busy = false;
                    review.completed = true;
                });
            }
            Ok(false) => self.update(sequence, |review| review.busy = false),
            Err(failure) => {
                self.update(sequence, |review| {
                    review.busy = false;
                    review.failure = Some(failure);
                });
                self.save_draft().await;
            }
        }
    }

    async fn submit_review(&self, review: &Review) -> Result<bool, NativeHostingReviewFailure> {
        let connection = self.connection(&review.connection_id)?;
        let preview = rt::blocking({
            let (connection, review) = (connection.clone(), review.clone());
            move || {
                gitlama_core::api::hosting_review_preview(
                    connection,
                    review.repository,
                    review.number,
                    review.head_sha,
                    review.action,
                    review.body,
                    review.inline,
                )
            }
        })
        .await;
        let preview = match (preview.preview, preview.failure) {
            (Some(preview), None) => preview,
            (_, failure) => return Err(failure.unwrap_or(NativeHostingReviewFailure::Unavailable)),
        };
        let answer = self
            .prompts
            .ask(
                "confirmHostingReview",
                json!({
                    "number": review.number,
                    "action": action_name(review.action),
                    "inlineCount": review.inline.len(),
                    "commands": [preview.target, preview.payload],
                }),
            )
            .await;
        if answer != Some(Value::Bool(true)) {
            return Ok(false);
        }
        let result =
            rt::blocking(move || gitlama_core::api::hosting_review_submit(connection, preview))
                .await;
        match result.state {
            NativeHostingReviewSubmitState::Submitted
            | NativeHostingReviewSubmitState::Reconciled => Ok(true),
            _ => Err(result
                .failure
                .unwrap_or(NativeHostingReviewFailure::Unavailable)),
        }
    }

    /// Re-runs a check after the person authorizes the request, then reloads.
    pub async fn retry_check(&self, check_stable_id: String) {
        let sequence = self.sequence.get();
        let Some(review) = self.review.borrow().clone().filter(|review| !review.busy) else {
            return;
        };
        let Some(name) = review.page.as_ref().and_then(|page| {
            page.checks
                .iter()
                .find(|check| check.stable_id == check_stable_id)
                .map(|check| check.name.clone())
        }) else {
            return;
        };
        self.update(sequence, |review| review.busy = true);
        let outcome: Result<bool, NativeHostingReviewFailure> = async {
            let connection = self.connection(&review.connection_id)?;
            let preview = rt::blocking({
                let (connection, repository, head_sha, id) = (
                    connection.clone(),
                    review.repository.clone(),
                    review.head_sha.clone(),
                    check_stable_id.clone(),
                );
                move || {
                    gitlama_core::api::hosting_check_retry_preview(
                        connection, repository, head_sha, id,
                    )
                }
            })
            .await;
            let preview = match (preview.preview, preview.failure) {
                (Some(preview), None) => preview,
                (_, failure) => {
                    return Err(failure.unwrap_or(NativeHostingReviewFailure::Unavailable));
                }
            };
            let answer = self
                .prompts
                .ask(
                    "confirmCheckRetry",
                    json!({"name": name, "commands": [preview.target, preview.payload]}),
                )
                .await;
            if answer != Some(Value::Bool(true)) {
                return Ok(false);
            }
            let result = rt::blocking(move || {
                gitlama_core::api::hosting_check_retry_submit(
                    connection,
                    preview.authorization_id,
                    preview.repository,
                    preview.head_sha,
                    preview.check_stable_id,
                )
            })
            .await;
            match result.state {
                NativeHostingReviewSubmitState::Submitted => Ok(true),
                _ => Err(result
                    .failure
                    .unwrap_or(NativeHostingReviewFailure::Unavailable)),
            }
        }
        .await;
        self.update(sequence, |review| review.busy = false);
        match outcome {
            Ok(true) => {
                self.open(
                    review.connection_id,
                    review.repository,
                    review.number,
                    review.head_sha,
                )
                .await;
            }
            Ok(false) => {}
            Err(failure) => self.update(sequence, |review| review.failure = Some(failure)),
        }
    }

    /// Closes the workspace: a running request is canceled and unfinished
    /// work stays as a draft.
    pub async fn close(&self) {
        let Some(review) = self.review.borrow().clone() else {
            return;
        };
        if !review.completed && (!review.body.is_empty() || !review.inline.is_empty()) {
            self.save_draft().await;
        }
        self.sequence.set(self.sequence.get() + 1);
        *self.review.borrow_mut() = None;
        self.changed();
        rt::blocking(move || {
            gitlama_core::api::hosting_review_cancel(
                review.connection_id,
                review.repository,
                review.number,
            )
        })
        .await;
    }

    /// What the workspace shows, or null while no review is open.
    pub fn value(&self) -> Value {
        let review = self.review.borrow();
        let Some(review) = review.as_ref() else {
            return Value::Null;
        };
        let page = review.page.as_ref();
        let selected = page.and_then(|page| {
            page.diffs
                .iter()
                .find(|diff| Some(&diff.stable_id) == review.selected.as_ref())
        });
        json!({
            "number": review.number,
            "headSha": review.head_sha,
            "loading": review.loading,
            "busy": review.busy,
            "completed": review.completed,
            "failure": review.failure.map(failure_name),
            "hasPage": page.is_some(),
            "hasMore": page.is_some_and(|page| page.next_page.is_some()),
            "files": page.map_or_else(Vec::new, |page| page.diffs.iter().map(|diff| json!({
                "stableId": diff.stable_id,
                "path": diff.path,
                "status": diff_status(&diff.patch),
            })).collect()),
            // The same files as a tree of folders.
            "fileTree": page.map_or_else(Vec::new, |page| {
                crate::path_tree::flatten(page.diffs.iter(), |diff| diff.path.clone(), &review.collapsed, true, None)
                    .into_iter()
                    .map(|row| json!({
                        "directory": row.directory,
                        "identity": row.identity,
                        "label": row.label,
                        "depth": row.depth,
                        "expanded": row.directory && !review.collapsed.contains(&row.identity),
                        "stableId": row.item.map(|diff| diff.stable_id.clone()),
                        "status": row.item.map(|diff| diff_status(&diff.patch)),
                    }))
                    .collect()
            }),
            "selected": selected.map(|diff| json!({
                "stableId": diff.stable_id,
                "path": diff.path,
                "patch": diff.patch,
                "anchors": diff.anchors.iter().take(100).map(|anchor| json!({
                    "stableId": anchor.stable_id, "path": anchor.path, "line": anchor.line,
                })).collect::<Vec<_>>(),
            })),
            "threads": page.map_or_else(Vec::new, |page| page.threads.iter().map(|thread| {
                // A thread re-anchors on the first line of its file's diff.
                let anchor = page.diffs.iter()
                    .filter(|diff| Some(&diff.path) == thread.path.as_ref())
                    .flat_map(|diff| diff.anchors.iter())
                    .next();
                json!({
                    "stableId": thread.stable_id,
                    "author": thread.author,
                    "body": thread.body,
                    "outdated": thread.outdated,
                    "anchor": anchor.map(|anchor| json!({"stableId": anchor.stable_id, "path": anchor.path, "line": anchor.line})),
                })
            }).collect()),
            "checks": page.map_or_else(Vec::new, |page| page.checks.iter().map(|check| json!({
                "stableId": check.stable_id,
                "name": check.name,
                "state": crate::hosting::check_state_name(check.state),
                "detailsUrl": check.details_url,
            })).collect()),
            "action": action_name(review.action),
            "body": review.body,
            "inline": review.inline.iter().map(|draft| json!({
                "stableId": draft.stable_id, "path": draft.path, "line": draft.line, "body": draft.body,
            })).collect::<Vec<_>>(),
        })
    }
}

/// A review with one file, one outdated thread and one failing check, for
/// tests and development screenshots.
pub fn sample_page() -> NativeHostingReviewPage {
    use gitlama_contract::hosting::{NativeHostingCheck, NativeHostingCheckState};
    use gitlama_contract::hosting_review::{
        NativeHostingReviewAnchor, NativeHostingReviewDiff, NativeHostingReviewThread,
    };
    NativeHostingReviewPage {
        connection_id: "c".into(),
        repository: "o/r".into(),
        pull_request: 7,
        head_sha: "abc".into(),
        diffs: vec![NativeHostingReviewDiff {
            stable_id: "d1".into(),
            path: "src/a.rs".into(),
            patch: "@@ -1 +1 @@\n-a\n+b".into(),
            anchors: vec![NativeHostingReviewAnchor {
                stable_id: "a1".into(),
                path: "src/a.rs".into(),
                line: 1,
            }],
        }],
        threads: vec![NativeHostingReviewThread {
            stable_id: "t1".into(),
            path: Some("src/a.rs".into()),
            line: Some(1),
            anchor_id: None,
            author: "octo".into(),
            body: "Why?".into(),
            resolved: false,
            outdated: true,
        }],
        checks: vec![NativeHostingCheck {
            stable_id: "k1".into(),
            name: "build".into(),
            state: NativeHostingCheckState::Failing,
            conclusion: "failure".into(),
            details_url: None,
            updated_at: None,
        }],
        next_page: None,
        incomplete: false,
    }
}
#[cfg(test)]
mod tests {

    use super::*;

    #[test]
    fn draft_keys_frame_their_parts() {
        assert_eq!(draft_key("gh", "o/r", 7), "2:gh3:o/r:7");
    }

    #[test]
    fn patches_name_their_status() {
        assert_eq!(diff_status("new file mode 100644\n@@"), "A");
        assert_eq!(diff_status("diff\ndeleted file mode 100644"), "D");
        assert_eq!(diff_status("rename from a\nrename to b"), "R");
        assert_eq!(diff_status("@@ -1 +1 @@"), "M");
    }

    fn service() -> Rc<HostingReview> {
        let notifier = Notifier::default();
        HostingReview::new(
            Box::new(Vec::new),
            Rc::new(Prompts::new(notifier.clone())),
            notifier,
        )
    }

    #[test]
    fn a_shown_page_projects_files_threads_checks_and_drafts() {
        let review = service();
        review.show_page(super::sample_page());
        review.add_inline("a1".into(), "src/a.rs".into(), 1, "first".into());
        review.add_inline("a1".into(), "src/a.rs".into(), 1, "second".into());
        let value = review.value();
        assert_eq!(value["files"][0]["status"], "M");
        assert_eq!(value["selected"]["anchors"][0]["line"], 1);
        assert_eq!(value["threads"][0]["anchor"]["stableId"], "a1");
        assert_eq!(value["checks"][0]["state"], "failing");
        assert_eq!(
            value["inline"].as_array().unwrap().len(),
            1,
            "one comment per line"
        );
        assert_eq!(value["inline"][0]["body"], "second");
        review.remove_inline("draft:a1".into());
        assert!(review.value()["inline"].as_array().unwrap().is_empty());
    }

    #[test]
    fn merged_pages_keep_each_row_once() {
        let merged = merge(&["a", "b"], &["b", "c"], |value| value);
        assert_eq!(merged, ["a", "b", "c"]);
    }
}
