//! Native path conversions shared by the use cases.
#![allow(clippy::wildcard_imports)]
use crate::domain::path_identity::{NativePathIdentity, NativePathPlatform, PathIdentityLocation};
use crate::dto::*;
use std::fs;
use std::path::Path;

/// Git path bytes as a native argument (devmil-git's one lossless conversion).
pub(crate) fn native_path_argument(bytes: Vec<u8>) -> Option<std::ffi::OsString> {
    devmil_git::native_bytes::bytes_to_os_string(&bytes).ok()
}

#[cfg(unix)]
pub(crate) fn native_identity_bytes(identity: &NativePathIdentity) -> Option<Vec<u8>> {
    (!identity.is_remote() && identity.platform == NativePathPlatform::Unix)
        .then(|| {
            identity
                .units
                .iter()
                .map(|unit| u8::try_from(*unit))
                .collect::<Result<Vec<_>, _>>()
                .ok()
        })
        .flatten()
}

#[cfg(windows)]
pub(crate) fn native_identity_bytes(identity: &NativePathIdentity) -> Option<Vec<u8>> {
    (!identity.is_remote() && identity.platform == NativePathPlatform::Windows)
        .then(|| devmil_git::native_bytes::encode_wtf8(&identity.units))
}

#[cfg(not(any(unix, windows)))]
pub(crate) fn native_identity_bytes(_identity: &NativePathIdentity) -> Option<Vec<u8>> {
    None
}

pub(crate) fn read_optional_bounded(
    path: &Path,
    maximum_bytes: usize,
) -> Result<Option<Vec<u8>>, NativeRepositoryFailureKind> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(NativeRepositoryFailureKind::InvalidOutput)
        }
        Ok(metadata) if metadata.len() > maximum_bytes as u64 => {
            Err(NativeRepositoryFailureKind::TooLarge)
        }
        Ok(_) => fs::read(path)
            .map(Some)
            .map_err(|_| NativeRepositoryFailureKind::Read),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(NativeRepositoryFailureKind::Read),
    }
}
