//! Projections of workbench state as plain values for QML.

use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::NativeRepositoryPhase;
use gitlama_workbench::entry::EntryState;
use gitlama_workbench::session::{basename, display_path};
use gitlama_workbench::workspace::{Pane, Tab, TabGroup, TabPhase};
use serde_json::{Value, json};

pub fn path_text(identity: &NativePathIdentity) -> String {
    display_path(identity)
}

pub fn recents(recents: &[NativePathIdentity]) -> Value {
    Value::Array(
        recents
            .iter()
            .enumerate()
            .map(|(index, identity)| {
                json!({
                    "index": index,
                    "name": basename(identity),
                    "path": display_path(identity),
                    "remote": identity.remote.is_some(),
                    "profileId": identity.remote.as_ref().map(|remote| remote.profile_id.clone()),
                })
            })
            .collect(),
    )
}

pub fn entry(state: EntryState) -> Value {
    json!({
        "busy": state.busy,
        "failure": state.failure.map(|failure| failure.name()),
        "cloneFailure": state.clone_failure,
    })
}

fn phase(phase: TabPhase) -> &'static str {
    match phase {
        TabPhase::Choosing => "choosing",
        TabPhase::Opening => "opening",
        TabPhase::Open => "open",
        TabPhase::Failed => "failed",
    }
}

pub fn tab(tab: &Tab) -> Value {
    let snapshot = tab.session.as_ref().map(|session| &session.snapshot);
    let status = snapshot.and_then(|snapshot| snapshot.status.as_ref());
    let identity = snapshot.and_then(|snapshot| snapshot.identity.as_ref());
    json!({
        "id": tab.id,
        "label": tab.label,
        "phase": phase(tab.phase),
        "failure": tab.failure.map(|failure| failure.name()),
        "groupId": tab.group_id,
        "remote": tab.canonical_identity().is_some_and(|identity| identity.remote.is_some()),
        "path": tab.canonical_identity().map(display_path),
        "repositoryKey": tab.repository().map(display_path),
        "mainWorktree": tab.is_main_worktree(),
        "loading": snapshot.is_some_and(|snapshot| snapshot.phase == NativeRepositoryPhase::Loading),
        "branch": status.and_then(|status| status.branch_name.as_ref()).map(|name| String::from_utf8_lossy(name).into_owned()),
        "headObjectId": status.and_then(|status| status.head_object_id.clone()),
        "bare": identity.is_some_and(|identity| identity.kind == gitlama_contract::dto::NativeRepositoryKind::Bare),
        "changes": status.map_or(0, |status| status.entries.len()),
        "pane": tab.navigation.pane.name(),
        "route": tab.navigation.route.name(),
        "watchOverflow": tab.watch_overflow_revision.is_some(),
        "history": tab.navigation.pane == Pane::History,
    })
}

pub fn group(group: &TabGroup) -> Value {
    json!({
        "id": group.id,
        "name": group.name,
        "color": group.color,
        "icon": group.icon,
        "collapsed": group.collapsed,
    })
}
