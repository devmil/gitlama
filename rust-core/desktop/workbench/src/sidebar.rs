//! The workspace sidebar: the active
//! repository's branches, remotes, stashes, tags, worktrees, integrations and
//! pull requests as sections of nested entries, filtered by name and
//! flattened into the rows the sidebar list shows.
//!
//! Expansion choices live here, per repository, outside the disposable list
//! delegates. Sections start open except tags and pull requests; groups
//! start closed unless they hold the checked-out branch. While filtering,
//! matches start revealed and the durable choices stay untouched.

use crate::backend::SessionCalls;
use crate::history::BranchFilter;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::session::{basename, display_path};
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{
    NativeRepositoryReference, NativeRepositoryRefs, NativeRepositoryRemote,
    NativeRepositorySnapshot,
};
use gitlama_contract::extensions::{NativeExtensionInventory, NativeWorktreeEntry};
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

/// What activating a row does besides selecting it.
#[derive(Clone, Debug, PartialEq)]
pub enum Activate {
    Command(&'static str),
    OpenWorktree(usize),
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Entry {
    pub name: String,
    pub subtitle: String,
    pub tree_path: Option<String>,
    pub commands: Vec<&'static str>,
    pub primary_command: Option<&'static str>,
    pub target: Option<String>,
    pub command_name: Option<String>,
    pub merge_drop_target: bool,
    pub draggable_merge_source: bool,
    pub current: bool,
    pub current_description: Option<&'static str>,
    pub contains_current: bool,
    pub activate: Option<Activate>,
    pub ahead: u64,
    pub behind: u64,
    pub children: Vec<Entry>,
    pub filter_reference: Option<String>,
    pub filter_upstream: Option<String>,
    pub reveal_reference: Option<String>,
    pub icon: Option<&'static str>,
    /// A worktree row: its index in the inventory.
    pub worktree: Option<usize>,
    /// A worktree row: its folder.
    pub worktree_path: Option<String>,
    /// A worktree row: deleting it is refused up front.
    pub worktree_protected: bool,
    /// A pull request row: its page and the branch and commit to check out.
    pub pull_request: Option<PullRequestRow>,
    /// The CI state shown after the name (a branch with pull requests, the
    /// bound integration's main branch).
    pub hosting_check: Option<&'static str>,
    /// The branch `hosting_check` belongs to, when not the row's own.
    pub hosting_check_branch: Option<String>,
}

/// What a pull request row carries.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct PullRequestRow {
    pub web_url: String,
    /// The checks state when the provider reported one.
    pub checks: Option<&'static str>,
    pub conflicting: bool,
    /// "source into target" for the tooltip.
    pub branches: (String, String),
    /// An open pull request can be checked out: its branch and head.
    pub checkout: Option<(String, String)>,
}

impl Entry {
    fn identity(&self) -> &str {
        self.tree_path
            .as_deref()
            .or(self.command_name.as_deref())
            .unwrap_or(&self.name)
    }

    fn with_children(&self, children: Vec<Entry>) -> Entry {
        Entry {
            children,
            ..self.clone()
        }
    }
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

pub const STASH_REFERENCE: &str = "refs/stash";

fn local_branch_commands() -> Vec<&'static str> {
    vec![
        "checkoutBranch",
        "mergeBranch",
        "rebaseBranch",
        "restackBranches",
        "autoStashCheckout",
        "createBranch",
        "createTag",
        "renameBranch",
        "deleteBranch",
    ]
}

/// The symbolic `HEAD` of a remote names its default branch; deleting it
/// would delete no branch.
fn remote_branch_commands(name: &str) -> Vec<&'static str> {
    let mut commands = vec![
        "checkoutBranch",
        "mergeBranch",
        "rebaseBranch",
        "createBranch",
        "createTag",
    ];
    if name != "HEAD" {
        commands.push("deleteRemoteBranch");
    }
    commands
}

const TAG_COMMANDS: [&str; 2] = ["pushTag", "deleteTag"];
const STASH_COMMANDS: [&str; 4] = ["applyStash", "popStash", "renameStash", "dropStash"];
const REMOTE_COMMANDS: [&str; 6] = [
    "remoteFetch",
    "pull",
    "remotePush",
    "renameRemote",
    "editRemote",
    "removeRemote",
];

/// The names a repository's main branch goes by, the preferred one first.
pub const MAIN_BRANCH_NAMES: [&str; 2] = ["main", "master"];

