//! The file action catalogue (the Dart file_actions.dart): one ruleset
//! builds every file and folder menu of the product, so a file offers the
//! same actions wherever it is listed (docs/design-system/specs/
//! inspector.md §7). Hosts perform the actions; the catalogue only says
//! which ones a menu lists, in which groups, with which titles.

use gitlama_contract::dto::{NativeFileChangeKind, NativeTreeEntryKind};
use serde_json::{Value, json};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum FileAction {
    ShowDiff,
    ShowContents,
    Blame,
    FileHistory,
    FolderHistory,
    OpenInNewWindow,
    Stage,
    Unstage,
    InspectChanges,
    CreatePatch,
    ExternalDiff,
    OpenExternally,
    RevealInFileBrowser,
    CopyPath,
    AddToGitignore,
    Discard,
    Clean,
    RestoreFromCommit,
}

const ACTIONS: &[(FileAction, &str)] = &[
    (FileAction::ShowDiff, "showDiff"),
    (FileAction::ShowContents, "showContents"),
    (FileAction::Blame, "blame"),
    (FileAction::FileHistory, "fileHistory"),
    (FileAction::FolderHistory, "folderHistory"),
    (FileAction::OpenInNewWindow, "openInNewWindow"),
    (FileAction::Stage, "stage"),
    (FileAction::Unstage, "unstage"),
    (FileAction::InspectChanges, "inspectChanges"),
    (FileAction::CreatePatch, "createPatch"),
    (FileAction::ExternalDiff, "externalDiff"),
    (FileAction::OpenExternally, "openExternally"),
    (FileAction::RevealInFileBrowser, "revealInFileBrowser"),
    (FileAction::CopyPath, "copyPath"),
    (FileAction::AddToGitignore, "addToGitignore"),
    (FileAction::Discard, "discard"),
    (FileAction::Clean, "clean"),
    (FileAction::RestoreFromCommit, "restoreFromCommit"),
];

impl FileAction {
    pub fn name(self) -> &'static str {
        ACTIONS
            .iter()
            .find(|(action, _)| *action == self)
            .map(|(_, name)| *name)
            .unwrap_or_default()
    }

    pub fn parse(name: &str) -> Option<Self> {
        ACTIONS
            .iter()
            .find(|(_, candidate)| *candidate == name)
            .map(|(action, _)| *action)
    }

    pub fn all() -> impl Iterator<Item = Self> {
        ACTIONS.iter().map(|(action, _)| *action)
    }
}

/// Where the menu's file or folder is listed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
    /// A file the shown commit changed.
    CommittedFile,
    /// A file a comparison of two commits changed.
    ComparedFile,
    /// A file of All files that the shown commit did not change.
    TreeFile,
    /// A folder of All files or of the Changed tree.
    Folder,
    /// A file of a history entry.
    HistoryEntryFile,
    UnstagedFile,
    StagedFile,
    /// A folder of the Changes lists.
    ChangesFolder,
    ConflictFile,
    ReviewFile,
}

const SOURCES: &[(Source, &str)] = &[
    (Source::CommittedFile, "committedFile"),
    (Source::ComparedFile, "comparedFile"),
    (Source::TreeFile, "treeFile"),
    (Source::Folder, "folder"),
    (Source::HistoryEntryFile, "historyEntryFile"),
    (Source::UnstagedFile, "unstagedFile"),
    (Source::StagedFile, "stagedFile"),
    (Source::ChangesFolder, "changesFolder"),
    (Source::ConflictFile, "conflictFile"),
    (Source::ReviewFile, "reviewFile"),
];

impl Source {
    pub fn parse(name: &str) -> Option<Self> {
        SOURCES
            .iter()
            .find(|(_, candidate)| *candidate == name)
            .map(|(source, _)| *source)
    }
}

