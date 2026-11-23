//! Projections of workbench state as plain values for QML.

use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::NativeRepositoryPhase;
use gitlama_workbench::entry::EntryState;
use gitlama_workbench::session::{basename, display_path};
use gitlama_workbench::workspace::{Pane, Tab, TabGroup, TabPhase};
use serde_json::{Value, json};

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

/// A tab's mark: the repository's image, icon or colour dot; null without
/// an appearance.
pub fn mark(
    appearances: &std::rc::Rc<gitlama_workbench::appearances::AppearanceService>,
    identity: Option<&NativePathIdentity>,
) -> Value {
    let Some(appearance) = appearances.appearance_for(identity) else {
        return Value::Null;
    };
    if !gitlama_workbench::appearances::has_mark(&appearance) {
        return Value::Null;
    }
    let image = appearance
        .image
        .as_ref()
        .and_then(|path| appearances.image_at(path))
        .map(|url| url.to_string());
    json!({
        "image": image,
        "icon": appearance.icon.filter(|icon| gitlama_workbench::appearance::is_icon(icon)),
        "color": appearance.color,
    })
}

pub fn tab(
    tab: &Tab,
    appearances: &std::rc::Rc<gitlama_workbench::appearances::AppearanceService>,
    remote_stale: bool,
) -> Value {
    let remote_profile = tab
        .canonical_identity()
        .or(tab.requested_identity.as_ref())
        .and_then(|identity| identity.remote.as_ref())
        .map(|remote| remote.profile_id.clone());
    let custom_name = appearances.name_for(tab.canonical_identity());
    let appearance = appearances.appearance_for(tab.canonical_identity());
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
        "remoteProfile": remote_profile,
        "remoteStale": remote_stale,
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
        "customName": custom_name,
        "hasCustomName": appearance.as_ref().is_some_and(|appearance| appearance.name.is_some()),
        "hasMark": appearance.as_ref().is_some_and(gitlama_workbench::appearances::has_mark),
        "mark": mark(appearances, tab.canonical_identity()),
        "ahead": status.map_or(0, |status| status.ahead),
        "behind": status.map_or(0, |status| status.behind),
        "hasStatus": status.is_some(),
        "detached": status.is_some_and(|status| status.branch_name.is_none()),
        "repositoryPath": tab.repository().map(display_path),
        "host": tab.canonical_identity().and_then(|identity| identity.remote.as_ref()).map(|remote| remote.profile_id.clone()),
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

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

fn operation_kind(kind: gitlama_contract::dto::NativeOperationKind) -> &'static str {
    use gitlama_contract::dto::NativeOperationKind as K;
    match kind {
        K::Merge => "merge",
        K::Rebase => "rebase",
        K::CherryPick => "cherryPick",
        K::Revert => "revert",
        K::Bisect => "bisect",
    }
}

