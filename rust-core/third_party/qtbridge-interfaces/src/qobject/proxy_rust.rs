// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

use qtbridge_runtime::{DispatchMetaCall, QObjectHolder};
use crate::genericrustproxy::GenericRustProxy;
use super::proxy_cpp_bridge::QObjectProxyCpp;

/* QObject trait left out on purpose */

pub trait QObjectAdapter: DispatchMetaCall {}

impl<T> QObjectAdapter for T
where T: QObjectHolder<ProxyRust = QObjectProxyRust> {}

pub type QObjectProxyRust = GenericRustProxy<QObjectProxyCpp, dyn QObjectAdapter>;