/// What a menu is about.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Subject {
    pub source: Source,
    /// The repository-relative path.
    pub path: String,
    /// How the shown commit changed the file.
    pub change: Option<NativeFileChangeKind>,
    pub tree: Option<NativeTreeEntryKind>,
    /// The file mode of a changed file, when known.
    pub mode: Option<u32>,
    /// Whether the path exists in the working tree, checked when the menu opens.
    pub exists: bool,
    /// A folder of the Changed tree, whose changed files can form a patch.
    pub changed_folder: bool,
    /// A folder (or file) of the staged list.
    pub staged: bool,
    /// Whether Discard or Clean applies.
    pub discardable: bool,
    /// An untracked file or folder, which Clean removes.
    pub untracked: bool,
}

impl Subject {
    pub fn new(source: Source, path: impl Into<String>) -> Self {
        Self {
            source,
            path: path.into(),
            change: None,
            tree: None,
            mode: None,
            exists: false,
            changed_folder: false,
            staged: false,
            discardable: false,
            untracked: false,
        }
    }

    pub fn is_folder(&self) -> bool {
        matches!(self.source, Source::Folder | Source::ChangesFolder)
    }

    /// Inspection actions of the working tree inspect the current commit.
    pub fn at_head(&self) -> bool {
        matches!(
            self.source,
            Source::UnstagedFile
                | Source::StagedFile
                | Source::ChangesFolder
                | Source::ConflictFile
        )
    }

    /// Reads a subject from the presentation: {source, path, change, tree,
    /// mode, exists, changedFolder, staged, discardable, untracked}.
    pub fn from_value(value: &Value) -> Option<Self> {
        let source = Source::parse(value.get("source")?.as_str()?)?;
        let flag = |name: &str| value.get(name).and_then(Value::as_bool).unwrap_or(false);
        Some(Self {
            source,
            path: value
                .get("path")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned(),
            change: value
                .get("change")
                .and_then(Value::as_str)
                .and_then(change_kind),
            tree: value
                .get("tree")
                .and_then(Value::as_str)
                .and_then(tree_kind),
            mode: value
                .get("mode")
                .and_then(Value::as_u64)
                .map(|mode| mode as u32),
            exists: flag("exists"),
            changed_folder: flag("changedFolder"),
            staged: flag("staged"),
            discardable: flag("discardable"),
            untracked: flag("untracked"),
        })
    }
}

pub fn change_kind(name: &str) -> Option<NativeFileChangeKind> {
    Some(match name {
        "modified" => NativeFileChangeKind::Modified,
        "added" => NativeFileChangeKind::Added,
        "deleted" => NativeFileChangeKind::Deleted,
        "renamed" => NativeFileChangeKind::Renamed,
        "copied" => NativeFileChangeKind::Copied,
        "modeChanged" => NativeFileChangeKind::ModeChanged,
        "typeChanged" => NativeFileChangeKind::TypeChanged,
        "binary" => NativeFileChangeKind::Binary,
        "image" => NativeFileChangeKind::Image,
        "submodule" => NativeFileChangeKind::Submodule,
        "conflict" => NativeFileChangeKind::Conflict,
        "untracked" => NativeFileChangeKind::Untracked,
        _ => return None,
    })
}

pub fn tree_kind(name: &str) -> Option<NativeTreeEntryKind> {
    Some(match name {
        "directory" => NativeTreeEntryKind::Directory,
        "file" => NativeTreeEntryKind::File,
        "symlink" => NativeTreeEntryKind::Symlink,
        "submodule" => NativeTreeEntryKind::Submodule,
        _ => return None,
    })
}

/// The multiple selection a Changes file belongs to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Selection {
    pub count: usize,
    pub staged: bool,
    /// Some(true) when Clean applies, Some(false) for Discard, None when
    /// neither does.
    pub clean: Option<bool>,
}

/// What a host can perform and why some actions are unavailable.
#[derive(Clone, Debug, Default)]
pub struct Host {
    pub capabilities: Vec<FileAction>,
    /// The file manager's name for "Reveal in …".
    pub file_browser: String,
    /// Why inspection actions are unavailable (an l10n key), or None.
    pub inspection_reason: Option<String>,
    /// Why an action is unavailable here (an l10n key). An action with a
    /// reason is listed disabled with it, even outside `capabilities`.
    pub reasons: Vec<(FileAction, String)>,
    pub busy: bool,
    pub allow_staging_while_busy: bool,
}

