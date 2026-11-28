// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

use std::mem;
use std::rc::{Rc, Weak};
use std::cell::{Cell, RefCell};

#[macro_export]
macro_rules! call_rust_trait_impl {
    (mut $self:expr, $method:ident ( $($arg:expr),* )) => {
        $self.rust_obj
            .try_call_rust_with_handle_mut(|vtable| {
                vtable.$method($($arg),*)
            })
            .expect(concat!(
                "Failed to borrow mutably for ",
                stringify!($method)
            ))
    };

    ($self:expr, $method:ident ( $($arg:expr),* )) => {
        $self.rust_obj
            .try_call_rust_with_handle(|vtable| {
                vtable.$method($($arg),*)
            })
            .expect(concat!(
                "Failed to borrow for ",
                stringify!($method)
            ))
    };
}

#[macro_export]
macro_rules! call_cpp_impl {
    (mut $self:expr, $mut_reference:expr, $method:ident ( $($arg:expr),* )) => {{
        let proxy = unsafe {
            $self.cpp_proxy
                .as_mut()
                .expect("cpp_proxy was null")
        };
        let proxy_pinned = unsafe { std::pin::Pin::new_unchecked(proxy) };
        $self.rust_obj
            .try_store_handle_and_call_cpp_mut($mut_reference, || proxy_pinned.$method($($arg),*))
            .expect(concat!(
                "Failed to borrow mutably for ",
                stringify!($method)
            ))
    }};

    ($self:expr, $reference:expr, $method:ident ( $($arg:expr),* )) => {{
        let proxy = unsafe {
            $self.cpp_proxy
                .as_ref()
                .expect("cpp_proxy was null")
        };
         $self.rust_obj
            .try_store_handle_and_call_cpp($reference, || proxy.$method($($arg),*))
            .expect(concat!(
                "Failed to borrow for ",
                stringify!($method)
            ))
    }};
}

/// Manages shared access to a Rust object across the Rust/C++ boundary.
///
/// When Rust calls into C++ and C++ calls back into Rust, the inner callback
/// cannot re-borrow the `RefCell` without panicking. This struct solves
/// this by caching a raw pointer before crossing into C++ and restoring it as
/// a reference on the way back, avoiding a second borrow while preserving a
/// valid borrow stack per the "Stacked Borrows" aliasing model.
pub struct RustObjAccess<T: ?Sized> {
    shared_reference: SharedReferenceWithQml<T>,
    borrow: Cell<BorrowState<T>>,
}

impl<T: ?Sized> RustObjAccess<T> {
    /// Create an instance that hold a strong reference to the Rust object.
    /// This is the case for objects created on the QML Side (QML Element).
    pub fn new_strong(ptr: Rc<RefCell<T>>) -> Self {
        Self {
            shared_reference: SharedReferenceWithQml::OwnedByQml(ptr),
            borrow: Cell::new(BorrowState::None),
        }
    }

    /// Create an instance that holds a weak (`Weak<RefCell<T>>`) reference to the Rust object.
    /// This is the case for objects created on the Rust Side.
    pub fn new_weak(ptr: Weak<RefCell<T>>) -> Self {
        Self {
            shared_reference: SharedReferenceWithQml::OwnedByRust(ptr),
            borrow: Cell::new(BorrowState::None),
        }
    }

    pub fn try_call_rust_with_handle<F, R>(&self, f: F) -> Result<R, RustObjAccessError>
    where
        F: FnOnce(&T) -> R,
    {
        let guard = BorrowState::consume(&self.borrow);

        match guard.content() {
            BorrowState::Immutable(ptr) => Ok(f(unsafe { &**ptr })),
            BorrowState::Mutable(ptr) => Ok(f(unsafe { &**ptr })),
            BorrowState::None => {
                let rc = self.shared_reference.get_rc()
                    .ok_or(RustObjAccessError::ExpiredWeakPtr)?;
                let ref_guarded = rc.try_borrow()
                    .map_err(|err| RustObjAccessError::BorrowError(err))?;
                Ok(f(&*ref_guarded))
            }
        }
    }

    pub fn try_call_rust_with_handle_mut<F, R>(&self, f: F) -> Result<R, RustObjAccessError>
    where
        F: FnOnce(&mut T) -> R,
    {
        let guard = BorrowState::consume(&self.borrow);

        match guard.content() {
            BorrowState::Mutable(ptr) => Ok(f(unsafe { &mut **ptr })),
            BorrowState::Immutable(_) => Err(RustObjAccessError::BorrowConflict),
            BorrowState::None => {
                let rc = self.shared_reference.get_rc()
                    .ok_or(RustObjAccessError::ExpiredWeakPtr)?;
                let mut ref_guarded = rc.try_borrow_mut()
                    .map_err(|err| RustObjAccessError::BorrowMutError(err))?;
                Ok(f(&mut *ref_guarded))
            }
        }
    }

