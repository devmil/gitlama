//! Resolving the conflicts of a paused merge, rebase, cherry-pick or revert. One session per
//! repository session, so unsaved choices survive switching tabs and files.

use crate::backend::SessionCalls;
use crate::changes::ChangesService;
use crate::conflict_draft::{MergeDraft, has_conflict_markers, marker_count, string};
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::session::SessionIdentity;
use crate::workspace::WorkspaceService;
use gitlama_contract::conflict::{
    NativeConflictContinuationState, NativeConflictFailureKind, NativeConflictFile,
    NativeConflictFileKind, NativeConflictOperationKind, NativeConflictRegionChoice,
    NativeConflictSequencerAction, NativeConflictSide, NativeConflictSideChoice,
    NativeConflictSnapshot, NativeConflictSnapshotResult,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

/// How a conflicted file was resolved in this step of the operation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Resolution {
    Deleted,
    Current,
    Incoming,
    Merged,
    External,
}

impl Resolution {
    pub fn name(self) -> &'static str {
        match self {
            Self::Deleted => "deleted",
            Self::Current => "current",
            Self::Incoming => "incoming",
            Self::Merged => "merged",
            Self::External => "external",
        }
    }
}

fn side_of(file: &NativeConflictFile, choice: NativeConflictSideChoice) -> &NativeConflictSide {
    match choice {
        NativeConflictSideChoice::Current => &file.current,
        NativeConflictSideChoice::Incoming => &file.incoming,
    }
}

/// What choosing the whole `side` of `file` does to it.
pub fn side_resolution(file: &NativeConflictFile, side: NativeConflictSideChoice) -> Resolution {
    match (side, side_of(file, side).present) {
        (_, false) => Resolution::Deleted,
        (NativeConflictSideChoice::Current, true) => Resolution::Current,
        (NativeConflictSideChoice::Incoming, true) => Resolution::Incoming,
    }
}

/// Which sides have the file.
pub fn presence(file: &NativeConflictFile) -> &'static str {
    match (
        file.ancestor.present,
        file.current.present,
        file.incoming.present,
    ) {
        (true, false, false) => "bothDeleted",
        (false, true, false) => "addedCurrent",
        (true, true, false) => "deletedIncoming",
        (false, false, true) => "addedIncoming",
        (true, false, true) => "deletedCurrent",
        (false, true, true) => "bothAdded",
        (true, true, true) => "bothPresent",
        _ => "unknown",
    }
}

fn has_bom(bytes: &[u8]) -> bool {
    bytes.starts_with(&[0xef, 0xbb, 0xbf])
}

/// How the two sides differ.
pub fn content_difference(file: &NativeConflictFile) -> &'static str {
    if !file.current.present || !file.incoming.present {
        return "missingSide";
    }
    let (Some(left), Some(right)) = (&file.current.content, &file.incoming.content) else {
        return "unavailable";
    };
    if left == right {
        return "identical";
    }
    if file.kind != NativeConflictFileKind::Text {
        return "content";
    }
    let decode = |bytes: &[u8]| -> Option<String> {
        let text = std::str::from_utf8(if has_bom(bytes) { &bytes[3..] } else { bytes }).ok()?;
        Some(format!(
            "{}{text}",
            if has_bom(bytes) { "\u{feff}" } else { "" }
        ))
    };
    let (Some(a), Some(b)) = (decode(left), decode(right)) else {
        return "unavailable";
    };
    let endings = |value: &str| value.replace("\r\n", "\n").replace('\r', "\n");
    if endings(&a) == endings(&b) {
        return "lineEndings";
    }
    let without_final = |value: &str| -> String {
        value
            .strip_suffix("\r\n")
            .or_else(|| value.strip_suffix('\n'))
            .or_else(|| value.strip_suffix('\r'))
            .unwrap_or(value)
            .to_owned()
    };
    if without_final(&a) == without_final(&b) {
        return "finalNewline";
    }
    let without_bom = |value: &str| value.strip_prefix('\u{feff}').unwrap_or(value).to_owned();
    if without_bom(&a) == without_bom(&b) {
        return "byteOrderMark";
    }
    let compact = |value: &str| {
        value
            .chars()
            .filter(|ch| !ch.is_whitespace())
            .collect::<String>()
    };
    if compact(&a) == compact(&b) {
        return "whitespace";
    }
    "content"
}

