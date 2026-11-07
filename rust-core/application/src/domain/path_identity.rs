//! The identity of a path: lossless native units of this computer or a remote workspace's
//! path under its authority. Every adapter and use case names a repository location this way.
pub use gitlama_contract::domain::path_identity::*;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// Where a path identity points. The bridge types hold no behaviour, so this lives here.
pub trait PathIdentityLocation {
    /// Whether the units name a path on a remote host rather than this computer.
    fn is_remote(&self) -> bool;
}

impl PathIdentityLocation for NativePathIdentity {
    fn is_remote(&self) -> bool {
        self.remote.is_some()
    }
}

pub(crate) fn valid_remote_authority(authority: &NativeRemoteAuthority) -> bool {
    valid_profile_id(&authority.profile_id)
        && valid_store_id(&authority.store_id)
        && valid_account_uid(&authority.account_uid)
}

/// A canonical lowercase hyphenated UUID.
pub(crate) fn valid_profile_id(value: &str) -> bool {
    value.len() == 36
        && value.bytes().enumerate().all(|(index, byte)| {
            if matches!(index, 8 | 13 | 18 | 23) {
                byte == b'-'
            } else {
                byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)
            }
        })
}

pub(crate) fn valid_store_id(value: &str) -> bool {
    value.len() == 32
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// A decimal `u32` without sign, padding or leading zeros.
pub(crate) fn valid_account_uid(value: &str) -> bool {
    !value.is_empty()
        && value.bytes().all(|byte| byte.is_ascii_digit())
        && (value == "0" || !value.starts_with('0'))
        && value.parse::<u32>().is_ok()
}

#[cfg(unix)]
pub fn native_path_identity(path: &Path) -> NativePathIdentity {
    use std::os::unix::ffi::OsStrExt;
    NativePathIdentity {
        platform: NativePathPlatform::Unix,
        units: path
            .as_os_str()
            .as_bytes()
            .iter()
            .map(|byte| u16::from(*byte))
            .collect(),
        remote: None,
    }
}

/// The local path of [identity]; `None` for a remote identity or another
/// platform's path.
#[cfg(unix)]
pub fn native_path(identity: &NativePathIdentity) -> Option<PathBuf> {
    use std::os::unix::ffi::OsStringExt;
    if identity.is_remote() || identity.platform != NativePathPlatform::Unix {
        return None;
    }
    let bytes = identity
        .units
        .iter()
        .map(|unit| u8::try_from(*unit))
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    Some(PathBuf::from(OsString::from_vec(bytes)))
}

#[cfg(windows)]
pub fn native_path_identity(path: &Path) -> NativePathIdentity {
    use std::os::windows::ffi::OsStrExt;
    NativePathIdentity {
        platform: NativePathPlatform::Windows,
        units: path.as_os_str().encode_wide().collect(),
        remote: None,
    }
}

#[cfg(windows)]
pub fn native_path(identity: &NativePathIdentity) -> Option<PathBuf> {
    use std::os::windows::ffi::OsStringExt;
    (!identity.is_remote() && identity.platform == NativePathPlatform::Windows)
        .then(|| PathBuf::from(OsString::from_wide(&identity.units)))
}