    pub fn try_store_handle_and_call_cpp<F, R>(&self, rust_obj: &T, f: F) -> Result<R, RustObjAccessError>
    where
        F: FnOnce() -> R,
    {
        assert!(
            self.shared_reference.contains(rust_obj),
            "The rust_obj you want to call a function on does not match the shared reference."
        );
        let guard = BorrowState::store(&self.borrow, rust_obj);
        // ProcessLama patch: C++ re-enters through its own pointer to this
        // proxy, which the caller's `&mut` (noalias) does not cover. Escape
        // the cell so the optimizer cannot sink the store past the call.
        std::hint::black_box(&self.borrow);
        // It is possible that multiple immutable references are alive, but no mutable
        if matches!(guard.content(), BorrowState::Mutable(_)) {
            return Err(RustObjAccessError::BorrowConflict);
        }
        let result = f();
        std::hint::black_box(&self.borrow);
        Ok(result)
    }

    pub fn try_store_handle_and_call_cpp_mut<F, R>(&self, rust_obj: &mut T, f: F) -> Result<R, RustObjAccessError>
    where
        F: FnOnce() -> R,
    {
        assert!(
            self.shared_reference.contains(rust_obj),
            "The rust_obj you want to call a function on does not match the shared reference."
        );
        let guard = BorrowState::store_mut(&self.borrow, rust_obj);
        // ProcessLama patch: see `try_store_handle_and_call_cpp`.
        std::hint::black_box(&self.borrow);
        // If we get a mutable reference, there should be no other reference alive
        if  matches!(guard.content(), BorrowState::Mutable(_)) || matches!(guard.content(), BorrowState::Immutable(_)) {
            return Err(RustObjAccessError::BorrowConflict);
        }
        let result = f();
        std::hint::black_box(&self.borrow);
        Ok(result)
    }

    pub fn get_rc(&self) -> Option<Rc<RefCell<T>>> {
        self.shared_reference.get_rc()
    }
}


enum BorrowState<T: ?Sized> {
    None,
    Immutable(*const T),
    Mutable(*mut T),
}

impl<T: ?Sized> BorrowState<T> {
    fn consume(cell: &Cell<Self>) -> BorrowGuard<'_, T> {
        let consumed = cell.replace(BorrowState::None);
        BorrowGuard { cell, consumed }
    }

    fn store<'a>(cell: &'a Cell<Self>, rust_obj: &T) -> BorrowGuard<'a, T> {
        let old = cell.replace(BorrowState::Immutable(rust_obj as *const T));
        BorrowGuard { cell, consumed: old }
    }

    fn store_mut<'a>(cell: &'a Cell<Self>, rust_obj: &mut T) -> BorrowGuard<'a, T> {
        let old = cell.replace(BorrowState::Mutable(rust_obj as *mut T));
        BorrowGuard { cell, consumed: old }
    }
}

struct BorrowGuard<'a, T: ?Sized> {
    cell: &'a Cell<BorrowState<T>>,
    consumed: BorrowState<T>,
}

impl<T: ?Sized> BorrowGuard<'_, T> {
    fn content(&self) -> &BorrowState<T> {
        &self.consumed
    }
}

impl<T: ?Sized> Drop for BorrowGuard<'_, T> {
    fn drop(&mut self) {
        self.cell.set(mem::replace(&mut self.consumed, BorrowState::None));
    }
}

#[derive(Debug)]
pub enum RustObjAccessError {
    BorrowError(std::cell::BorrowError),
    BorrowMutError(std::cell::BorrowMutError),
    BorrowConflict,
    ExpiredWeakPtr,
}

/// Represents how a Rust object is shared between Rust and QML.
enum SharedReferenceWithQml<T: ?Sized> {
    /// Holds a weak reference to the Rust object.
    /// The object is dropped once there are no remaining strong references
    /// on the Rust side.
    OwnedByRust(Weak<RefCell<T>>),

    /// Holds a strong reference to the Rust object.
    /// Even if Rust no longer keeps any references, the object will remain
    /// alive as long as it is still referenced from QML
    /// (until the corresponding QObject is destroyed by the QML engine).
    OwnedByQml(Rc<RefCell<T>>),
}

impl<T: ?Sized> SharedReferenceWithQml<T> {
    fn get_rc(&self) -> Option<Rc<RefCell<T>>> {
        match self {
            SharedReferenceWithQml::OwnedByRust(weak) => weak.upgrade(),
            SharedReferenceWithQml::OwnedByQml(rc) => Some(rc.clone()),
        }
    }

    fn contains(&self, obj: &T) -> bool {
        let Some(rc) = self.get_rc() else { return false };
        let expected = rc.as_ptr() as *const ();
        let actual = obj as *const T as *const ();
        expected == actual
    }
}