/// One side's index-entry facts for the details disclosure.
fn entry(side: &NativeConflictSide, size_known: bool) -> Value {
    if !side.present {
        return json!({"present": false});
    }
    let mut facts = json!({
        "present": true,
        "type": match side.mode {
            Some(0o100644) => "regular",
            Some(0o100755) => "executable",
            Some(0o120000) => "symlink",
            Some(0o160000) => "submodule",
            Some(0o040000) => "directory",
            _ => "unknown",
        },
        "mode": side.mode.map(|mode| format!("{mode:06o}")),
        "bytes": size_known.then_some(side.byte_count),
    });
    let Some(bytes) = &side.content else {
        return facts;
    };
    if bytes.contains(&0) || std::str::from_utf8(bytes).is_err() {
        return facts;
    }
    let (mut lf, mut crlf, mut cr) = (0, 0, 0);
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'\r' if bytes.get(index + 1) == Some(&b'\n') => {
                crlf += 1;
                index += 1;
            }
            b'\r' => cr += 1,
            b'\n' => lf += 1,
            _ => {}
        }
        index += 1;
    }
    let kinds: Vec<&str> = [(lf, "LF"), (crlf, "CRLF"), (cr, "CR")]
        .into_iter()
        .filter(|(count, _)| *count > 0)
        .map(|(_, name)| name)
        .collect();
    facts["endings"] = json!(match kinds.len() {
        0 => "none",
        1 => kinds[0],
        _ => "mixed",
    });
    facts["finalNewline"] = json!(
        bytes
            .last()
            .is_some_and(|last| *last == b'\n' || *last == b'\r')
    );
    facts["bom"] = json!(has_bom(bytes));
    facts
}

/// The details of `file`.
pub fn details(file: &NativeConflictFile) -> Value {
    let modes: std::collections::HashSet<u32> = [&file.ancestor, &file.current, &file.incoming]
        .iter()
        .filter(|side| side.present)
        .filter_map(|side| side.mode)
        .chain(file.result_present.then_some(file.result_mode).flatten())
        .collect();
    let working = NativeConflictSide {
        present: file.result_present,
        mode: file.result_mode,
        content: file.result.clone(),
        byte_count: file.result.as_ref().map_or(0, |result| result.len() as u64),
    };
    json!({
        "presence": presence(file),
        "difference": content_difference(file),
        "modeDiffers": modes.len() > 1,
        "ancestor": entry(&file.ancestor, true),
        "current": entry(&file.current, true),
        "incoming": entry(&file.incoming, true),
        "working": entry(&working, file.result.is_some()),
    })
}

/// The shown file's unsaved resolution: its region choices, the edited
/// text and a whole side chosen but not yet saved, for file version
/// `fingerprint`.
#[derive(Clone, Debug)]
pub struct FileDraft {
    pub fingerprint: u64,
    pub text: Vec<u16>,
    pub draft: Option<MergeDraft>,
    pub side: Option<NativeConflictSideChoice>,
    pub focused_region: usize,
}

#[derive(Default)]
pub struct ConflictSession {
    pub snapshot: Option<Rc<NativeConflictSnapshot>>,
    pub selected: usize,
    pub loading: bool,
    pub busy: bool,
    pub load_failed: bool,
    /// The operation ended (or there is none); the resolver closes.
    pub finished: bool,
    drafts: HashMap<Vec<u8>, FileDraft>,
    /// The shown file's path and working draft.
    pub shown: Option<(Vec<u8>, FileDraft)>,
    resolutions: HashMap<Vec<u8>, Resolution>,
    merge_bound: bool,
    pub merge_subject: String,
    pub merge_description: String,
    /// Bumped when the result text changes other than by typing, so the
    /// editor takes it.
    pub text_revision: u64,
}

impl ConflictSession {
    fn new() -> Self {
        Self {
            loading: true,
            ..Self::default()
        }
    }

    pub fn selected_file(&self) -> Option<&NativeConflictFile> {
        let files = &self.snapshot.as_ref()?.files;
        files.get(self.selected.min(files.len().checked_sub(1)?))
    }

    pub fn resolution_of(&self, path: &[u8]) -> Option<Resolution> {
        self.resolutions.get(path).copied()
    }

    /// The unsaved draft of `file`, when drafted at this version.
    fn draft_of(&self, file: &NativeConflictFile) -> Option<&FileDraft> {
        self.drafts
            .get(&file.path)
            .filter(|draft| draft.fingerprint == file.fingerprint)
    }

    /// The remaining conflicts of `file`'s result as last edited.
    pub fn remaining(&self, file: &NativeConflictFile) -> Option<usize> {
        if file.kind != NativeConflictFileKind::Text {
            return None;
        }
        let text = match &self.shown {
            Some((path, draft)) if path == &file.path => string(&draft.text),
            _ => match self.draft_of(file) {
                Some(draft) => string(&draft.text),
                None => {
                    String::from_utf8_lossy(file.result.as_deref().unwrap_or_default()).into_owned()
                }
            },
        };
        Some(marker_count(&text))
    }

    /// Keeps the shown file's draft until it is saved or the file changes.
    fn remember_shown(&mut self) {
        if let Some((path, draft)) = self.shown.take() {
            self.drafts.insert(path, draft);
        }
    }

