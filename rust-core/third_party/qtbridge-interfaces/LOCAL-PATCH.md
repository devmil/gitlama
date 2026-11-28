# qtbridge-interfaces 0.2.0, patched for the Devmil Qt applications (copied from ProcessLama)

Upstream: https://code.qt.io/cgit/qt/qtbridge-rust.git/ (LGPL-3.0-only or
Qt Commercial), version 0.2.0 from crates.io, unmodified except
`src/object_access/rust_object_access.rs` and the `dataChangedRoles` addition
in `src/qabstract_item_model/`.

Why: `try_store_handle_and_call_cpp(_mut)` stores the Rust object's handle in a
`Cell` reached through the caller's `&mut` proxy, then calls into C++. Qt
re-enters (for example `rowCount` from `rowsAboutToBeInserted` inside
`beginInsertRows`) through C++'s own pointer to the proxy. Under `noalias`,
release builds may sink the store past the opaque call, so the re-entrant read
finds no handle, tries the borrowed `RefCell` and panics
("Failed to borrow for row_count").

Patch: `std::hint::black_box(&self.borrow)` after storing the handle and after
the C++ call, so the cell's address escapes and the store stays before the
call. Remove this copy once upstream fixes the aliasing.

## dataChanged with roles

Upstream exposes `dataChanged(topLeft, bottomRight)` only. Without roles a view
re-reads every role of every delegate in the range. `data_changed_roles` (C++
`dataChangedRoles`) forwards a role list to `QAbstractItemModel::dataChanged`,
so a live table updates only the value roles that change each poll.
