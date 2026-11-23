//! The History graph's rows: every row of the history, built on demand
//! from the loaded pages (the Dart `rowAt`). A row that is not loaded yet
//! is a placeholder and asks History to load its page.

use gitlama_workbench::history::HistoryService;
use gitlama_workbench::history_rows::{ReferenceContext, RowView, row_view};
use qtbridge::qtbridge_type_lib::{QByteArray, QHash, QModelIndex, QVariant};
use qtbridge::{QAbstractItemModel, QAbstractItemModelBase};
use serde_json::Value;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use crate::row_model::to_qvariant;

const ROLES: &[&str] = &[
    "objectId",
    "loading",
    "lit",
    "incomingLit",
    "graph",
    "occupiedLane",
    "subject",
    "worktree",
    "author",
    "avatarHash",
    "authorTime",
    "metadataFailure",
    "chips",
    "overflow",
    "detached",
    "current",
    "selected",
    "compared",
    "searchMatch",
    "refsText",
    "hiddenRefs",
];
const FIRST_ROLE: i32 = 0x100;

/// What the rows are built from.
#[derive(Default, Clone)]
pub struct HistorySource {
    pub history: Option<Rc<HistoryService>>,
    pub context: Rc<ReferenceContext>,
    pub head: Option<String>,
    /// The bound repository's pull requests, for the branch chips.
    pub hosting: Option<Rc<gitlama_workbench::hosting::RepositoryHosting>>,
}

/// `chips` with each branch's pull request (the Dart _withPullRequest): a
/// pull request stands at its head commit; when no chip of the branch is
/// there it stands on the remote-tracking chip, marked outdated, and the
/// branch is looked up again. Branches not looked up yet are asked for.
fn chips_with_pulls(chips: &Value, object_id: &str, hosting: &Rc<gitlama_workbench::hosting::RepositoryHosting>) -> Value {
    let Some(list) = chips.as_array() else { return chips.clone() };
    let mut branches = Vec::new();
    let mut out: Vec<Value> = list.clone();
    for chip in &mut out {
        let raw = chip["raw"].as_str().unwrap_or_default().to_owned();
        let tracking = chip["tracking"].as_str().map(str::to_owned);
        let Some(branch) = hosting.branch_for(&raw, tracking.as_deref()) else { continue };
        branches.push(branch.clone());
        let Some(pull) = hosting.shown_pull(&branch) else { continue };
        let at_head = !pull.head_sha.is_empty() && pull.head_sha == object_id;
        let remote_tracking = raw.starts_with("refs/remotes/");
        if !at_head && !(remote_tracking && !pull.head_sha.is_empty()) {
            continue;
        }
        let mut value = gitlama_workbench::hosting::pull_value(&pull);
        value["outdated"] = Value::Bool(!at_head);
        if !at_head {
            hosting.recheck_branch(&branch, object_id);
        }
        chip["pull"] = value;
    }
    // Rows report their branches while they build.
    if !branches.is_empty() {
        hosting.request_branches(branches);
    }
    Value::Array(out)
}

#[qtbridge::qobject(Base = QAbstractItemModel, ConvertToCamelCase)]
mod history_model {
    use super::*;

    #[derive(Default)]
    pub struct HistoryModel {
        source: HistorySource,
        total: i32,
        rows: RefCell<HashMap<i32, Rc<RowView>>>,
    }

    impl HistoryModel {
        #[qsignal]
        fn count_changed(&mut self);

        #[qslot]
        fn count(&self) -> i32 {
            self.total
        }

        /// The index of the loaded row of `object_id`, or -1.
        #[qslot]
        fn index_of(&self, object_id: String) -> i32 {
            self.source
                .history
                .as_ref()
                .and_then(|history| history.index_of_loaded(&object_id))
                .and_then(|index| i32::try_from(index).ok())
                .unwrap_or(-1)
        }

        /// The object id of row `index` ("" when it is not loaded).
        #[qslot]
        fn object_id_at(&self, index: i32) -> String {
            let row = self.view(index);
            if row.loading { String::new() } else { row.object_id.clone() }
        }
    }