    /// Shows the selected file: its unsaved draft, or a fresh one.
    fn bind(&mut self) {
        self.remember_shown();
        self.text_revision += 1;
        let Some(file) = self.selected_file().cloned() else {
            return;
        };
        let draft = match self
            .drafts
            .remove(&file.path)
            .filter(|draft| draft.fingerprint == file.fingerprint)
        {
            Some(draft) => draft,
            None => {
                let merge = (file.kind == NativeConflictFileKind::Text)
                    .then(|| MergeDraft::from_file(&file));
                let text = match &merge {
                    Some(merge) => merge.text.clone(),
                    None => String::from_utf8_lossy(file.result.as_deref().unwrap_or_default())
                        .encode_utf16()
                        .collect(),
                };
                FileDraft {
                    fingerprint: file.fingerprint,
                    text,
                    draft: merge,
                    side: None,
                    focused_region: 0,
                }
            }
        };
        self.shown = Some((file.path.clone(), draft));
    }

    fn record(&mut self, snapshot: &NativeConflictSnapshot, path: &[u8], resolution: Resolution) {
        if !snapshot.files.iter().any(|file| file.path == path) {
            self.resolutions.insert(path.to_vec(), resolution);
        }
    }

    fn clamp(&self, index: usize, snapshot: &NativeConflictSnapshot) -> usize {
        index.min(snapshot.files.len().saturating_sub(1))
    }

    fn ended(snapshot: &NativeConflictSnapshot) -> bool {
        snapshot.operation == NativeConflictOperationKind::Standalone && snapshot.files.is_empty()
    }

    /// The file to show once the file at `path` changed: itself while still
    /// conflicted, else the next one in queue order.
    fn shown_after(&self, snapshot: &NativeConflictSnapshot, path: &[u8]) -> usize {
        match snapshot.files.iter().position(|file| file.path == path) {
            Some(index) => index,
            None if self.selected < snapshot.files.len() => self.selected,
            None => 0,
        }
    }

    /// Takes `snapshot`, dropping drafts of files that changed.
    fn apply(&mut self, snapshot: NativeConflictSnapshot, selected: usize) {
        self.drafts.retain(|path, draft| {
            snapshot
                .files
                .iter()
                .any(|file| &file.path == path && file.fingerprint == draft.fingerprint)
        });
        self.selected = self.clamp(selected, &snapshot);
        self.finished = Self::ended(&snapshot);
        self.load_failed = false;
        self.snapshot = Some(Rc::new(snapshot));
    }
}

/// Outcome of loading, saving or undoing: the snapshot, or why not.
fn snapshot_of(
    result: Result<NativeConflictSnapshotResult, ()>,
) -> Result<NativeConflictSnapshot, Option<NativeConflictFailureKind>> {
    match result {
        Ok(NativeConflictSnapshotResult {
            snapshot: Some(snapshot),
            failure: None,
            ..
        }) => Ok(snapshot),
        Ok(NativeConflictSnapshotResult {
            failure: Some(failure),
            ..
        }) => Err(Some(failure.kind)),
        _ => Err(None),
    }
}

pub struct ConflictService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    changes: Rc<ChangesService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    sessions: RefCell<HashMap<(u64, u64), ConflictSession>>,
    probe: Cell<u64>,
}

