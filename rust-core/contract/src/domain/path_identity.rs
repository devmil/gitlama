//! The bridge types of `domain::path_identity`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum NativePathPlatform {
    Unix,
    Windows,
}

/// Lossless native path units: Unix bytes or Windows UTF-16 code units.
#[derive(Clone, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativePathIdentity {
    pub platform: NativePathPlatform,
    pub units: Vec<u16>,
    /// The remote workspace authority; absent for a path on this computer.
    /// A remote identity is never a local path: every local file, process and
    /// cache boundary rejects it. Local identities omit the field, so they
    /// serialize exactly as before schema 13.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub remote: Option<NativeRemoteAuthority>,
}

/// The verified remote account and private helper store a remote workspace
/// belongs to, under the local host profile that reached it. Two remote paths
/// are the same workspace only when their authorities are equal.
#[derive(Clone, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeRemoteAuthority {
    /// The local profile's canonical lowercase UUID.
    pub profile_id: String,
    /// The helper store's 32 lowercase hexadecimal digits.
    pub store_id: String,
    /// The remote effective user ID as a canonical decimal string.
    pub account_uid: String,
}