impl Host {
    fn reason(&self, action: FileAction) -> Option<&str> {
        self.reasons
            .iter()
            .find(|(candidate, _)| *candidate == action)
            .map(|(_, reason)| reason.as_str())
    }

    fn offers(&self, action: FileAction) -> bool {
        self.capabilities.contains(&action) || self.reason(action).is_some()
    }
}

const SYMLINK_MODE: u32 = 0xA000;
const GITLINK_MODE: u32 = 0xE000;
const MODE_TYPE: u32 = 0xF000;

/// Whether the inspector's lens rule lets (contents, blame) show `subject`.
fn lenses(subject: &Subject) -> (bool, bool) {
    let kind_of_mode = subject.mode.map(|mode| mode & MODE_TYPE);
    let submodule = subject.tree == Some(NativeTreeEntryKind::Submodule)
        || subject.change == Some(NativeFileChangeKind::Submodule)
        || kind_of_mode == Some(GITLINK_MODE);
    let symlink =
        subject.tree == Some(NativeTreeEntryKind::Symlink) || kind_of_mode == Some(SYMLINK_MODE);
    if subject.change == Some(NativeFileChangeKind::Deleted) || submodule {
        (false, false)
    } else if symlink
        || matches!(
            subject.change,
            Some(NativeFileChangeKind::Binary | NativeFileChangeKind::Image)
        )
    {
        (true, false)
    } else {
        (true, true)
    }
}

/// Whether the matrix of spec §7.1 offers `action` for `subject`, before
/// the host's capabilities apply.
pub fn applies(action: FileAction, subject: &Subject) -> bool {
    use Source::*;
    let source = subject.source;
    let committed = matches!(source, CommittedFile | ComparedFile);
    let history = source == HistoryEntryFile;
    let changes_file = matches!(source, UnstagedFile | StagedFile);
    let (contents, blame) = lenses(subject);
    match action {
        FileAction::ShowDiff => committed || history,
        // A submodule has no contents to show, wherever it is listed.
        FileAction::ShowContents => (committed || history || source == TreeFile) && contents,
        FileAction::Blame => {
            ((committed || history || source == TreeFile) && blame)
                || changes_file
                || matches!(source, ConflictFile | ReviewFile)
        }
        FileAction::FileHistory => !subject.is_folder(),
        FileAction::FolderHistory => subject.is_folder(),
        FileAction::OpenInNewWindow => committed || history || matches!(source, TreeFile | Folder),
        FileAction::Stage => source == UnstagedFile || (source == ChangesFolder && !subject.staged),
        FileAction::Unstage => source == StagedFile || (source == ChangesFolder && subject.staged),
        FileAction::InspectChanges => changes_file,
        FileAction::CreatePatch => {
            committed
                || changes_file
                || source == ChangesFolder
                || (source == Folder && subject.changed_folder)
        }
        FileAction::ExternalDiff => committed || history,
        FileAction::OpenExternally => {
            changes_file
                || source == ConflictFile
                || ((committed || history || matches!(source, TreeFile | ReviewFile))
                    && subject.exists)
        }
        FileAction::RevealInFileBrowser => {
            changes_file || matches!(source, ChangesFolder | ConflictFile) || subject.exists
        }
        FileAction::CopyPath => true,
        FileAction::AddToGitignore => {
            source == UnstagedFile || (source == ChangesFolder && !subject.staged)
        }
        FileAction::Discard => {
            matches!(source, UnstagedFile | ChangesFolder)
                && !subject.staged
                && subject.discardable
                && !subject.untracked
        }
        FileAction::Clean => {
            matches!(source, UnstagedFile | ChangesFolder)
                && !subject.staged
                && subject.discardable
                && subject.untracked
        }
        FileAction::RestoreFromCommit => {
            matches!(source, CommittedFile | TreeFile | HistoryEntryFile)
                && subject.change != Some(NativeFileChangeKind::Deleted)
        }
    }
}

