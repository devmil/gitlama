//! The conflict resolver: the active repository's conflict session as QML
//! reads it (`state`), the shown file's result text and comparison rows,
//! and slots for every resolver action. Paths travel as hex keys, since
//! they need not be UTF-8.

use crate::plumbing::Commands;
use gitlama_contract::conflict::{
    NativeConflictFileKind, NativeConflictOperationKind, NativeConflictRegionChoice, NativeConflictSequencerAction,
    NativeConflictSideChoice,
};
use gitlama_workbench::app::Services;
use gitlama_workbench::conflict_draft::{has_conflict_markers, marker_count, string};
use gitlama_workbench::conflicts::{ConflictSession, details, presence};
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

/// The roles of a comparison row.
pub const CONFLICT_ROW_ROLES: &[&str] = &[
    "key",
    "current",
    "incoming",
    "currentLine",
    "incomingLine",
    "block",
    "different",
    "first",
    "chosenCurrent",
    "chosenIncoming",
];

pub fn key(path: &[u8]) -> String {
    path.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn path_of(key: &str) -> Option<Vec<u8>> {
    (0..key.len()).step_by(2).map(|index| u8::from_str_radix(key.get(index..index + 2)?, 16).ok()).collect()
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).replace('\\', "/")
}

fn operation_name(kind: NativeConflictOperationKind) -> &'static str {
    match kind {
        NativeConflictOperationKind::Merge => "merge",
        NativeConflictOperationKind::Rebase => "rebase",
        NativeConflictOperationKind::CherryPick => "cherryPick",
        NativeConflictOperationKind::Revert => "revert",
        NativeConflictOperationKind::Snapshot => "snapshot",
        NativeConflictOperationKind::Stash => "stash",
        NativeConflictOperationKind::Standalone => "standalone",
    }
}

fn choice_name(choice: Option<NativeConflictRegionChoice>) -> Value {
    match choice {
        Some(NativeConflictRegionChoice::Current) => json!("current"),
        Some(NativeConflictRegionChoice::Incoming) => json!("incoming"),
        Some(NativeConflictRegionChoice::Both) => json!("both"),
        None => Value::Null,
    }
}

fn parse_region_choice(name: &str) -> Option<NativeConflictRegionChoice> {
    Some(match name {
        "current" => NativeConflictRegionChoice::Current,
        "incoming" => NativeConflictRegionChoice::Incoming,
        "both" => NativeConflictRegionChoice::Both,
        _ => return None,
    })
}

fn parse_side(name: &str) -> Option<NativeConflictSideChoice> {
    Some(match name {
        "current" => NativeConflictSideChoice::Current,
        "incoming" => NativeConflictSideChoice::Incoming,
        _ => return None,
    })
}