/// `branches` with the main branch first and every other branch in order.
pub fn main_branch_first(
    branches: &[NativeRepositoryReference],
) -> Vec<&NativeRepositoryReference> {
    let main = MAIN_BRANCH_NAMES.iter().find_map(|name| {
        branches
            .iter()
            .position(|branch| branch.name == name.as_bytes())
    });
    let mut ordered: Vec<&NativeRepositoryReference> =
        main.map(|index| &branches[index]).into_iter().collect();
    ordered.extend(
        branches
            .iter()
            .enumerate()
            .filter(|(index, _)| Some(*index) != main)
            .map(|(_, branch)| branch),
    );
    ordered
}

fn full_name(reference: &NativeRepositoryReference, fallback: impl FnOnce() -> String) -> String {
    if reference.full_name.is_empty() {
        fallback()
    } else {
        text(&reference.full_name)
    }
}

pub fn branch_reference(branch: &NativeRepositoryReference) -> String {
    full_name(branch, || format!("refs/heads/{}", text(&branch.name)))
}

pub fn remote_branch_reference(
    remote: &NativeRepositoryRemote,
    branch: &NativeRepositoryReference,
) -> String {
    full_name(branch, || {
        format!("refs/remotes/{}/{}", text(&remote.name), text(&branch.name))
    })
}

pub fn tag_reference(tag: &NativeRepositoryReference) -> String {
    full_name(tag, || format!("refs/tags/{}", text(&tag.name)))
}

/// Whether `reference` is a remote's symbolic `HEAD`, which names no branch.
pub fn is_remote_head(reference: &str) -> bool {
    reference.starts_with("refs/remotes/") && reference.ends_with("/HEAD")
}

/// Whether `reference` names a branch the graph can be filtered to.
pub fn is_filterable_branch(reference: &str) -> bool {
    reference.starts_with("refs/heads/")
        || (reference.starts_with("refs/remotes/") && !is_remote_head(reference))
}

/// The branch shown along with `branch` in the graph filter: the one it
/// tracks, when the graph can be filtered to it.
pub fn filter_upstream(branch: &NativeRepositoryReference) -> Option<String> {
    let upstream = branch
        .upstream
        .as_ref()
        .filter(|_| !branch.upstream_gone)
        .map(|bytes| text(bytes))?;
    is_filterable_branch(&upstream).then_some(upstream)
}

/// The short display name of a full reference name.
pub fn display_reference(full: &str) -> &str {
    for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] {
        if let Some(short) = full.strip_prefix(prefix) {
            return short;
        }
    }
    if full == STASH_REFERENCE {
        "stash"
    } else {
        full
    }
}

/// Groups `entries` by their `/`-separated name segments; groups show only
/// their segment, commands keep the full name.
pub fn branch_tree(entries: Vec<Entry>, prefix: &str) -> Vec<Entry> {
    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, Vec<Entry>> = HashMap::new();
    for entry in entries {
        let segment = entry.name[prefix.len()..]
            .split('/')
            .next()
            .unwrap_or_default()
            .to_owned();
        if !groups.contains_key(&segment) {
            order.push(segment.clone());
        }
        groups.entry(segment).or_default().push(entry);
    }
    order
        .into_iter()
        .map(|segment| {
            let mut members = groups.remove(&segment).unwrap_or_default();
            let full = format!("{prefix}{segment}");
            if members.len() == 1 && members[0].name == full {
                let single = members.remove(0);
                Entry {
                    name: segment,
                    tree_path: Some(single.name.clone()),
                    command_name: Some(
                        single
                            .command_name
                            .clone()
                            .unwrap_or_else(|| single.name.clone()),
                    ),
                    ..single
                }
            } else {
                let path = format!("{full}/");
                Entry {
                    name: segment,
                    tree_path: Some(path.clone()),
                    contains_current: members.iter().any(|entry| entry.current),
                    children: branch_tree(members, &path),
                    ..Entry::default()
                }
            }
        })
        .collect()
}