const GROUPS: &[&[FileAction]] = &[
    &[
        FileAction::ShowDiff,
        FileAction::ShowContents,
        FileAction::Blame,
        FileAction::FileHistory,
        FileAction::FolderHistory,
        FileAction::OpenInNewWindow,
    ],
    &[
        FileAction::Stage,
        FileAction::Unstage,
        FileAction::InspectChanges,
    ],
    &[FileAction::CreatePatch, FileAction::ExternalDiff],
    &[
        FileAction::OpenExternally,
        FileAction::RevealInFileBrowser,
        FileAction::CopyPath,
    ],
    &[FileAction::AddToGitignore],
    &[
        FileAction::Discard,
        FileAction::Clean,
        FileAction::RestoreFromCommit,
    ],
];

const BUSY_ACTIONS: &[FileAction] = &[
    FileAction::Stage,
    FileAction::Unstage,
    FileAction::InspectChanges,
    FileAction::CreatePatch,
    FileAction::AddToGitignore,
    FileAction::Discard,
    FileAction::Clean,
    FileAction::RestoreFromCommit,
];

const INSPECTION_ACTIONS: &[FileAction] = &[
    FileAction::ShowDiff,
    FileAction::ShowContents,
    FileAction::Blame,
    FileAction::FileHistory,
    FileAction::FolderHistory,
    FileAction::OpenInNewWindow,
];

fn icon(action: FileAction, subject: &Subject) -> &'static str {
    match action {
        FileAction::ShowDiff | FileAction::CreatePatch => "file-diff",
        FileAction::ShowContents => "file-text",
        FileAction::Blame => "blame",
        FileAction::FileHistory | FileAction::FolderHistory => "history",
        FileAction::OpenInNewWindow => "app-window",
        FileAction::Stage => {
            if subject.is_folder() {
                "stage-all"
            } else {
                "plus"
            }
        }
        FileAction::Unstage => {
            if subject.is_folder() {
                "unstage-all"
            } else {
                "minus"
            }
        }
        FileAction::InspectChanges => "inspect",
        FileAction::ExternalDiff | FileAction::OpenExternally => "external-link",
        FileAction::RevealInFileBrowser => "folder-open",
        FileAction::CopyPath => "copy",
        FileAction::AddToGitignore => "eye-off",
        FileAction::Discard | FileAction::Clean => "trash",
        FileAction::RestoreFromCommit => "archive-restore",
    }
}

/// The l10n key of `action`'s title.
fn title_key(action: FileAction, subject: &Subject, in_selection: bool) -> &'static str {
    let folder = subject.is_folder();
    match action {
        FileAction::ShowDiff => "fileActionShowDiff",
        FileAction::ShowContents => "fileActionShowContents",
        FileAction::Blame => "historyBlame",
        FileAction::FileHistory => "fileActionFileHistory",
        FileAction::FolderHistory => "fileActionFolderHistory",
        FileAction::OpenInNewWindow => "inspectorOpenInWindow",
        FileAction::Stage => {
            if folder {
                "stageSelected"
            } else {
                "stageFile"
            }
        }
        FileAction::Unstage => {
            if folder {
                "unstageSelected"
            } else {
                "unstageFile"
            }
        }
        FileAction::InspectChanges => "inspectChanges",
        FileAction::CreatePatch => {
            if folder
                || (!in_selection
                    && matches!(subject.source, Source::UnstagedFile | Source::StagedFile))
            {
                "patchCreate"
            } else {
                "patchCreateFromFile"
            }
        }
        FileAction::ExternalDiff => "fileActionExternalDiff",
        FileAction::OpenExternally => "openFileExternal",
        FileAction::RevealInFileBrowser => "openInFileBrowser",
        FileAction::CopyPath => "copyFilePath",
        FileAction::AddToGitignore => "fileActionAddToGitignore",
        FileAction::Discard => {
            if folder {
                "discardSelected"
            } else {
                "discardFile"
            }
        }
        FileAction::Clean => {
            if folder {
                "discardSelected"
            } else {
                "cleanFile"
            }
        }
        FileAction::RestoreFromCommit => "historyRestoreFile",
    }
}