/// What QML shows of `session`, its result text and comparison rows.
pub fn project(session: &ConflictSession) -> (Value, String, u64, Vec<Value>) {
    let Some(snapshot) = &session.snapshot else {
        return (
            json!({"loading": session.loading, "busy": session.busy, "loadFailed": session.load_failed, "finished": session.finished, "ready": false}),
            String::new(),
            session.text_revision,
            Vec::new(),
        );
    };
    let files: Vec<Value> = snapshot
        .files
        .iter()
        .map(|file| {
            let shown_presence = presence(file);
            json!({
                "key": key(&file.path),
                "path": text(&file.path),
                "kind": match file.kind {
                    NativeConflictFileKind::Text => "text",
                    NativeConflictFileKind::Binary => "binary",
                    NativeConflictFileKind::Huge => "huge",
                },
                "remaining": session.remaining(file),
                "deletion": matches!(shown_presence, "deletedCurrent" | "deletedIncoming" | "bothDeleted").then_some(shown_presence),
            })
        })
        .collect();
    let resolved: Vec<Value> = snapshot
        .resolved_undo_paths
        .iter()
        .map(|path| json!({"key": key(path), "path": text(path), "outcome": session.resolution_of(path).map(|kind| kind.name())}))
        .collect();
    let mut rows = Vec::new();
    let mut result = String::new();
    let file = match (session.selected_file(), &session.shown) {
        (Some(file), Some((path, draft))) if path == &file.path => {
            result = string(&draft.text);
            let blocks = draft.draft.as_ref().map(|merge| {
                merge
                    .blocks
                    .iter()
                    .map(|block| {
                        json!({
                            "choice": choice_name(block.choice),
                            "start": block.start,
                            "end": block.end,
                        })
                    })
                    .collect::<Vec<_>>()
            });
            if let Some(merge) = &draft.draft {
                let firsts: Vec<usize> = merge.block_rows().iter().filter(|(_, count)| *count > 0).map(|(first, _)| *first).collect();
                for (index, row) in merge.rows.iter().enumerate() {
                    let choice = row.block.and_then(|block| merge.blocks.get(block)).and_then(|block| block.choice);
                    rows.push(json!({
                        "key": index.to_string(),
                        "current": string(&row.current).trim_end_matches('\n'),
                        "incoming": string(&row.incoming).trim_end_matches('\n'),
                        "currentLine": row.current_line,
                        "incomingLine": row.incoming_line,
                        "block": row.block.map_or(-1, |block| block as i64),
                        "different": row.different,
                        "first": firsts.contains(&index),
                        "chosenCurrent": matches!(choice, Some(NativeConflictRegionChoice::Current | NativeConflictRegionChoice::Both)),
                        "chosenIncoming": matches!(choice, Some(NativeConflictRegionChoice::Incoming | NativeConflictRegionChoice::Both)),
                    }));
                }
            }
            // Whole-line bands under the result: an open conflict, or the
            // parts taken from each side (both: current, then incoming).
            let mut marks = Vec::new();
            if draft.side.is_none()
                && let Some(merge) = &draft.draft
            {
                let units = &draft.text;
                let line_at = |offset: usize| units[..offset.min(units.len())].iter().filter(|unit| **unit == b'\n' as u16).count();
                let mut mark = |start: usize, end: usize, kind: &str| {
                    if end > start {
                        marks.push(json!({"first": line_at(start), "last": line_at(end - 1), "kind": kind}));
                    }
                };
                let mut offset = 0;
                for block in &merge.blocks {
                    let start = block.start.clamp(offset, units.len());
                    let end = block.end.clamp(start, units.len());
                    offset = end;
                    match block.choice {
                        None => mark(start, end, "open"),
                        Some(NativeConflictRegionChoice::Current) => mark(start, end, "current"),
                        Some(NativeConflictRegionChoice::Incoming) => mark(start, end, "incoming"),
                        Some(NativeConflictRegionChoice::Both) => {
                            let split = (start + block.current.len()).clamp(start, end);
                            mark(start, split, "current");
                            mark(split, end, "incoming");
                        }
                    }
                }
            }
            let side_name = draft.side.map(|side| match side {
                NativeConflictSideChoice::Current => "current",
                NativeConflictSideChoice::Incoming => "incoming",
            });
            let side_present = |side: NativeConflictSideChoice| match side {
                NativeConflictSideChoice::Current => file.current.present,
                NativeConflictSideChoice::Incoming => file.incoming.present,
            };
            json!({
                "key": key(&file.path),
                "path": text(&file.path),
                "kind": match file.kind {
                    NativeConflictFileKind::Text => "text",
                    NativeConflictFileKind::Binary => "binary",
                    NativeConflictFileKind::Huge => "huge",
                },
                "details": details(file),
                "markerFree": !has_conflict_markers(&result),
                "markers": marker_count(&result),
                "currentPresent": file.current.present,
                "incomingPresent": file.incoming.present,
                "currentEmpty": file.current.content.as_ref().is_some_and(Vec::is_empty),
                "incomingEmpty": file.incoming.content.as_ref().is_some_and(Vec::is_empty),
                "ancestorPresent": file.ancestor.present,
                "ancestor": file.ancestor.content.as_deref().map(|content| String::from_utf8_lossy(content).into_owned()),
                "side": side_name,
                "deletionChosen": draft.side.is_some_and(|side| !side_present(side)),
                "focusedRegion": draft.focused_region,
                "regions": blocks.as_ref().map_or(0, Vec::len),
                "unresolved": draft.draft.as_ref().map_or(file.regions.len(), |merge| merge.unresolved_count()),
                "blocks": blocks,
                "marks": marks,
                "blockRows": draft.draft.as_ref().map_or(Vec::new(), |merge| merge.block_rows().iter().map(|(first, count)| json!([first, count])).collect()),
            })
        }
        _ => Value::Null,
    };
    let state = json!({
        "ready": true,
        "loading": session.loading,
        "busy": session.busy,
        "loadFailed": session.load_failed,
        "finished": session.finished,
        "operation": operation_name(snapshot.operation),
        "currentLabel": text(&snapshot.current_label),
        "incomingLabel": text(&snapshot.incoming_label),
        "step": snapshot.current_step,
        "steps": snapshot.total_steps,
        "canContinue": snapshot.can_continue,
        "canSkip": snapshot.can_skip,
        "selected": session.selected,
        "files": files,
        "resolved": resolved,
        "mergeSubject": session.merge_subject,
        "mergeDescription": session.merge_description,
        "file": file,
    });
    (state, result, session.text_revision, rows)
}

#[qobject(ConvertToCamelCase)]
mod conflicts_state {
    use super::*;

    #[derive(Default)]
    pub struct ConflictsState {
        pub commands: Option<Commands>,
        pub(crate) state: Value,
        pub(crate) result_text: String,
        pub(crate) text_revision: i64,
    }

    impl ConflictsState {
        qproperty!("state", Member = state, Notify = state_changed);
        qproperty!("resultText", Member = result_text, Notify = result_changed);
        qproperty!("textRevision", Member = text_revision, Notify = result_changed);