impl ConflictService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        changes: Rc<ChangesService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            changes,
            prompts,
            notices,
            notifier,
            sessions: RefCell::new(HashMap::new()),
            probe: Cell::new(0),
        })
    }

    fn active_identity(&self) -> Option<SessionIdentity> {
        self.workspace.current().map(|session| session.identity)
    }

    fn changed(&self) {
        self.notifier.notify(Topics::CONFLICTS);
    }

    /// Reads the active repository's conflict session (made on first use;
    /// sessions of closed repositories are dropped).
    pub fn with_active<R>(&self, read: impl FnOnce(&mut ConflictSession) -> R) -> Option<R> {
        let identity = self.active_identity()?;
        let mut sessions = self.sessions.borrow_mut();
        let open: Vec<(u64, u64)> = self
            .workspace
            .open_sessions()
            .iter()
            .map(|(identity, _, _)| (identity.native_id, identity.generation))
            .collect();
        sessions.retain(|key, _| open.contains(key));
        // A new session starts loading, unlike its default.
        #[allow(clippy::unwrap_or_default)]
        let session = sessions
            .entry((identity.native_id, identity.generation))
            .or_insert_with(ConflictSession::new);
        Some(read(session))
    }

    fn with_session<R>(
        &self,
        identity: SessionIdentity,
        change: impl FnOnce(&mut ConflictSession) -> R,
    ) -> Option<R> {
        let result = self
            .sessions
            .borrow_mut()
            .get_mut(&(identity.native_id, identity.generation))
            .map(change);
        self.changed();
        result
    }

    /// Whether the active repository still shows `identity`.
    fn shown(&self, identity: SessionIdentity) -> bool {
        self.active_identity() == Some(identity)
    }

    /// Reads the paused operation again; the merge message is taken from
    /// Git once per operation.
    pub async fn load(&self) {
        let Some(identity) = self.active_identity() else {
            return;
        };
        self.with_active(|session| {
            session.remember_shown();
            session.loading = true;
        });
        self.changed();
        let result = self
            .calls
            .repository_session_conflicts(identity.native_id, identity.generation)
            .await
            .map_err(|_| ());
        if !self.shown(identity) {
            return;
        }
        match snapshot_of(result) {
            Ok(snapshot) => {
                self.with_session(identity, |session| {
                    if snapshot.operation == NativeConflictOperationKind::Merge
                        && !session.merge_bound
                    {
                        let message = snapshot.suggested_message.clone().unwrap_or_default();
                        let (subject, rest) = message.split_once('\n').unwrap_or((&message, ""));
                        session.merge_subject = subject.trim().to_owned();
                        session.merge_description = rest
                            .split('\n')
                            .filter(|line| !line.trim_start().starts_with('#'))
                            .collect::<Vec<_>>()
                            .join("\n")
                            .trim()
                            .to_owned();
                        session.merge_bound = true;
                    }
                    let selected = session.selected;
                    session.apply(snapshot, selected);
                    session.loading = false;
                    session.bind();
                });
            }
            Err(Some(NativeConflictFailureKind::NoActiveOperation)) => {
                self.with_session(identity, |session| {
                    session.loading = false;
                    session.finished = true;
                });
            }
            Err(_) => {
                self.with_session(identity, |session| {
                    session.loading = false;
                    session.load_failed = true;
                });
            }
        }
    }

    /// Shows the file at `index` (its last region when `last_region`).
    pub fn select(&self, index: usize, last_region: bool) {
        self.with_active(|session| {
            let count = session
                .snapshot
                .as_ref()
                .map_or(0, |snapshot| snapshot.files.len());
            if session.busy || index >= count || index == session.selected {
                return;
            }
            session.remember_shown();
            session.selected = index;
            session.bind();
            if last_region && let Some((_, draft)) = &mut session.shown {
                let blocks = draft.draft.as_ref().map_or(0, |merge| merge.blocks.len());
                if blocks > 0 {
                    draft.focused_region = blocks - 1;
                }
            }
        });
        self.changed();
    }

    /// Takes (or with `remove`, takes back) `choice` in region `index` of
    /// the shown file.
    pub fn take_region(&self, index: usize, choice: NativeConflictRegionChoice, remove: bool) {
        self.with_active(|session| {
            if session.busy {
                return;
            }
            let Some((_, draft)) = &mut session.shown else {
                return;
            };
            let Some(merge) = &mut draft.draft else {
                return;
            };
            if index >= merge.blocks.len() {
                return;
            }
            draft.side = None;
            draft.focused_region = index;
            draft.text = if remove {
                merge.remove(index, choice)
            } else {
                merge.take(index, choice)
            }
            .to_vec();
            session.text_revision += 1;
        });
        self.changed();
    }

    /// Takes `choice` in the focused region, or the whole side of a file
    /// without regions (the conflictTake* commands).
    pub fn take_focused(&self, choice: NativeConflictRegionChoice) {
        let target = self.with_active(|session| {
            let file = session.selected_file()?;
            let (_, draft) = session.shown.as_ref()?;
            let regions = draft.draft.as_ref().map_or(0, |merge| merge.blocks.len());
            Some((
                file.kind == NativeConflictFileKind::Text && regions > 0,
                draft.focused_region,
            ))
        });
        match target.flatten() {
            Some((true, region)) => self.take_region(region, choice, false),
            Some((false, _)) => match choice {
                NativeConflictRegionChoice::Current => {
                    self.choose_side(NativeConflictSideChoice::Current)
                }
                NativeConflictRegionChoice::Incoming => {
                    self.choose_side(NativeConflictSideChoice::Incoming)
                }
                NativeConflictRegionChoice::Both => {}
            },
            None => {}
        }
    }

    pub fn focus_region(&self, index: usize) {
        self.with_active(|session| {
            if let Some((_, draft)) = &mut session.shown {
                draft.focused_region = index;
            }
        });
        self.changed();
    }

    /// Chooses the whole `side` as the shown file's result (not yet saved);
    /// choosing it again takes the choice back.
    pub fn choose_side(&self, side: NativeConflictSideChoice) {
        self.with_active(|session| {
            if session.busy {
                return;
            }
            let Some(file) = session.selected_file().cloned() else {
                return;
            };
            let Some((_, draft)) = &mut session.shown else {
                return;
            };
            if draft.side == Some(side) {
                Self::clear_side(draft, &file);
            } else {
                draft.side = Some(side);
                if file.kind == NativeConflictFileKind::Text
                    && let Some(content) = &side_of(&file, side).content
                {
                    draft.text = String::from_utf8_lossy(content).encode_utf16().collect();
                }
            }
            session.text_revision += 1;
        });
        self.changed();
    }

    fn clear_side(draft: &mut FileDraft, file: &NativeConflictFile) {
        draft.side = None;
        draft.text = match &draft.draft {
            Some(merge) => merge.text.clone(),
            None => String::from_utf8_lossy(file.result.as_deref().unwrap_or_default())
                .encode_utf16()
                .collect(),
        };
    }

    /// Takes back a whole-file choice.
    pub fn clear_whole_side(&self) {
        self.with_active(|session| {
            if session.busy {
                return;
            }
            let Some(file) = session.selected_file().cloned() else {
                return;
            };
            let Some((_, draft)) = &mut session.shown else {
                return;
            };
            if draft.side.is_some() {
                Self::clear_side(draft, &file);
                session.text_revision += 1;
            }
        });
        self.changed();
    }

    /// Follows a hand edit of the shown file's result.
    pub fn edit_result(&self, text: &str) {
        self.with_active(|session| {
            let Some(file) = session.selected_file() else {
                return;
            };
            if file.kind != NativeConflictFileKind::Text {
                return;
            }
            let Some((_, draft)) = &mut session.shown else {
                return;
            };
            let updated: Vec<u16> = text.encode_utf16().collect();
            if updated == draft.text {
                return;
            }
            if let Some(merge) = &mut draft.draft {
                merge.edit(&updated);
            }
            draft.text = updated;
            draft.side = None;
        });
        self.changed();
    }

    pub fn set_merge_message(&self, subject: String, description: String) {
        self.with_active(|session| {
            session.merge_subject = subject;
            session.merge_description = description;
        });
        self.changed();
    }

    fn set_busy(&self, identity: SessionIdentity, busy: bool) {
        self.with_session(identity, |session| session.busy = busy);
    }

    /// Saves the shown file's result: its chosen whole side, or its text,
    /// which must hold no conflict marker.
    pub async fn save(&self) -> bool {
        let Some(identity) = self.active_identity() else {
            return false;
        };
        let Some(Some((file, draft))) = self.with_active(|session| {
            if session.busy {
                return None;
            }
            Some((
                session.selected_file()?.clone(),
                session.shown.as_ref()?.1.clone(),
            ))
        }) else {
            return false;
        };
        if let Some(side) = draft.side {
            return self
                .mutate(
                    identity,
                    file.path.clone(),
                    Some(side_resolution(&file, side)),
                    async {
                        self.calls
                            .repository_session_conflict_choose_side(
                                identity.native_id,
                                identity.generation,
                                file.path.clone(),
                                file.fingerprint,
                                side,
                            )
                            .await
                            .map_err(|_| ())
                    },
                )
                .await;
        }
        if file.kind != NativeConflictFileKind::Text {
            return false;
        }
        let text = string(&draft.text);
        if has_conflict_markers(&text) {
            let count = draft
                .draft
                .as_ref()
                .map_or(file.regions.len(), MergeDraft::unresolved_count);
            self.notices
                .status("conflictRegionsRemaining", json!({"count": count}));
            return false;
        }
        self.set_busy(identity, true);
        let result = self
            .calls
            .repository_session_conflict_save_result(
                identity.native_id,
                identity.generation,
                file.path.clone(),
                file.fingerprint,
                text.into_bytes(),
            )
            .await
            .map_err(|_| ());
        let saved = match snapshot_of(result) {
            Ok(snapshot) if self.shown(identity) => {
                let next = self.with_session(identity, |session| {
                    session.shown = None;
                    session.drafts.remove(&file.path);
                    session.record(&snapshot, &file.path, Resolution::Merged);
                    let selected = session.shown_after(&snapshot, &file.path);
                    session.apply(snapshot, selected);
                    session.bind();
                    session.selected_file().map(|next| next.path.clone())
                });
                if let Some(Some(next)) = next
                    && next != file.path
                {
                    self.notices.status(
                        "conflictResolvedNext",
                        json!({"resolved": file_name(&file.path), "next": file_name(&next)}),
                    );
                }
                true
            }
            Ok(_) => false,
            Err(_) => {
                self.notices.status("conflictSaveFailed", Value::Null);
                false
            }
        };
        self.set_busy(identity, false);
        drop(self.workspace.refresh_if_open(identity).await);
        saved
    }

    /// Runs one snapshot-returning change for `path`, then shows its result
    /// (or reloads after a failure).
    async fn mutate(
        &self,
        identity: SessionIdentity,
        path: Vec<u8>,
        resolution: Option<Resolution>,
        operation: impl std::future::Future<Output = Result<NativeConflictSnapshotResult, ()>>,
    ) -> bool {
        self.set_busy(identity, true);
        let result = snapshot_of(operation.await);
        let ok = match result {
            Ok(snapshot) => {
                self.with_session(identity, |session| {
                    session.shown = None;
                    session.drafts.remove(&path);
                    if let Some(resolution) = resolution {
                        session.record(&snapshot, &path, resolution);
                    }
                    let selected = session.shown_after(&snapshot, &path);
                    session.apply(snapshot, selected);
                    session.bind();
                });
                true
            }
            Err(_) => {
                self.notices.status("conflictSaveFailed", Value::Null);
                self.set_busy(identity, false);
                Box::pin(self.load()).await;
                false
            }
        };
        self.set_busy(identity, false);
        drop(self.workspace.refresh_if_open(identity).await);
        ok
    }

    /// Puts the conflict of `path` back.
    /// Merges the shown file in the external `tool`: its exact command is previewed and confirmed, then
    /// it runs; the conflict is read again and the file counts as resolved
    /// externally once Git no longer lists it.
    pub async fn merge_externally(
        &self,
        tool: gitlama_contract::integrations::NativeIntegrationDefinition,
    ) {
        let Some(identity) = self.active_identity() else {
            return;
        };
        let Some(Some(file)) = self.with_active(|session| {
            if session.busy {
                None
            } else {
                session.selected_file().cloned()
            }
        }) else {
            return;
        };
        self.set_busy(identity, true);
        let (session, generation) = (identity.native_id, identity.generation);
        let preview = match self
            .calls
            .repository_session_conflict_external_merge_preview(
                session,
                generation,
                file.path.clone(),
                file.fingerprint,
                tool,
            )
            .await
        {
            Ok(result) if result.failure.is_none() => result.preview,
            _ => None,
        };
        let Some(preview) = preview else {
            self.set_busy(identity, false);
            return self.notices.status("conflictSaveFailed", Value::Null);
        };
        let commands: Vec<String> = std::iter::once(preview.executable.clone())
            .chain(preview.arguments.iter().cloned())
            .collect();
        let answer = self
            .prompts
            .ask(
                "confirmIntegration",
                json!({"commands": commands, "summary": "integrationMergeSummary"}),
            )
            .await;
        if answer != Some(Value::Bool(true)) || !self.shown(identity) {
            let _ = self
                .calls
                .repository_session_integration_cancel(session, generation, preview.token)
                .await;
            return self.set_busy(identity, false);
        }
        let completed = matches!(
            self.calls.repository_session_integration_execute(session, generation, preview.token, true).await,
            Ok(result) if result.state == gitlama_contract::integrations::NativeIntegrationExecutionState::Completed
        );
        if !completed {
            let _ = self
                .calls
                .repository_session_integration_cancel(session, generation, preview.token)
                .await;
            self.set_busy(identity, false);
            return self.notices.status("conflictSaveFailed", Value::Null);
        }
        self.set_busy(identity, false);
        if !self.shown(identity) {
            return;
        }
        self.load().await;
        self.with_session(identity, |session| {
            if let Some(snapshot) = session.snapshot.clone() {
                session.record(&snapshot, &file.path, Resolution::External);
            }
        });
    }

    pub async fn undo(&self, path: Vec<u8>) {
        let Some(identity) = self.active_identity() else {
            return;
        };
        if self.with_active(|session| session.busy).unwrap_or(true) {
            return;
        }
        self.mutate(identity, path.clone(), None, async {
            self.calls
                .repository_session_conflict_undo_resolution(
                    identity.native_id,
                    identity.generation,
                    path.clone(),
                )
                .await
                .map_err(|_| ())
        })
        .await;
        self.with_session(identity, |session| session.resolutions.remove(&path));
    }

    /// Resolves each of `paths` still conflicted with its whole `side`, or
    /// (side None) puts each back; one busy state for all.
    pub async fn for_each(&self, paths: Vec<Vec<u8>>, side: Option<NativeConflictSideChoice>) {
        let Some(identity) = self.active_identity() else {
            return;
        };
        if paths.is_empty() || self.with_active(|session| session.busy).unwrap_or(true) {
            return;
        }
        self.set_busy(identity, true);
        for path in paths {
            let state = self.with_session(identity, |session| {
                let shown = session.selected_file().map(|file| file.path.clone());
                let file = session.snapshot.as_ref().and_then(|snapshot| {
                    snapshot
                        .files
                        .iter()
                        .find(|file| file.path == path)
                        .cloned()
                });
                (session.finished, shown, file)
            });
            let Some((finished, shown, file)) = state else {
                break;
            };
            if finished || !self.shown(identity) {
                break;
            }
            let (call, resolution) = match side {
                Some(side) => {
                    let Some(file) = file else { continue };
                    (
                        self.calls.repository_session_conflict_choose_side(
                            identity.native_id,
                            identity.generation,
                            path.clone(),
                            file.fingerprint,
                            side,
                        ),
                        Some(side_resolution(&file, side)),
                    )
                }
                None => {
                    self.with_session(identity, |session| session.resolutions.remove(&path));
                    (
                        self.calls.repository_session_conflict_undo_resolution(
                            identity.native_id,
                            identity.generation,
                            path.clone(),
                        ),
                        None,
                    )
                }
            };
            match snapshot_of(call.await.map_err(|_| ())) {
                Ok(snapshot) => {
                    self.with_session(identity, |session| {
                        session.drafts.remove(&path);
                        if let Some(resolution) = resolution {
                            session.record(&snapshot, &path, resolution);
                        }
                        let selected = shown
                            .as_ref()
                            .and_then(|shown| {
                                snapshot.files.iter().position(|file| &file.path == shown)
                            })
                            .unwrap_or(session.selected);
                        if session
                            .shown
                            .as_ref()
                            .is_some_and(|(shown, _)| shown == &path)
                        {
                            session.shown = None;
                        }
                        session.apply(snapshot, selected);
                    });
                }
                Err(_) => {
                    self.notices.status("conflictSaveFailed", Value::Null);
                    self.set_busy(identity, false);
                    Box::pin(self.load()).await;
                    break;
                }
            }
        }
        self.with_session(identity, |session| {
            session.busy = false;
            if !session.finished {
                session.bind();
            }
        });
        drop(self.workspace.refresh_if_open(identity).await);
    }

    /// Continues, skips or aborts the paused operation. Skip and Abort ask
    /// first; Continue waits until no file is conflicted.
    pub async fn sequence(&self, action: NativeConflictSequencerAction) {
        let Some(identity) = self.active_identity() else {
            return;
        };
        let Some((busy, conflicted, merge, message)) = self.with_active(|session| {
            let snapshot = session.snapshot.clone();
            (
                session.busy,
                snapshot
                    .as_ref()
                    .is_some_and(|snapshot| !snapshot.files.is_empty()),
                snapshot.as_ref().is_some_and(|snapshot| {
                    snapshot.operation == NativeConflictOperationKind::Merge
                }),
                format!(
                    "{}\n\n{}",
                    session.merge_subject.trim(),
                    session.merge_description.trim()
                )
                .trim()
                .to_owned(),
            )
        }) else {
            return;
        };
        if busy || (action == NativeConflictSequencerAction::Continue && conflicted) {
            return;
        }
        if action != NativeConflictSequencerAction::Continue {
            let kind = if action == NativeConflictSequencerAction::Abort {
                "abort"
            } else {
                "skip"
            };
            if self
                .prompts
                .ask("confirmSequencer", json!({"action": kind}))
                .await
                != Some(Value::Bool(true))
                || !self.shown(identity)
            {
                return;
            }
        }
        self.set_busy(identity, true);
        let call = if action == NativeConflictSequencerAction::Continue && merge {
            self.calls
                .repository_session_conflict_continue_with_message(
                    identity.native_id,
                    identity.generation,
                    action,
                    message,
                )
        } else {
            self.calls.repository_session_conflict_continue(
                identity.native_id,
                identity.generation,
                action,
            )
        };
        match call.await {
            Ok(result) => {
                let key = match result.state {
                    NativeConflictContinuationState::Completed => "conflictCompleted",
                    NativeConflictContinuationState::Aborted => "conflictAborted",
                    NativeConflictContinuationState::Conflict
                    | NativeConflictContinuationState::Interrupted => "conflictStoppedAgain",
                    NativeConflictContinuationState::Failed => "conflictContinueFailed",
                    NativeConflictContinuationState::OutcomeUncertain => "mutationOutcomeUncertain",
                };
                self.notices.status(key, Value::Null);
                self.with_session(identity, |session| {
                    if result.state != NativeConflictContinuationState::Failed {
                        session.resolutions.clear();
                    }
                    if matches!(
                        result.state,
                        NativeConflictContinuationState::Completed
                            | NativeConflictContinuationState::Aborted
                    ) {
                        session.finished = true;
                    }
                    session.busy = false;
                });
                drop(self.workspace.refresh_if_open(identity).await);
                if matches!(
                    result.state,
                    NativeConflictContinuationState::Conflict
                        | NativeConflictContinuationState::Interrupted
                        | NativeConflictContinuationState::OutcomeUncertain
                ) {
                    Box::pin(self.load()).await;
                }
            }
            Err(_) => {
                self.notices.status("conflictContinueFailed", Value::Null);
                self.set_busy(identity, false);
            }
        }
    }

    /// The resolver of the active tab closed: drops a finished session and
    /// gives the lists back until a new conflict appears.
    pub fn finish(&self) {
        let Some(identity) = self.active_identity() else {
            return;
        };
        let finished = self
            .with_active(|session| session.finished)
            .unwrap_or(false);
        if finished {
            self.sessions
                .borrow_mut()
                .remove(&(identity.native_id, identity.generation));
        }
        if let Some(tab) = self.workspace.active_tab_id() {
            self.changes.finish_conflict_flow(tab);
        }
        self.changed();
    }

    /// Asks whether the active repository has a paused operation its status
    /// does not show, such as a resolved one awaiting Continue.
    pub async fn probe(&self) {
        let (Some(identity), Some(tab)) = (self.active_identity(), self.workspace.active_tab_id())
        else {
            return;
        };
        let probe = self.probe.get() + 1;
        self.probe.set(probe);
        let result = self
            .calls
            .repository_session_conflicts(identity.native_id, identity.generation)
            .await
            .map_err(|_| ());
        if probe != self.probe.get() || !self.shown(identity) {
            return;
        }
        match snapshot_of(result) {
            Ok(snapshot) => {
                let active =
                    !snapshot.files.is_empty() || snapshot.can_continue || snapshot.can_skip;
                self.changes.set_conflict_flow(tab, active);
            }
            Err(Some(NativeConflictFailureKind::NoActiveOperation)) => {
                self.changes.set_conflict_flow(tab, false)
            }
            Err(_) => {}
        }
    }
}