/// A title: {key, args}, wrapped in "… (HEAD)" by `head`.
fn title(key: &str, args: Value, head: bool) -> Value {
    let inner = json!({"key": key, "args": args});
    if head {
        json!({"key": "fileActionHeadSuffix", "args": {"action": inner}})
    } else {
        inner
    }
}

fn item(
    action: FileAction,
    selection: bool,
    title: Value,
    icon: &str,
    enabled: bool,
    reason: Option<&str>,
    danger: bool,
) -> Value {
    json!({
        "action": action.name(),
        "selection": selection,
        "title": title,
        "icon": icon,
        "enabled": enabled && reason.is_none(),
        "reason": reason,
        "danger": danger,
    })
}

/// The menu of `subject` for `host`: grouped, separated and in the order of
/// the inspector spec. `selection` adds the actions on the multiple
/// selection the file belongs to, under their own header. Items are
/// {separator: true}, {header: title} or {action, selection, title, icon,
/// enabled, reason, danger, unavailable}; a title is {key, args}, whose
/// args may themselves be titles, or {text}.
pub fn menu(subject: &Subject, host: &Host, selection: Option<Selection>) -> Vec<Value> {
    let mut items = Vec::new();
    let selection = selection.filter(|selection| selection.count >= 2);
    let in_selection = selection.is_some();
    if let Some(selection) = selection {
        items.push(
            json!({"header": title("menuSelectedFiles", json!({"count": selection.count}), false)}),
        );
        let stage = if selection.staged {
            FileAction::Unstage
        } else {
            FileAction::Stage
        };
        if host.offers(stage) {
            let (key, icon) = if selection.staged {
                ("unstageSelected", "unstage-all")
            } else {
                ("stageSelected", "stage-all")
            };
            items.push(item(
                stage,
                true,
                title(key, json!({}), false),
                icon,
                !host.busy || host.allow_staging_while_busy,
                host.reason(stage),
                false,
            ));
        }
        if host.offers(FileAction::CreatePatch) {
            items.push(item(
                FileAction::CreatePatch,
                true,
                title("patchCreateFromSelection", json!({}), false),
                "file-diff",
                !host.busy,
                host.reason(FileAction::CreatePatch),
                false,
            ));
        }
        if let (false, Some(clean)) = (selection.staged, selection.clean) {
            let action = if clean {
                FileAction::Clean
            } else {
                FileAction::Discard
            };
            if host.offers(action) {
                let key = if clean {
                    "cleanSelected"
                } else {
                    "discardSelected"
                };
                items.push(item(
                    action,
                    true,
                    title(key, json!({}), false),
                    "trash",
                    !host.busy,
                    host.reason(action),
                    true,
                ));
            }
        }
        let basename = subject.path.rsplit('/').next().unwrap_or_default();
        items.push(json!({"separator": true}));
        items.push(json!({"header": {"text": basename}}));
    }
    let mut first = true;
    for group in GROUPS {
        let entries: Vec<FileAction> = group
            .iter()
            .copied()
            .filter(|action| host.offers(*action) && applies(*action, subject))
            .collect();
        if entries.is_empty() {
            continue;
        }
        if !first {
            items.push(json!({"separator": true}));
        }
        first = false;
        for action in entries {
            let unavailable =
                host.inspection_reason.is_some() && INSPECTION_ACTIONS.contains(&action);
            let head = subject.at_head()
                && matches!(
                    action,
                    FileAction::Blame | FileAction::FileHistory | FileAction::FolderHistory
                );
            let args = if action == FileAction::RevealInFileBrowser {
                json!({"browser": host.file_browser})
            } else {
                json!({})
            };
            let busy = host.busy
                && BUSY_ACTIONS.contains(&action)
                && !(host.allow_staging_while_busy
                    && matches!(action, FileAction::Stage | FileAction::Unstage));
            let mut value = item(
                action,
                false,
                title(title_key(action, subject, in_selection), args, head),
                icon(action, subject),
                !unavailable && !busy,
                if unavailable {
                    None
                } else {
                    host.reason(action)
                },
                matches!(
                    action,
                    FileAction::Discard | FileAction::Clean | FileAction::RestoreFromCommit
                ),
            );
            if unavailable {
                value["unavailable"] = json!(host.inspection_reason);
            }
            items.push(value);
        }
    }
    items
}