        #[qsignal]
        pub fn state_changed(&mut self);
        #[qsignal]
        pub fn result_changed(&mut self);

        /// Reads the paused operation again.
        #[qslot]
        fn load(&self) {
            self.spawn(|services| {
                let conflicts = Rc::clone(&services.conflicts);
                async move { conflicts.load().await }
            });
        }

        #[qslot]
        fn select(&self, index: i32, last_region: bool) {
            self.with_services(move |services| services.conflicts.select(index.max(0) as usize, last_region));
        }

        /// `choice` is current, incoming or both.
        #[qslot]
        fn take_region(&self, index: i32, choice: String, remove: bool) {
            let Some(choice) = parse_region_choice(&choice) else { return };
            self.with_services(move |services| services.conflicts.take_region(index.max(0) as usize, choice, remove));
        }

        #[qslot]
        fn take_focused(&self, choice: String) {
            let Some(choice) = parse_region_choice(&choice) else { return };
            self.with_services(move |services| services.conflicts.take_focused(choice));
        }

        #[qslot]
        fn focus_region(&self, index: i32) {
            self.with_services(move |services| services.conflicts.focus_region(index.max(0) as usize));
        }

        /// `side` is current or incoming; choosing it again takes it back.
        #[qslot]
        fn choose_side(&self, side: String) {
            let Some(side) = parse_side(&side) else { return };
            self.with_services(move |services| services.conflicts.choose_side(side));
        }

        #[qslot]
        fn clear_whole_side(&self) {
            self.with_services(|services| services.conflicts.clear_whole_side());
        }

        #[qslot]
        fn edit_result(&self, text: String) {
            self.with_services(move |services| services.conflicts.edit_result(&text));
        }

        #[qslot]
        fn set_merge_message(&self, subject: String, description: String) {
            self.with_services(move |services| services.conflicts.set_merge_message(subject, description));
        }

        /// Saves the shown file's result.
        #[qslot]
        fn save(&self) {
            self.spawn(|services| {
                let conflicts = Rc::clone(&services.conflicts);
                async move {
                    conflicts.save().await;
                }
            });
        }

        /// Merges the shown file in the merge tool `name` (the only one when
        /// empty).
        #[qslot]
        fn merge_externally(&self, name: String) {
            self.spawn(move |services| {
                let conflicts = Rc::clone(&services.conflicts);
                let tool = services.settings.with(|document| {
                    let tools: Vec<_> = document
                        .integrations
                        .iter()
                        .filter_map(gitlama_workbench::integrations::definition)
                        .filter(|tool| tool.kind == gitlama_contract::integrations::NativeIntegrationKind::MergeTool)
                        .collect();
                    if name.is_empty() && tools.len() == 1 { tools.into_iter().next() } else { tools.into_iter().find(|tool| tool.id == name) }
                });
                async move {
                    if let Some(tool) = tool {
                        conflicts.merge_externally(tool).await;
                    }
                }
            });
        }

        /// Puts the conflict of the file `key` back.
        #[qslot]
        fn undo(&self, key: String) {
            let Some(path) = path_of(&key) else { return };
            self.spawn(move |services| {
                let conflicts = Rc::clone(&services.conflicts);
                async move { conflicts.undo(path).await }
            });
        }

        /// Resolves each file of `keys` with its whole `side`; an empty side
        /// puts each back.
        #[qslot]
        fn for_each(&self, keys: Value, side: String) {
            let paths: Vec<Vec<u8>> =
                keys.as_array().map(|keys| keys.iter().filter_map(|key| path_of(key.as_str()?)).collect()).unwrap_or_default();
            let side = parse_side(&side);
            self.spawn(move |services| {
                let conflicts = Rc::clone(&services.conflicts);
                async move { conflicts.for_each(paths, side).await }
            });
        }

        /// `action` is continue, skip or abort.
        #[qslot]
        fn sequence(&self, action: String) {
            let action = match action.as_str() {
                "continue" => NativeConflictSequencerAction::Continue,
                "skip" => NativeConflictSequencerAction::Skip,
                "abort" => NativeConflictSequencerAction::Abort,
                _ => return,
            };
            self.spawn(move |services| {
                let conflicts = Rc::clone(&services.conflicts);
                async move { conflicts.sequence(action).await }
            });
        }

        /// The resolver closed.
        #[qslot]
        fn finish(&self) {
            self.with_services(|services| services.conflicts.finish());
        }

        /// Looks for a paused operation the status does not show.
        #[qslot]
        fn probe(&self) {
            self.spawn(|services| {
                let conflicts = Rc::clone(&services.conflicts);
                async move { conflicts.probe().await }
            });
        }
    }

    impl ConflictsState {
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

pub use conflicts_state::ConflictsState;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_round_trip_any_bytes() {
        let path = vec![0x66, 0xff, 0x2f, 0x00];
        assert_eq!(path_of(&key(&path)), Some(path));
        assert_eq!(path_of("zz"), None);
    }
}