/// The entries whose full name contains `needle` (lower-case), keeping the
/// groups and remotes that hold one.
pub fn filter_entries(entries: &[Entry], needle: &str) -> Vec<Entry> {
    let mut kept = Vec::new();
    for entry in entries {
        if entry.children.is_empty() {
            if entry
                .command_name
                .as_deref()
                .unwrap_or(&entry.name)
                .to_lowercase()
                .contains(needle)
            {
                kept.push(entry.clone());
            }
        } else {
            let children = filter_entries(&entry.children, needle);
            if !children.is_empty() {
                kept.push(entry.with_children(children));
            }
        }
    }
    kept
}

/// Sidebar entries derived from one reference snapshot.
/// Every reference at `commit` (branches, remote branches, tags), for the
/// History commit menu's submenus: (shown name, entry).
pub fn entries_at(refs: &NativeRepositoryRefs, commit: &str) -> Vec<(String, Entry)> {
    fn walk(entries: &[Entry], commit: &str, found: &mut Vec<(String, Entry)>) {
        for entry in entries {
            if entry.target.as_deref() == Some(commit)
                && (entry.filter_reference.is_some() || entry.command_name.is_some())
            {
                let name = entry
                    .command_name
                    .clone()
                    .unwrap_or_else(|| entry.name.clone());
                found.push((name, entry.clone()));
            }
            walk(&entry.children, commit, found);
        }
    }
    let references = References::new(refs);
    let mut found = Vec::new();
    walk(&references.branches, commit, &mut found);
    walk(&references.remotes, commit, &mut found);
    walk(&references.tags, commit, &mut found);
    found
}

pub struct References {
    pub current_branch: Option<String>,
    pub branches: Vec<Entry>,
    pub remotes: Vec<Entry>,
    pub tags: Vec<Entry>,
    pub stashes: Vec<Entry>,
}

impl References {
    pub fn new(refs: &NativeRepositoryRefs) -> Self {
        let local: Vec<Entry> = main_branch_first(&refs.branches)
            .into_iter()
            .map(local_branch)
            .collect();
        let current_branch = local
            .iter()
            .find(|entry| entry.current)
            .map(|entry| entry.name.clone());
        Self {
            current_branch,
            branches: branch_tree(local, ""),
            remotes: refs.remotes.iter().map(remote).collect(),
            tags: refs
                .tags
                .iter()
                .map(|tag| Entry {
                    name: text(&tag.name),
                    target: Some(tag.target.clone()),
                    commands: TAG_COMMANDS.to_vec(),
                    reveal_reference: Some(tag_reference(tag)),
                    ..Entry::default()
                })
                .collect(),
            stashes: refs
                .stashes
                .iter()
                .map(|stash| {
                    let selector = text(&stash.selector);
                    Entry {
                        name: text(&stash.subject),
                        command_name: Some(selector.clone()),
                        subtitle: selector.clone(),
                        primary_command: Some("applyStash"),
                        target: Some(stash.object_id.clone()),
                        // Only the newest stash is a reference; older ones are
                        // reflog entries the history graph does not load.
                        reveal_reference: (selector == "stash@{0}")
                            .then(|| STASH_REFERENCE.to_owned()),
                        commands: STASH_COMMANDS.to_vec(),
                        ..Entry::default()
                    }
                })
                .collect(),
        }
    }
}

fn local_branch(reference: &NativeRepositoryReference) -> Entry {
    let tracked = reference.upstream.is_some() && !reference.upstream_gone;
    Entry {
        name: text(&reference.name),
        ahead: if tracked { reference.ahead } else { 0 },
        behind: if tracked { reference.behind } else { 0 },
        primary_command: Some("checkoutBranch"),
        target: Some(reference.target.clone()),
        merge_drop_target: reference.head,
        draggable_merge_source: !reference.head,
        current: reference.head,
        commands: local_branch_commands(),
        filter_reference: Some(branch_reference(reference)),
        filter_upstream: filter_upstream(reference),
        ..Entry::default()
    }
}

fn remote(remote: &NativeRepositoryRemote) -> Entry {
    let branches = main_branch_first(&remote.branches)
        .into_iter()
        .map(|reference| {
            let name = text(&reference.name);
            let full = remote_branch_reference(remote, reference);
            Entry {
                commands: remote_branch_commands(&name),
                name,
                target: Some(reference.target.clone()),
                command_name: Some(display_reference(&full).to_owned()),
                filter_reference: (!is_remote_head(&full)).then_some(full),
                ..Entry::default()
            }
        })
        .collect();
    Entry {
        name: text(&remote.name),
        primary_command: Some("remoteFetch"),
        commands: REMOTE_COMMANDS.to_vec(),
        children: branch_tree(branches, ""),
        ..Entry::default()
    }
}

