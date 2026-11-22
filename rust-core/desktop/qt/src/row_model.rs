//! A list model of JSON rows with stable keys. Publishing a new row list
//! removes and inserts only the rows whose keys came or went, and reports
//! changed roles for the rest, so QML views keep their delegates, scroll
//! position and add/remove transitions.

use qtbridge::qtbridge_type_lib::{QByteArray, QHash, QList, QMap, QModelIndex, QString, QVariant};
use qtbridge::{QAbstractItemModel, QAbstractItemModelBase};
use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};

const FIRST_ROLE: i32 = 0x100;

/// Converts a JSON value to the QVariant QML reads.
pub fn to_qvariant(value: &Value) -> QVariant {
    match value {
        Value::Null => QVariant::default(),
        Value::Bool(value) => QVariant::from(*value),
        Value::Number(number) => match number.as_i64() {
            Some(integer) if i32::try_from(integer).is_ok() => QVariant::from(integer as i32),
            Some(integer) => QVariant::from(integer as f64),
            None => QVariant::from(number.as_f64().unwrap_or_default()),
        },
        Value::String(text) => QVariant::from(text),
        Value::Array(items) => {
            let list: QList<QVariant> = items.iter().map(to_qvariant).collect::<Vec<_>>().into();
            QVariant::from(&list)
        }
        Value::Object(fields) => {
            let mut map = QMap::<QString, QVariant>::default();
            for (key, value) in fields {
                map.insert(&QString::from(key.as_str()), &to_qvariant(value));
            }
            QVariant::from(&map)
        }
    }
}

/// The steps that turn one keyed row list into another.
#[derive(Debug, PartialEq, Eq)]
pub enum Step {
    /// Remove `count` rows from `first` (applied in order).
    Remove { first: usize, count: usize },
    /// Insert `count` rows of the new list at `first` (applied in order).
    Insert { first: usize, count: usize },
    /// The rows from `first` to `last` changed in place.
    Change { first: usize, last: usize },
    /// The order changed: replace everything.
    Reset,
}

/// Plans the steps from `old` keys to `new` keys; `changed(old, new)` says
/// whether the row kept under one key differs.
pub fn plan(old: &[String], new: &[String], changed: impl Fn(usize, usize) -> bool) -> Vec<Step> {
    let new_keys: HashSet<&String> = new.iter().collect();
    if new_keys.len() != new.len() {
        return vec![Step::Reset];
    }
    let old_keys: HashSet<&String> = old.iter().collect();
    if old_keys.len() != old.len() {
        return vec![Step::Reset];
    }
    let kept_old: Vec<&String> = old.iter().filter(|key| new_keys.contains(key)).collect();
    let kept_new: Vec<&String> = new.iter().filter(|key| old_keys.contains(key)).collect();
    if kept_old != kept_new {
        return vec![Step::Reset];
    }
    let mut steps = Vec::new();
    // Removals from the back, so earlier indices stay valid.
    let mut index = old.len();
    while index > 0 {
        if new_keys.contains(&old[index - 1]) {
            index -= 1;
            continue;
        }
        let last = index;
        while index > 0 && !new_keys.contains(&old[index - 1]) {
            index -= 1;
        }
        steps.push(Step::Remove { first: index, count: last - index });
    }
    // Insertions from the front, at their final positions.
    let mut index = 0;
    while index < new.len() {
        if old_keys.contains(&new[index]) {
            index += 1;
            continue;
        }
        let first = index;
        while index < new.len() && !old_keys.contains(&new[index]) {
            index += 1;
        }
        steps.push(Step::Insert { first, count: index - first });
    }
    let old_index: HashMap<&String, usize> = old.iter().enumerate().map(|(i, key)| (key, i)).collect();
    let mut run: Option<(usize, usize)> = None;
    for (position, key) in new.iter().enumerate() {
        let differs = old_index.get(key).is_some_and(|&previous| changed(previous, position));
        match (differs, run) {
            (true, Some((first, last))) if last + 1 == position => run = Some((first, position)),
            (true, Some((first, last))) => {
                steps.push(Step::Change { first, last });
                run = Some((position, position));
            }
            (true, None) => run = Some((position, position)),
            (false, _) => {}
        }
    }
    if let Some((first, last)) = run {
        steps.push(Step::Change { first, last });
    }
    steps
}

#[qtbridge::qobject(Base = QAbstractItemModel, ConvertToCamelCase)]
mod row_model {
    use super::*;

    #[derive(Default)]
    pub struct RowModel {
        roles: Vec<String>,
        key: String,
        keys: Vec<String>,
        rows: Vec<Map<String, Value>>,
    }

    impl RowModel {
        #[qsignal]
        fn count_changed(&mut self);

        #[qslot]
        fn count(&self) -> i32 {
            i32::try_from(self.rows.len()).unwrap_or(i32::MAX)
        }

        /// The row at `index` as one object, for QML code outside delegates.
        #[qslot]
        fn get(&self, index: i32) -> Value {
            usize::try_from(index)
                .ok()
                .and_then(|index| self.rows.get(index))
                .map(|row| Value::Object(row.clone()))
                .unwrap_or(Value::Null)
        }

        /// The index of the row with key `key`, or -1.
        #[qslot]
        fn index_of(&self, key: String) -> i32 {
            self.keys
                .iter()
                .position(|candidate| *candidate == key)
                .and_then(|index| i32::try_from(index).ok())
                .unwrap_or(-1)
        }
    }