/// The active tab's repository as the toolbar, Compass and command
/// availability read it.
pub fn active(tab: Option<&Tab>, group_name: Option<&str>) -> Value {
    use gitlama_contract::dto::{NativeChangeKind, NativeStatusEntryKind, NativeWorkingTreeState};
    let Some(tab) = tab else { return Value::Null };
    let session = tab.session.as_ref();
    let snapshot = session.map(|session| &*session.snapshot);
    let status = snapshot.and_then(|snapshot| snapshot.status.as_ref());
    let identity = snapshot.and_then(|snapshot| snapshot.identity.as_ref());
    let refs = snapshot.map(|snapshot| &snapshot.refs);
    // The checked-out branch: the status's, else HEAD's reference when it is
    // a local branch.
    let branch: Option<String> = match status {
        Some(status) => status.branch_name.as_deref().map(text),
        None => identity
            .and_then(|identity| identity.head_reference.as_deref())
            .and_then(|reference| reference.strip_prefix(b"refs/heads/"))
            .map(text),
    };
    let head_object_id = match status {
        Some(status) => status.head_object_id.clone(),
        None => identity.and_then(|identity| identity.head_object_id.clone()),
    };
    let head = refs.and_then(|refs| refs.branches.iter().find(|branch| branch.head));
    let conflicts = status.map_or(0, |status| {
        status
            .entries
            .iter()
            .filter(|entry| entry.kind == NativeStatusEntryKind::Unmerged)
            .count()
    });
    json!({
        "tabId": tab.id,
        "label": tab.label,
        "title": match group_name.filter(|name| !name.is_empty()) {
            Some(group) => json!({ "group": group, "name": tab.label }),
            None => json!({ "name": tab.label }),
        },
        "phase": phase(tab.phase),
        "hasSession": session.is_some(),
        "remote": tab.canonical_identity().is_some_and(|identity| identity.remote.is_some()),
        "pane": tab.navigation.pane.name(),
        "branchFilter": tab.navigation.branch_filter.references(),
        "remotes": session.map_or_else(Vec::new, |session| session.snapshot.refs.remotes.iter().map(|remote| String::from_utf8_lossy(&remote.name).into_owned()).collect()),
        "selectedIdentity": tab.navigation.selected_identity,
        "branch": branch,
        "detached": branch.is_none() && head_object_id.is_some(),
        "headObjectId": head_object_id,
        "hasStatus": status.is_some(),
        "ahead": status.map_or(0, |status| status.ahead),
        "behind": status.map_or(0, |status| status.behind),
        "dirty": status.map_or(0, |status| status.total_entries),
        "conflicts": conflicts,
        "staged": status.map_or(0, |status| status.entries.iter().filter(|entry| entry.index != NativeChangeKind::Unmodified).count()),
        "workingTree": status.map(|status| match status.working_tree {
            NativeWorkingTreeState::Clean => "clean",
            NativeWorkingTreeState::Dirty => "dirty",
            NativeWorkingTreeState::Conflicted => "conflicted",
        }),
        "operations": status.map_or(Vec::new(), |status| status.operations.iter().map(|operation| json!({
            "kind": operation_kind(operation.kind),
            "current": operation.current,
            "total": operation.total,
        })).collect()),
        "headRef": head.map(|head| text(&head.full_name)),
        "upstream": head.and_then(|head| head.upstream.as_deref()).map(text),
        "attached": status.is_some_and(|status| status.branch_name.is_some()) || head.is_some(),
        "branchCount": refs.map_or(0, |refs| refs.branches.len()),
        "remoteCount": refs.map_or(0, |refs| refs.remotes.len()),
        "remoteBranchCount": refs.map_or(0, |refs| refs.remotes.iter().map(|remote| remote.branches.len()).sum::<usize>()),
        "remoteBranchesOnlyHead": refs.is_none_or(|refs| refs.remotes.iter().all(|remote| remote.branches.iter().all(|branch| branch.name == b"HEAD"))),
        "tagCount": refs.map_or(0, |refs| refs.tags.len()),
        "stashCount": refs.map_or(0, |refs| refs.stashes.len()),
        "bare": identity.is_some_and(|identity| identity.kind == gitlama_contract::dto::NativeRepositoryKind::Bare),
        // The repository conditions banner.
        "watchOverflow": tab.watch_overflow_revision.is_some(),
        "watchFailure": snapshot.is_some_and(|snapshot| snapshot.watch_failure.is_some()),
        "statusFailure": snapshot.is_some_and(|snapshot| snapshot.status_failure.is_some()),
        "refsFailure": snapshot.is_some_and(|snapshot| snapshot.refs_failure.is_some()),
    })
}

/// The command registry, for menus, the palette and the toolbar.
pub fn commands() -> Value {
    serde_json::to_value(gitlama_workbench::commands::registry()).unwrap_or(Value::Null)
}

/// Each command's shortcut in effect on this platform: {id: {canonical,
/// sequence, global, keyHint}}; an invalid override document shows the
/// defaults.
pub fn shortcuts(overrides: &[gitlama_contract::storage::NativeShortcutOverride]) -> Value {
    use gitlama_workbench::commands;
    let mac = cfg!(target_os = "macos");
    let overrides = commands::without_retired(overrides);
    let bound = commands::resolve(&overrides, mac)
        .or_else(|_| commands::resolve(&[], mac))
        .unwrap_or_default();
    let shown = commands::shown(&overrides, mac)
        .or_else(|_| commands::shown(&[], mac))
        .unwrap_or_default();
    let mut map = serde_json::Map::new();
    for command in commands::registry() {
        let binding = bound.get(&command.id).cloned().flatten();
        let display = shown.get(&command.id).cloned().flatten();
        map.insert(
            command.id.clone(),
            json!({
                "canonical": display.as_ref().map(|shortcut| shortcut.canonical.clone()),
                "sequence": binding.as_ref().map(|shortcut| shortcut.qt_sequence(mac)),
                "scopes": command.scopes,
            }),
        );
    }
    Value::Object(map)
}