#[cfg(test)]
mod tests {
    use super::*;

    /// English titles of the keys the catalogue uses (as rendered by the
    /// presentation), with '—' for separators and '#' before headers.
    fn english(key: &str) -> &str {
        match key {
            "fileActionShowDiff" => "Show diff",
            "fileActionShowContents" => "Show contents",
            "historyBlame" => "Blame",
            "fileActionFileHistory" => "File history",
            "fileActionFolderHistory" => "Folder history",
            "inspectorOpenInWindow" => "Open in new window",
            "stageSelected" => "Stage selected",
            "stageFile" => "Stage file",
            "unstageSelected" => "Unstage selected",
            "unstageFile" => "Unstage file",
            "inspectChanges" => "Inspect changes",
            "patchCreate" => "Create patch",
            "patchCreateFromFile" => "Create patch from this file",
            "patchCreateFromSelection" => "Create patch from selection",
            "fileActionExternalDiff" => "Open in external diff tool",
            "openFileExternal" => "Open in external editor",
            "copyFilePath" => "Copy path",
            "fileActionAddToGitignore" => "Add to .gitignore…",
            "discardSelected" => "Discard selected",
            "discardFile" => "Discard changes",
            "cleanFile" => "Delete untracked file",
            "cleanSelected" => "Clean selected",
            "historyRestoreFile" => "Restore this version",
            other => other,
        }
    }

    fn text(title: &Value) -> String {
        if let Some(text) = title.get("text").and_then(Value::as_str) {
            return text.to_owned();
        }
        let key = title["key"].as_str().unwrap();
        match key {
            "fileActionHeadSuffix" => format!("{} (HEAD)", text(&title["args"]["action"])),
            "openInFileBrowser" => {
                format!("Open in {}", title["args"]["browser"].as_str().unwrap())
            }
            "menuSelectedFiles" => format!("{} selected files", title["args"]["count"]),
            other => english(other).to_owned(),
        }
    }

    fn render(items: &[Value]) -> Vec<String> {
        items
            .iter()
            .map(|item| {
                if item.get("separator").is_some() {
                    "—".to_owned()
                } else if let Some(header) = item.get("header") {
                    format!("# {}", text(header))
                } else {
                    let mut shown = text(&item["title"]);
                    if let Some(reason) = item["unavailable"].as_str() {
                        shown = format!("{shown} — {reason}");
                    }
                    if item["danger"] == true {
                        shown.push_str(" !");
                    }
                    if item["enabled"] != true {
                        shown.push_str(" (off)");
                    }
                    shown
                }
            })
            .collect()
    }

    fn all() -> Host {
        Host {
            capabilities: FileAction::all().collect(),
            file_browser: "Files".into(),
            ..Host::default()
        }
    }

    fn subject(source: Source) -> Subject {
        Subject {
            exists: true,
            ..Subject::new(source, "lib/a.dart")
        }
    }

    fn check(subject: Subject, expected: &[&str]) {
        assert_eq!(
            render(&menu(&subject, &all(), None)),
            expected,
            "{:?}",
            subject.source
        );
    }