fn file_name(path: &[u8]) -> String {
    let shown = String::from_utf8_lossy(path).replace('\\', "/");
    shown.rsplit('/').next().unwrap_or_default().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::conflict::NativeConflictRegion;

    fn side(content: Option<&[u8]>, mode: Option<u32>) -> NativeConflictSide {
        NativeConflictSide {
            present: content.is_some(),
            mode,
            content: content.map(<[u8]>::to_vec),
            byte_count: content.map_or(0, <[u8]>::len) as u64,
        }
    }

    fn file(path: &str, current: Option<&[u8]>, incoming: Option<&[u8]>) -> NativeConflictFile {
        NativeConflictFile {
            path: path.as_bytes().to_vec(),
            kind: NativeConflictFileKind::Text,
            ancestor: side(Some(b"base\n"), Some(0o100644)),
            current: side(current, Some(0o100644)),
            incoming: side(incoming, Some(0o100644)),
            result: Some(b"<<<<<<< a\nx\n=======\ny\n>>>>>>> b\n".to_vec()),
            result_present: true,
            result_mode: Some(0o100644),
            marker_free: false,
            regions: vec![NativeConflictRegion {
                index: 0,
                current: b"x\n".to_vec(),
                incoming: b"y\n".to_vec(),
                ancestor: None,
            }],
            fingerprint: 7,
            can_undo_resolution: false,
        }
    }

    #[test]
    fn presence_and_differences_read_the_sides() {
        assert_eq!(presence(&file("f", Some(b"x"), None)), "deletedIncoming");
        assert_eq!(
            content_difference(&file("f", Some(b"a\r\nb"), Some(b"a\nb"))),
            "lineEndings"
        );
        assert_eq!(
            content_difference(&file("f", Some(b"a\n"), Some(b"a"))),
            "finalNewline"
        );
        assert_eq!(
            content_difference(&file("f", Some(b"\xef\xbb\xbfa"), Some(b"a"))),
            "byteOrderMark"
        );
        assert_eq!(
            content_difference(&file("f", Some(b"a b"), Some(b"ab"))),
            "whitespace"
        );
        assert_eq!(
            content_difference(&file("f", Some(b"a"), Some(b"b"))),
            "content"
        );
        assert_eq!(
            side_resolution(
                &file("f", None, Some(b"y")),
                NativeConflictSideChoice::Current
            ),
            Resolution::Deleted
        );
    }

    #[test]
    fn entry_facts_name_the_line_endings() {
        let facts = entry(&side(Some(b"a\r\nb\n"), Some(0o100755)), true);
        assert_eq!(facts["type"], "executable");
        assert_eq!(facts["mode"], "100755");
        assert_eq!(facts["endings"], "mixed");
        assert_eq!(facts["finalNewline"], true);
    }

    #[test]
    fn a_session_keeps_the_draft_of_a_file_it_leaves() {
        let mut session = ConflictSession::new();
        session.apply(
            NativeConflictSnapshot {
                operation: NativeConflictOperationKind::Merge,
                current_label: b"main".to_vec(),
                incoming_label: b"topic".to_vec(),
                current_step: None,
                total_steps: None,
                files: vec![
                    file("a", Some(b"x\n"), Some(b"y\n")),
                    file("b", Some(b"x\n"), Some(b"y\n")),
                ],
                resolved_undo_paths: Vec::new(),
                can_continue: false,
                can_skip: false,
                suggested_message: None,
            },
            0,
        );
        session.bind();
        let (_, draft) = session.shown.as_mut().unwrap();
        draft.text = draft
            .draft
            .as_mut()
            .unwrap()
            .take(0, NativeConflictRegionChoice::Incoming)
            .to_vec();
        assert_eq!(
            session.remaining(&session.selected_file().unwrap().clone()),
            Some(0)
        );
        session.selected = 1;
        session.bind();
        assert_eq!(session.shown.as_ref().unwrap().0, b"b");
        session.selected = 0;
        session.bind();
        assert_eq!(string(&session.shown.as_ref().unwrap().1.text), "y\n");
    }
}
