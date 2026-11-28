//! The blame lens's lines: every line of the blamed file, read on demand
//! from the loaded pages. A line that is not loaded yet is a placeholder;
//! the view asks the inspector for its page.

use gitlama_contract::dto::NativeBlameRow;
use gitlama_workbench::inspector::BlameView;
use qtbridge::qtbridge_type_lib::{QByteArray, QHash, QModelIndex, QVariant};
use qtbridge::{QAbstractItemModel, QAbstractItemModelBase};
use std::rc::Rc;

const ROLES: &[&str] = &[
    "loading",
    "line",
    "content",
    "commit",
    "author",
    "summary",
    "authorTime",
    "boundary",
    "groupStart",
    "groupEnd",
];
const FIRST_ROLE: i32 = 0x100;

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

#[qtbridge::qobject(Base = QAbstractItemModel, ConvertToCamelCase)]
mod blame_model {
    use super::*;

    #[derive(Default)]
    pub struct BlameModel {
        view: Option<Rc<BlameView>>,
        total: i32,
    }

    impl BlameModel {
        #[qsignal]
        fn count_changed(&mut self);

        #[qslot]
        fn count(&self) -> i32 {
            self.total
        }
    }

    impl QAbstractItemModel for BlameModel {
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
            let line = index.row();
            if line < 0 || line >= self.total {
                return QVariant::default();
            }
            let row = self.row(line);
            let name = ROLES
                .get((role - FIRST_ROLE) as usize)
                .copied()
                .unwrap_or_default();
            let Some(row) = row else {
                return match name {
                    "loading" => QVariant::from(true),
                    "line" => QVariant::from(line + 1),
                    _ => QVariant::default(),
                };
            };
            match name {
                "loading" => QVariant::from(false),
                "line" => QVariant::from(row.final_line as i32),
                "content" => QVariant::from(
                    &text(&row.content)
                        .trim_end_matches(['\n', '\r'])
                        .replace('\t', "    "),
                ),
                "commit" => QVariant::from(row.commit.as_deref().unwrap_or_default()),
                "author" => QVariant::from(&text(&row.author)),
                "summary" => QVariant::from(&text(&row.summary)),
                "authorTime" => QVariant::from(row.author_time as f64),
                "boundary" => QVariant::from(row.boundary),
                "groupStart" => QVariant::from(
                    line == 0
                        || self
                            .row(line - 1)
                            .is_none_or(|previous| previous.commit != row.commit),
                ),
                "groupEnd" => QVariant::from(
                    line + 1 >= self.total
                        || self
                            .row(line + 1)
                            .is_none_or(|next| next.commit != row.commit),
                ),
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

    impl BlameModel {
        fn row(&self, line: i32) -> Option<&NativeBlameRow> {
            self.view.as_ref()?.rows.get(&(line as u64))
        }

        /// Shows `view`'s lines; every shown line is read again.
        pub fn publish(&mut self, view: Option<Rc<BlameView>>) {
            if match (&self.view, &view) {
                (Some(old), Some(new)) => Rc::ptr_eq(old, new),
                (None, None) => true,
                _ => false,
            } {
                return;
            }
            let total = view
                .as_ref()
                .map_or(0, |view| view.total_rows.min(i32::MAX as u64) as i32);
            let same_file = match (&self.view, &view) {
                (Some(old), Some(new)) => old.request_id == new.request_id,
                _ => false,
            };
            self.view = view;
            let previous = self.total;
            if !same_file {
                self.begin_reset_model();
                self.total = total;
                self.end_reset_model();
            } else if self.total > 0 {
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

pub use blame_model::BlameModel;