    impl QAbstractItemModel for RowModel {
        fn index(&self, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex {
            if parent.is_valid() || column != 0 || row < 0 || row as usize >= self.rows.len() {
                return QModelIndex::default();
            }
            self.create_index(row, column, 0)
        }

        fn parent(&self, _child: &QModelIndex) -> QModelIndex {
            QModelIndex::default()
        }

        fn row_count(&self, parent: &QModelIndex) -> i32 {
            if parent.is_valid() { 0 } else { self.count() }
        }

        fn column_count(&self, parent: &QModelIndex) -> i32 {
            i32::from(!parent.is_valid())
        }

        fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
            let Some(row) = usize::try_from(index.row()).ok().and_then(|row| self.rows.get(row)) else {
                return QVariant::default();
            };
            let Some(name) = usize::try_from(role - FIRST_ROLE).ok().and_then(|role| self.roles.get(role))
            else {
                return QVariant::default();
            };
            row.get(name).map(to_qvariant).unwrap_or_default()
        }

        fn role_names(&self) -> QHash<i32, QByteArray> {
            let mut names = QHash::<i32, QByteArray>::default();
            for (offset, name) in self.roles.iter().enumerate() {
                names.insert(&(FIRST_ROLE + offset as i32), &QByteArray::from(name.as_str()));
            }
            names
        }
    }

    impl RowModel {
        /// A model with `roles`, keyed by the row field `key`.
        pub fn with_roles(key: &str, roles: &[&str]) -> Self {
            let mut model = Self::default();
            model.roles = roles.iter().map(|role| (*role).to_owned()).collect();
            model.key = key.to_owned();
            model
        }

        /// Publishes `rows` (JSON objects carrying the key field).
        pub fn publish(&mut self, rows: Vec<Value>) {
            let rows: Vec<Map<String, Value>> = rows
                .into_iter()
                .filter_map(|row| match row {
                    Value::Object(fields) => Some(fields),
                    _ => None,
                })
                .collect();
            let keys: Vec<String> = rows
                .iter()
                .map(|row| match row.get(&self.key) {
                    Some(Value::String(key)) => key.clone(),
                    Some(other) => other.to_string(),
                    None => String::new(),
                })
                .collect();
            let old_count = self.rows.len();
            let steps = plan(&self.keys, &keys, |old, new| self.rows[old] != rows[new]);
            if steps.is_empty() {
                return;
            }
            if steps.contains(&Step::Reset) {
                self.begin_reset_model();
                self.rows = rows;
                self.keys = keys;
                self.end_reset_model();
            } else {
                let mut changes = Vec::new();
                for step in steps {
                    match step {
                        Step::Remove { first, count } => {
                            self.begin_remove_rows(
                                &QModelIndex::default(),
                                first as i32,
                                (first + count - 1) as i32,
                            );
                            self.rows.drain(first..first + count);
                            self.keys.drain(first..first + count);
                            self.end_remove_rows();
                        }
                        Step::Insert { first, count } => {
                            self.begin_insert_rows(
                                &QModelIndex::default(),
                                first as i32,
                                (first + count - 1) as i32,
                            );
                            for offset in 0..count {
                                self.rows.insert(first + offset, rows[first + offset].clone());
                                self.keys.insert(first + offset, keys[first + offset].clone());
                            }
                            self.end_insert_rows();
                        }
                        Step::Change { first, last } => changes.push((first, last)),
                        Step::Reset => {}
                    }
                }
                for (first, last) in changes {
                    let roles: Vec<i32> = self
                        .roles
                        .iter()
                        .enumerate()
                        .filter(|(_, name)| {
                            (first..=last).any(|row| self.rows[row].get(*name) != rows[row].get(*name))
                        })
                        .map(|(offset, _)| FIRST_ROLE + offset as i32)
                        .collect();
                    for row in first..=last {
                        self.rows[row] = rows[row].clone();
                    }
                    let top = self.create_index(first as i32, 0, 0);
                    let bottom = self.create_index(last as i32, 0, 0);
                    self.data_changed_roles(&top, &bottom, &roles);
                }
            }
            if self.rows.len() != old_count {
                self.count_changed();
            }
        }
    }
}

pub use row_model::RowModel;

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).to_owned()).collect()
    }

    #[test]
    fn plans_removals_insertions_and_changes() {
        let old = keys(&["a", "b", "c", "d"]);
        let new = keys(&["a", "x", "y", "c", "d", "z"]);
        let steps = plan(&old, &new, |old, _| old == 3);
        assert_eq!(
            steps,
            vec![
                Step::Remove { first: 1, count: 1 },
                Step::Insert { first: 1, count: 2 },
                Step::Insert { first: 5, count: 1 },
                Step::Change { first: 4, last: 4 },
            ]
        );
    }

    #[test]
    fn reorders_reset() {
        assert_eq!(plan(&keys(&["a", "b"]), &keys(&["b", "a"]), |_, _| false), vec![Step::Reset]);
        assert_eq!(plan(&keys(&["a"]), &keys(&["b", "b"]), |_, _| false), vec![Step::Reset]);
    }

    #[test]
    fn identical_lists_need_nothing() {
        assert!(plan(&keys(&["a", "b"]), &keys(&["a", "b"]), |_, _| false).is_empty());
    }
}