/// The entries of the worktree section.
pub fn worktree_entries(inventory: &NativeExtensionInventory) -> Vec<Entry> {
    inventory
        .worktrees
        .iter()
        .enumerate()
        .map(|(index, worktree)| {
            let root = display_path(&worktree.worktree_root);
            let name = match &worktree.branch {
                Some(branch) => display_reference(&text(branch)).to_owned(),
                None => basename(&worktree.worktree_root),
            };
            Entry {
                worktree_path: Some(root.clone()),
                worktree_protected: worktree_deletion_protected(inventory, worktree),
                tree_path: Some(root),
                name,
                current: worktree.current,
                current_description: worktree.current.then_some("extensionWorktreeCurrent"),
                activate: (!worktree.current).then_some(Activate::OpenWorktree(index)),
                worktree: Some(index),
                ..Entry::default()
            }
        })
        .collect()
}

/// Whether deleting `entry` is refused up front.
pub fn worktree_deletion_protected(
    inventory: &NativeExtensionInventory,
    entry: &NativeWorktreeEntry,
) -> bool {
    entry.current
        || entry.locked
        || inventory.worktrees.len() == 1
        || entry.git_dir == entry.common_git_dir
}

/// One sidebar section.
pub struct Section {
    pub command: &'static str,
    pub label: &'static str,
    pub icon: &'static str,
    pub count: u64,
    pub entries: Vec<Entry>,
    /// The section can be opened though it lists nothing yet.
    pub expandable: bool,
}

/// Filtered sections start open while filtering.
const FILTERED_SECTIONS: [&str; 3] = ["createBranch", "addRemote", "createTag"];

/// Whether any of `entries` is in the branch filter.
fn holds_filtered(entries: &[Entry], filter: &BranchFilter) -> bool {
    entries.iter().any(|entry| {
        entry
            .filter_reference
            .as_ref()
            .is_some_and(|reference| filter.contains(reference))
            || holds_filtered(&entry.children, filter)
    })
}

/// What the rows are flattened from.
pub struct Flatten<'a> {
    pub sections: &'a [Section],
    pub filtering: bool,
    pub choices: &'a HashMap<String, bool>,
    pub durable: &'a HashMap<String, bool>,
    pub selected: Option<&'a str>,
    pub branch_filter: &'a BranchFilter,
    pub has_repository: bool,
    /// Why the last worktree deletion failed (an l10n key), shown under
    /// the worktrees.
    pub worktree_failure: Option<&'a str>,
}