    impl QAbstractItemModel for HistoryModel {
        fn index(&self, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex {
            if parent.is_valid() || column != 0 || row < 0 || row >= self.total {
                return QModelIndex::default();
            }
            self.create_index(row, column, 0)
        }

        fn parent(&self, _child: &QModelIndex) -> QModelIndex {
            QModelIndex::default()
        }

        fn row_count(&self, parent: &QModelIndex) -> i32 {
            if parent.is_valid() { 0 } else { self.total }
        }

        fn column_count(&self, parent: &QModelIndex) -> i32 {
            i32::from(!parent.is_valid())
        }

        fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
            let row = index.row();
            if row < 0 || row >= self.total {
                return QVariant::default();
            }
            let view = self.view(row);
            match ROLES.get((role - FIRST_ROLE) as usize).copied().unwrap_or_default() {
                "objectId" => QVariant::from(&view.object_id),
                "loading" => QVariant::from(view.loading),
                "lit" => QVariant::from(view.lit),
                "incomingLit" => QVariant::from(if row == 0 { view.lit } else { self.view(row - 1).lit }),
                "graph" => to_qvariant(&view.graph),
                "occupiedLane" => QVariant::from(view.occupied_lane as i32),
                "subject" => QVariant::from(&view.subject),
                "worktree" => QVariant::from(view.worktree),
                "author" => QVariant::from(&view.author),
                "avatarHash" => QVariant::from(&view.avatar_hash),
                "authorTime" => QVariant::from(view.author_time as f64),
                "metadataFailure" => view.metadata_failure.map(QVariant::from).unwrap_or_default(),
                "chips" => match &self.source.hosting {
                    Some(hosting) => to_qvariant(&chips_with_pulls(&view.chips, &view.object_id, hosting)),
                    None => to_qvariant(&view.chips),
                },
                "overflow" => to_qvariant(&view.overflow),
                "detached" => QVariant::from(view.detached),
                "current" => QVariant::from(view.current),
                "selected" => QVariant::from(view.selected),
                "compared" => QVariant::from(view.compared),
                "searchMatch" => QVariant::from(view.search_match),
                "refsText" => QVariant::from(&view.refs_text),
                "hiddenRefs" => QVariant::from(view.hidden_refs as i32),
                _ => QVariant::default(),
            }
        }

        fn role_names(&self) -> QHash<i32, QByteArray> {
            let mut names = QHash::<i32, QByteArray>::default();
            for (offset, name) in ROLES.iter().enumerate() {
                names.insert(&(FIRST_ROLE + offset as i32), &QByteArray::from(*name));
            }
            names
        }
    }

    impl HistoryModel {
        fn view(&self, row: i32) -> Rc<RowView> {
            if let Some(view) = self.rows.borrow().get(&row) {
                return Rc::clone(view);
            }
            let Some(history) = &self.source.history else {
                return Rc::new(row_view_placeholder(row));
            };
            let view = Rc::new(row_view(history, row as u64, &self.source.context, self.source.head.as_deref()));
            // Placeholders are asked again once their page arrives.
            if !view.loading {
                self.rows.borrow_mut().insert(row, Rc::clone(&view));
            }
            view
        }

        /// Shows `total` rows from `source`; every shown row is read again.
        pub fn publish(&mut self, source: HistorySource, total: i32) {
            self.source = source;
            self.rows.borrow_mut().clear();
            let previous = self.total;
            if total > previous {
                self.begin_insert_rows(&QModelIndex::default(), previous, total - 1);
                self.total = total;
                self.end_insert_rows();
            } else if total < previous {
                self.begin_remove_rows(&QModelIndex::default(), total, previous - 1);
                self.total = total;
                self.end_remove_rows();
            }
            if self.total > 0 {
                let top = self.create_index(0, 0, 0);
                let bottom = self.create_index(self.total - 1, 0, 0);
                self.data_changed(&top, &bottom);
            }
            if total != previous {
                self.count_changed();
            }
        }
    }
}

fn row_view_placeholder(row: i32) -> RowView {
    RowView {
        object_id: format!("loading-{row}"),
        loading: true,
        lit: false,
        graph: Value::Null,
        occupied_lane: 0,
        subject: String::new(),
        worktree: false,
        author: String::new(),
        avatar_hash: String::new(),
        author_time: 0,
        metadata_failure: None,
        chips: Value::Array(Vec::new()),
        overflow: Value::Null,
        detached: false,
        current: false,
        selected: false,
        compared: false,
        search_match: false,
        refs_text: String::new(),
        hidden_refs: 0,
    }
}

pub use history_model::HistoryModel;