    #[test]
    fn the_matrix_of_every_source() {
        let modified = Some(NativeFileChangeKind::Modified);
        check(
            Subject {
                change: modified,
                ..subject(Source::CommittedFile)
            },
            &[
                "Show diff",
                "Show contents",
                "Blame",
                "File history",
                "Open in new window",
                "—",
                "Create patch from this file",
                "Open in external diff tool",
                "—",
                "Open in external editor",
                "Open in Files",
                "Copy path",
                "—",
                "Restore this version !",
            ],
        );
        check(
            Subject {
                change: modified,
                exists: false,
                ..subject(Source::ComparedFile)
            },
            &[
                "Show diff",
                "Show contents",
                "Blame",
                "File history",
                "Open in new window",
                "—",
                "Create patch from this file",
                "Open in external diff tool",
                "—",
                "Copy path",
            ],
        );
        check(
            subject(Source::TreeFile),
            &[
                "Show contents",
                "Blame",
                "File history",
                "Open in new window",
                "—",
                "Open in external editor",
                "Open in Files",
                "Copy path",
                "—",
                "Restore this version !",
            ],
        );
        check(
            Subject {
                exists: false,
                ..subject(Source::Folder)
            },
            &["Folder history", "Open in new window", "—", "Copy path"],
        );
        check(
            Subject {
                changed_folder: true,
                ..subject(Source::Folder)
            },
            &[
                "Folder history",
                "Open in new window",
                "—",
                "Create patch",
                "—",
                "Open in Files",
                "Copy path",
            ],
        );
        check(
            Subject {
                change: Some(NativeFileChangeKind::Added),
                exists: false,
                ..subject(Source::HistoryEntryFile)
            },
            &[
                "Show diff",
                "Show contents",
                "Blame",
                "File history",
                "Open in new window",
                "—",
                "Open in external diff tool",
                "—",
                "Copy path",
                "—",
                "Restore this version !",
            ],
        );
        let unstaged = [
            "Blame (HEAD)",
            "File history (HEAD)",
            "—",
            "Stage file",
            "Inspect changes",
            "—",
            "Create patch",
            "—",
            "Open in external editor",
            "Open in Files",
            "Copy path",
            "—",
            "Add to .gitignore…",
            "—",
        ];
        check(
            Subject {
                discardable: true,
                ..subject(Source::UnstagedFile)
            },
            &[&unstaged[..], &["Discard changes !"]].concat(),
        );
        check(
            Subject {
                discardable: true,
                untracked: true,
                ..subject(Source::UnstagedFile)
            },
            &[&unstaged[..], &["Delete untracked file !"]].concat(),
        );
        check(
            Subject {
                staged: true,
                ..subject(Source::StagedFile)
            },
            &[
                "Blame (HEAD)",
                "File history (HEAD)",
                "—",
                "Unstage file",
                "Inspect changes",
                "—",
                "Create patch",
                "—",
                "Open in external editor",
                "Open in Files",
                "Copy path",
            ],
        );
        check(
            Subject {
                discardable: true,
                ..subject(Source::ChangesFolder)
            },
            &[
                "Folder history (HEAD)",
                "—",
                "Stage selected",
                "—",
                "Create patch",
                "—",
                "Open in Files",
                "Copy path",
                "—",
                "Add to .gitignore…",
                "—",
                "Discard selected !",
            ],
        );
        check(
            subject(Source::ConflictFile),
            &[
                "Blame (HEAD)",
                "File history (HEAD)",
                "—",
                "Open in external editor",
                "Open in Files",
                "Copy path",
            ],
        );
        check(
            Subject {
                exists: false,
                ..subject(Source::ReviewFile)
            },
            &["Blame", "File history", "—", "Copy path"],
        );
    }

    #[test]
    fn deleted_binary_submodule_and_symlink_entries_hide_lenses_they_cannot_show() {
        let shown = |subject: Subject| render(&menu(&subject, &all(), None));
        let deleted = shown(Subject {
            change: Some(NativeFileChangeKind::Deleted),
            ..subject(Source::CommittedFile)
        });
        assert!(
            !deleted.contains(&"Show contents".to_owned())
                && !deleted.contains(&"Blame".to_owned())
        );
        assert!(!deleted.iter().any(|title| title.starts_with("Restore")));
        let binary = shown(Subject {
            change: Some(NativeFileChangeKind::Binary),
            ..subject(Source::CommittedFile)
        });
        assert!(
            binary.contains(&"Show contents".to_owned()) && !binary.contains(&"Blame".to_owned())
        );
        let submodule = shown(Subject {
            tree: Some(NativeTreeEntryKind::Submodule),
            ..subject(Source::TreeFile)
        });
        assert!(!submodule.contains(&"Show contents".to_owned()));
        let symlink = shown(Subject {
            mode: Some(0o120000),
            ..subject(Source::CommittedFile)
        });
        assert!(
            symlink.contains(&"Show contents".to_owned()) && !symlink.contains(&"Blame".to_owned())
        );
    }