impl Flatten<'_> {
    fn section_expanded(&self, name: &str) -> bool {
        if let Some(choice) = self.choices.get(name) {
            return *choice;
        }
        let durable = self
            .durable
            .get(name)
            .copied()
            .unwrap_or(name != "createTag" && name != "hostingCreatePullRequest");
        if self.filtering {
            FILTERED_SECTIONS.contains(&name) || durable
        } else {
            durable
        }
    }

    /// The rows: a header per section, then its visible entries.
    pub fn rows(&self) -> Vec<Value> {
        let mut rows = Vec::new();
        for section in self.sections {
            let expanded = self.section_expanded(section.command);
            let expandable = !section.entries.is_empty() || section.expandable;
            rows.push(json!({
                "key": format!("section:{}", section.command),
                "kind": "section",
                "section": section.command,
                "name": section.label,
                "icon": section.icon,
                "count": section.count,
                "expanded": expanded && expandable,
                "hasChildren": expandable,
                "depth": 0,
            }));
            if expanded && !section.entries.is_empty() {
                self.flatten(&mut rows, section, &section.entries, section.command, 0);
            }
            if section.command == "addWorktree"
                && let Some(failure) = self.worktree_failure
            {
                rows.push(json!({"key": "banner:addWorktree", "kind": "banner", "section": section.command, "name": failure, "depth": 0}));
            }
        }
        rows
    }

    fn flatten(
        &self,
        rows: &mut Vec<Value>,
        section: &Section,
        entries: &[Entry],
        path: &str,
        depth: usize,
    ) {
        for entry in entries {
            let entry_path = format!("{path}/{}", entry.identity());
            let has_children = !entry.children.is_empty();
            let expanded = has_children
                && self
                    .choices
                    .get(&entry_path)
                    .copied()
                    .unwrap_or(self.filtering || entry.contains_current);
            let reference = entry.identity().to_owned();
            let filtered = entry
                .filter_reference
                .as_ref()
                .is_some_and(|name| self.branch_filter.contains(name));
            let holds = has_children
                && !expanded
                && !self.branch_filter.is_empty()
                && holds_filtered(&entry.children, self.branch_filter);
            let icon = if entry.current {
                "check"
            } else if has_children {
                "folder-closed"
            } else {
                entry.icon.unwrap_or(section.icon)
            };
            let activate = match &entry.activate {
                Some(Activate::Command(command)) => json!({"command": command}),
                Some(Activate::OpenWorktree(index)) => json!({"worktree": index}),
                None => Value::Null,
            };
            rows.push(json!({
                "key": entry_path,
                "kind": "ref",
                "section": section.command,
                "name": entry.name,
                "reference": reference,
                "selected": self.selected == Some(reference.as_str()),
                "icon": icon,
                "depth": depth,
                "hasChildren": has_children,
                "expanded": expanded,
                "current": entry.current,
                "currentDescription": entry.current_description,
                "subtitle": entry.subtitle,
                "ahead": entry.ahead,
                "behind": entry.behind,
                "filtered": filtered,
                "holdsFiltered": holds,
                "commands": entry.commands,
                "primaryCommand": entry.primary_command,
                "target": entry.target,
                "commandName": entry.command_name.clone().unwrap_or_else(|| entry.name.clone()),
                "filterReference": entry.filter_reference,
                "filterUpstream": entry.filter_upstream,
                "revealReference": entry.reveal_reference,
                "draggable": entry.draggable_merge_source && entry.target.is_some(),
                "dropTarget": entry.merge_drop_target,
                "activate": activate,
                "worktree": entry.worktree,
                "worktreePath": entry.worktree_path,
                "worktreeProtected": entry.worktree_protected,
                "pullRequest": entry.pull_request.as_ref().map(|pull| json!({
                    "webUrl": pull.web_url,
                    "checks": pull.checks,
                    "conflicting": pull.conflicting,
                    "source": pull.branches.0,
                    "target": pull.branches.1,
                    "checkoutBranch": pull.checkout.as_ref().map(|checkout| checkout.0.clone()),
                    "checkoutTarget": pull.checkout.as_ref().map(|checkout| checkout.1.clone()),
                })),
                "hostingCheck": entry.hosting_check,
                "hostingCheckBranch": entry.hosting_check_branch,
                "hasMenu": !entry.commands.is_empty() || entry.worktree.is_some() || entry.activate.is_some() || entry.pull_request.is_some(),
            }));
            if expanded {
                self.flatten(rows, section, &entry.children, &entry_path, depth + 1);
            }
        }
    }
}

#[derive(Default)]
struct Filter {
    open: bool,
    text: String,
    choices: HashMap<String, bool>,
}

impl Filter {
    fn needle(&self) -> String {
        if self.open {
            self.text.trim().to_lowercase()
        } else {
            String::new()
        }
    }
}

struct Worktrees {
    revision: u64,
    session: u64,
    inventory: Option<Rc<NativeExtensionInventory>>,
    loading: bool,
}