    #[test]
    fn hosts_omit_actions_they_cannot_perform() {
        let host = Host {
            capabilities: vec![FileAction::CopyPath, FileAction::Stage],
            ..all()
        };
        let items = menu(
            &Subject {
                discardable: true,
                ..subject(Source::UnstagedFile)
            },
            &host,
            None,
        );
        assert_eq!(render(&items), ["Stage file", "—", "Copy path"]);
    }

    #[test]
    fn busy_hosts_disable_mutations_and_unavailable_inspection_says_why() {
        let host = Host {
            busy: true,
            inspection_reason: Some("Loading".into()),
            ..all()
        };
        let items = render(&menu(
            &Subject {
                discardable: true,
                ..subject(Source::UnstagedFile)
            },
            &host,
            None,
        ));
        assert_eq!(items[0], "Blame (HEAD) — Loading (off)");
        assert!(items.contains(&"Stage file (off)".to_owned()));
        assert!(items.contains(&"Copy path".to_owned()));
        assert!(items.contains(&"Discard changes ! (off)".to_owned()));
        let queueing = Host {
            busy: true,
            allow_staging_while_busy: true,
            ..all()
        };
        let items = render(&menu(&subject(Source::UnstagedFile), &queueing, None));
        assert!(items.contains(&"Stage file".to_owned()));
    }

    #[test]
    fn an_unavailable_action_stays_listed_disabled_with_its_reason() {
        let host = Host {
            capabilities: vec![FileAction::CopyPath],
            reasons: vec![(FileAction::Stage, "remoteUnavailable".into())],
            ..all()
        };
        let items = menu(&subject(Source::UnstagedFile), &host, None);
        assert_eq!(render(&items), ["Stage file (off)", "—", "Copy path"]);
        assert_eq!(items[0]["reason"], "remoteUnavailable");
    }

    #[test]
    fn a_multiple_selection_comes_first_under_its_own_header() {
        let selection = Selection {
            count: 3,
            staged: false,
            clean: Some(false),
        };
        let items = render(&menu(
            &Subject {
                discardable: true,
                ..subject(Source::UnstagedFile)
            },
            &all(),
            Some(selection),
        ));
        assert_eq!(
            items[..6],
            [
                "# 3 selected files",
                "Stage selected",
                "Create patch from selection",
                "Discard selected !",
                "—",
                "# a.dart"
            ]
        );
        // The pointed file's patch names the file once a selection is listed.
        assert!(items.contains(&"Create patch from this file".to_owned()));
        let single = render(&menu(
            &subject(Source::UnstagedFile),
            &all(),
            Some(Selection {
                count: 1,
                ..selection
            }),
        ));
        assert_eq!(single[0], "Blame (HEAD)");
    }

    #[test]
    fn no_menu_starts_ends_or_doubles_a_separator() {
        let sources = SOURCES.iter().map(|(source, _)| *source);
        for source in sources {
            for exists in [false, true] {
                let items = render(&menu(
                    &Subject {
                        exists,
                        discardable: true,
                        ..subject(source)
                    },
                    &all(),
                    None,
                ));
                assert_ne!(items.first().map(String::as_str), Some("—"));
                assert_ne!(items.last().map(String::as_str), Some("—"));
                assert!(
                    items
                        .windows(2)
                        .all(|pair| !(pair[0] == "—" && pair[1] == "—"))
                );
            }
        }
    }

    #[test]
    fn subjects_read_from_the_presentation() {
        let read = Subject::from_value(
            &json!({"source": "stagedFile", "path": "a/b", "staged": true, "change": "binary"}),
        )
        .unwrap();
        assert_eq!(read.source, Source::StagedFile);
        assert!(read.staged && !read.exists);
        assert_eq!(read.change, Some(NativeFileChangeKind::Binary));
        assert!(Subject::from_value(&json!({"source": "nowhere"})).is_none());
    }
}