#[derive(Default)]
struct Inner {
    repository: Option<NativePathIdentity>,
    expansion: HashMap<Option<NativePathIdentity>, HashMap<String, bool>>,
    filter: Filter,
    references: Option<(Rc<NativeRepositorySnapshot>, Rc<References>)>,
    worktrees: Option<Worktrees>,
    worktree_failure: Option<&'static str>,
    pull_requests: Vec<Entry>,
    /// Hosting's CI state per local branch, and the bound integration's row.
    hosting: (HashMap<String, &'static str>, Option<Entry>),
}

/// The sidebar's state: expansion, the reference filter and the worktree
/// inventory of the active repository.
pub struct SidebarService {
    workspace: Rc<WorkspaceService>,
    settings: Rc<SettingsService>,
    calls: Rc<dyn SessionCalls>,
    notifier: Notifier,
    inner: RefCell<Inner>,
}

/// The sidebar projection.
pub struct Projection {
    pub rows: Vec<Value>,
    pub header: Value,
}

impl SidebarService {
    pub fn new(
        workspace: Rc<WorkspaceService>,
        settings: Rc<SettingsService>,
        calls: Rc<dyn SessionCalls>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            workspace,
            settings,
            calls,
            notifier,
            inner: RefCell::new(Inner::default()),
        })
    }

    fn changed(&self) {
        self.notifier.notify(Topics::WORKSPACE);
    }

    /// Opens or closes the row (or section) at `path`.
    pub fn set_expanded(&self, path: String, expanded: bool) {
        {
            let mut inner = self.inner.borrow_mut();
            if !inner.filter.needle().is_empty() {
                inner.filter.choices.insert(path, expanded);
            } else {
                let repository = inner.repository.clone();
                inner
                    .expansion
                    .entry(repository)
                    .or_default()
                    .insert(path, expanded);
            }
        }
        self.changed();
    }

    /// Shows, edits or (with `open` false) clears the reference filter.
    pub fn set_filter(&self, open: bool, text: String) {
        {
            let mut inner = self.inner.borrow_mut();
            if !open {
                inner.filter = Filter::default();
            } else {
                if inner.filter.text.trim().to_lowercase() != text.trim().to_lowercase() {
                    // A new needle starts from revealed matches again.
                    inner.filter.choices.clear();
                }
                inner.filter.open = true;
                inner.filter.text = text;
            }
        }
        self.changed();
    }

    /// The pull request rows (linked pull requests of the active repository).
    /// Hosting's CI decorations: the state of each local branch with pull
    /// requests and the bound integration's row.
    pub fn set_hosting(
        self: &Rc<Self>,
        decorations: HashMap<String, &'static str>,
        bound: Option<Entry>,
    ) {
        let next = (decorations, bound);
        if self.inner.borrow().hosting != next {
            self.inner.borrow_mut().hosting = next;
            self.changed();
        }
    }

    pub fn set_pull_requests(self: &Rc<Self>, entries: Vec<Entry>) {
        if self.inner.borrow().pull_requests != entries {
            self.inner.borrow_mut().pull_requests = entries;
            self.changed();
        }
    }

    /// The worktree inventory, when loaded.
    pub fn worktrees(&self) -> Option<Rc<NativeExtensionInventory>> {
        self.inner
            .borrow()
            .worktrees
            .as_ref()
            .and_then(|worktrees| worktrees.inventory.clone())
    }

    /// Reloads the worktree inventory now (after opening its section).
    /// Shows (or clears) why the last worktree deletion failed.
    pub fn set_worktree_failure(&self, failure: Option<&'static str>) {
        if self.inner.borrow().worktree_failure != failure {
            self.inner.borrow_mut().worktree_failure = failure;
            self.changed();
        }
    }

    pub fn reload_worktrees(self: &Rc<Self>) {
        self.inner.borrow_mut().worktrees = None;
        self.changed();
    }

    fn ensure_worktrees(
        self: &Rc<Self>,
        snapshot: &NativeRepositorySnapshot,
        session: u64,
        generation: u64,
    ) {
        if snapshot.ref_counts.worktrees == 0 {
            self.inner.borrow_mut().worktrees = None;
            return;
        }
        {
            let inner = self.inner.borrow();
            if let Some(worktrees) = &inner.worktrees
                && worktrees.session == session
                && worktrees.revision == snapshot.revision
            {
                return;
            }
        }
        let previous = self
            .inner
            .borrow_mut()
            .worktrees
            .take()
            .and_then(|worktrees| worktrees.inventory);
        self.inner.borrow_mut().worktrees = Some(Worktrees {
            revision: snapshot.revision,
            session,
            inventory: previous,
            loading: true,
        });
        let this = Rc::clone(self);
        let revision = snapshot.revision;
        let request = self
            .calls
            .repository_session_extensions(session, generation);
        rt::spawn_detached(async move {
            let result = request.await;
            let inventory = result.ok().and_then(|result| result.inventory).map(Rc::new);
            let mut inner = this.inner.borrow_mut();
            if let Some(worktrees) = inner.worktrees.as_mut()
                && worktrees.session == session
                && worktrees.revision == revision
            {
                worktrees.loading = false;
                if inventory.is_some() {
                    worktrees.inventory = inventory;
                }
                drop(inner);
                this.changed();
            }
        });
    }

    /// The rows and header the sidebar shows for the active tab, with the
    /// reference `selected` there.
    pub fn project(self: &Rc<Self>, selected: Option<&str>) -> Projection {
        let active = self.workspace.active_tab();
        let session = active.as_ref().and_then(|tab| tab.session.clone());
        let repository = active
            .as_ref()
            .and_then(|tab| tab.canonical_identity().cloned());
        {
            let mut inner = self.inner.borrow_mut();
            if inner.repository != repository {
                inner.repository = repository.clone();
                inner.filter = Filter::default();
                inner.worktrees = None;
            }
        }
        if let Some(session) = &session {
            self.ensure_worktrees(
                &session.snapshot,
                session.identity.native_id,
                session.identity.generation,
            );
        }
        let references = session.as_ref().map(|session| {
            // The snapshot is kept, so a new one never reuses its address.
            let cached = self
                .inner
                .borrow()
                .references
                .as_ref()
                .filter(|(snapshot, _)| Rc::ptr_eq(snapshot, &session.snapshot))
                .map(|(_, references)| Rc::clone(references));
            cached.unwrap_or_else(|| {
                let built = Rc::new(References::new(&session.snapshot.refs));
                self.inner.borrow_mut().references =
                    Some((Rc::clone(&session.snapshot), Rc::clone(&built)));
                built
            })
        });
        let inner = self.inner.borrow();
        let needle = inner.filter.needle();
        let filtering = !needle.is_empty();
        let counts = session
            .as_ref()
            .map(|session| session.snapshot.ref_counts.clone())
            .unwrap_or_default();
        let empty = References {
            current_branch: None,
            branches: vec![],
            remotes: vec![],
            tags: vec![],
            stashes: vec![],
        };
        let references_ref: &References = references.as_deref().unwrap_or(&empty);
        let (branches, remotes, tags) = if filtering {
            (
                filter_entries(&references_ref.branches, &needle),
                filter_entries(&references_ref.remotes, &needle),
                filter_entries(&references_ref.tags, &needle),
            )
        } else {
            (
                references_ref.branches.clone(),
                references_ref.remotes.clone(),
                references_ref.tags.clone(),
            )
        };
        let no_matches = filtering && branches.is_empty() && remotes.is_empty() && tags.is_empty();
        let worktree_inventory = inner
            .worktrees
            .as_ref()
            .and_then(|worktrees| worktrees.inventory.clone());
        let (decorations, bound) = inner.hosting.clone();
        fn decorate(entries: &mut [Entry], decorations: &HashMap<String, &'static str>) {
            for entry in entries {
                if let Some(branch) = entry
                    .filter_reference
                    .as_deref()
                    .and_then(|reference| reference.strip_prefix("refs/heads/"))
                {
                    entry.hosting_check = decorations.get(branch).copied();
                }
                decorate(&mut entry.children, decorations);
            }
        }
        let mut branches = branches;
        if !decorations.is_empty() {
            decorate(&mut branches, &decorations);
        }
        let integrations: Vec<Entry> = bound
            .into_iter()
            .chain(self.settings.with(|document| {
                document
                    .integrations
                    .iter()
                    .map(|integration| Entry {
                        name: integration.id.clone(),
                        subtitle: integration.kind.clone(),
                        commands: vec!["addIntegration"],
                        activate: Some(Activate::Command("addIntegration")),
                        icon: None,
                        ..Entry::default()
                    })
                    .collect::<Vec<_>>()
            }))
            .collect();
        let sections = vec![
            Section {
                command: "createBranch",
                label: "workspaceBranches",
                icon: "branch",
                count: counts.branches,
                entries: branches,
                expandable: false,
            },
            Section {
                command: "addRemote",
                label: "workspaceRemotes",
                icon: "cloud",
                count: counts.remotes,
                entries: remotes,
                expandable: false,
            },
            Section {
                command: "createStash",
                label: "workspaceStashes",
                icon: "stash",
                count: counts.stashes,
                entries: references_ref.stashes.clone(),
                expandable: false,
            },
            Section {
                command: "createTag",
                label: "workspaceTags",
                icon: "tag",
                count: counts.tags,
                entries: tags,
                expandable: false,
            },
            Section {
                command: "addWorktree",
                label: "workspaceWorktrees",
                icon: "folder-symlink",
                count: counts.worktrees,
                entries: worktree_inventory
                    .as_deref()
                    .map(worktree_entries)
                    .unwrap_or_default(),
                expandable: counts.worktrees > 0,
            },
            Section {
                command: "trackLfsPattern",
                label: "extensionLfs",
                icon: "box",
                count: 0,
                entries: vec![],
                expandable: false,
            },
            Section {
                command: "addIntegration",
                label: "integrationTitle",
                icon: "command",
                count: integrations.len() as u64,
                entries: integrations,
                expandable: false,
            },
            Section {
                command: "hostingCreatePullRequest",
                label: "hostingChangeRequests",
                icon: "git-pull-request",
                count: inner.pull_requests.len() as u64,
                entries: inner.pull_requests.clone(),
                expandable: false,
            },
        ];
        let empty_choices = HashMap::new();
        let durable = inner.expansion.get(&repository).unwrap_or(&empty_choices);
        let branch_filter = active
            .as_ref()
            .map(|tab| tab.navigation.branch_filter.clone())
            .unwrap_or_default();
        let flatten = Flatten {
            sections: &sections,
            filtering,
            choices: if filtering {
                &inner.filter.choices
            } else {
                durable
            },
            durable,
            selected,
            branch_filter: &branch_filter,
            has_repository: session.is_some(),
            worktree_failure: inner.worktree_failure,
        };
        let rows = flatten.rows();
        let header = json!({
            "hasRepository": flatten.has_repository,
            "filterOpen": inner.filter.open,
            "noMatches": no_matches,
            "currentBranch": references_ref.current_branch,
        });
        Projection { rows, header }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn branch(name: &str, head: bool) -> NativeRepositoryReference {
        NativeRepositoryReference {
            name: name.as_bytes().to_vec(),
            full_name: format!("refs/heads/{name}").into_bytes(),
            target: format!("{name}-oid"),
            head,
            published: false,
            upstream: None,
            ahead: 0,
            behind: 0,
            upstream_gone: false,
        }
    }

    fn refs() -> NativeRepositoryRefs {
        NativeRepositoryRefs {
            branches: vec![
                branch("feature/a", false),
                branch("feature/b", true),
                branch("main", false),
                branch("topic", false),
            ],
            remotes: vec![],
            tags: vec![],
            stashes: vec![],
            truncated: false,
        }
    }

    #[test]
    fn groups_branches_and_puts_main_first() {
        let references = References::new(&refs());
        let names: Vec<&str> = references
            .branches
            .iter()
            .map(|entry| entry.name.as_str())
            .collect();
        assert_eq!(names, ["main", "feature", "topic"]);
        let feature = &references.branches[1];
        assert_eq!(feature.tree_path.as_deref(), Some("feature/"));
        assert!(feature.contains_current);
        assert_eq!(feature.children[1].tree_path.as_deref(), Some("feature/b"));
        assert_eq!(references.current_branch.as_deref(), Some("feature/b"));
    }

    #[test]
    fn filters_keep_groups_that_hold_matches() {
        let references = References::new(&refs());
        let kept = filter_entries(&references.branches, "b");
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].children.len(), 1);
        assert_eq!(kept[0].children[0].name, "b");
    }

    #[test]
    fn flattens_with_default_expansion() {
        let references = References::new(&refs());
        let sections = vec![
            Section {
                command: "createBranch",
                label: "",
                icon: "branch",
                count: 4,
                entries: references.branches.clone(),
                expandable: false,
            },
            Section {
                command: "createTag",
                label: "",
                icon: "tag",
                count: 1,
                entries: vec![Entry {
                    name: "v1".into(),
                    ..Entry::default()
                }],
                expandable: false,
            },
        ];
        let choices = HashMap::new();
        let filter = BranchFilter::default();
        let rows = Flatten {
            sections: &sections,
            filtering: false,
            choices: &choices,
            durable: &choices,
            selected: Some("main"),
            branch_filter: &filter,
            has_repository: true,
            worktree_failure: None,
        }
        .rows();
        let keys: Vec<&str> = rows
            .iter()
            .map(|row| row["key"].as_str().unwrap())
            .collect();
        // The group holding the current branch is open; tags start closed.
        assert_eq!(
            keys,
            [
                "section:createBranch",
                "createBranch/main",
                "createBranch/feature/",
                "createBranch/feature//feature/a",
                "createBranch/feature//feature/b",
                "createBranch/topic",
                "section:createTag",
            ]
        );
        assert_eq!(rows[1]["selected"], true);
        assert_eq!(rows[4]["icon"], "check");
    }
}
