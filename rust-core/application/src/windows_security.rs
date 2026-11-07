//! Windows filesystem security helpers for private product runtime material.

use std::ffi::c_void;
use std::path::Path;

use std::os::windows::ffi::OsStrExt as _;
use windows::core::{PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, LocalFree, HANDLE, HLOCAL};
use windows::Win32::Security::Authorization::{
    ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
};
use windows::Win32::Security::{
    GetLengthSid, GetTokenInformation, SetFileSecurityW, TokenUser, DACL_SECURITY_INFORMATION,
    PROTECTED_DACL_SECURITY_INFORMATION, PSECURITY_DESCRIPTOR, TOKEN_QUERY, TOKEN_USER,
};
use windows::Win32::System::SystemServices::SECURITY_DESCRIPTOR_REVISION;
use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

fn windows_error(context: &'static str) -> std::io::Error {
    std::io::Error::other(context)
}

/// Replace inherited permissions with a DACL granting full access only to the
/// current Windows user. Call this before writing private data into a file.
pub(crate) fn owner_only(path: &Path) -> std::io::Result<()> {
    let mut token = HANDLE::default();
    unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw mut token) }
        .map_err(|_| windows_error("could not query the current Windows user"))?;
    let sid_result = (|| {
        let mut required = 0;
        let _ = unsafe { GetTokenInformation(token, TokenUser, None, 0, &raw mut required) };
        if required == 0 {
            return Err(windows_error("could not size the current Windows user SID"));
        }
        let words = usize::try_from(required)
            .ok()
            .and_then(|bytes| bytes.checked_add(std::mem::size_of::<usize>() - 1))
            .map(|bytes| bytes / std::mem::size_of::<usize>())
            .ok_or_else(|| windows_error("the current Windows user SID is too large"))?;
        let mut storage = vec![0_usize; words];
        unsafe {
            GetTokenInformation(
                token,
                TokenUser,
                Some(storage.as_mut_ptr().cast::<c_void>()),
                required,
                &raw mut required,
            )
        }
        .map_err(|_| windows_error("could not read the current Windows user SID"))?;
        let token_user = unsafe { &*storage.as_ptr().cast::<TOKEN_USER>() };
        if unsafe { GetLengthSid(token_user.User.Sid) } == 0 {
            return Err(windows_error("the current Windows user SID is invalid"));
        }
        let mut sid_text = PWSTR::null();
        unsafe { ConvertSidToStringSidW(token_user.User.Sid, &raw mut sid_text) }
            .map_err(|_| windows_error("could not encode the current Windows user SID"))?;
        let result = unsafe { sid_text.to_string() }
            .map_err(|_| windows_error("the current Windows user SID is invalid"));
        let _ = unsafe { LocalFree(Some(HLOCAL(sid_text.0.cast::<c_void>()))) };
        result
    })();
    let _ = unsafe { CloseHandle(token) };
    let sid = sid_result?;

    let sddl = format!("D:P(A;;GA;;;{sid})")
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect::<Vec<_>>();
    let mut descriptor = PSECURITY_DESCRIPTOR::default();
    unsafe {
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            PCWSTR(sddl.as_ptr()),
            SECURITY_DESCRIPTOR_REVISION,
            &raw mut descriptor,
            None,
        )
    }
    .map_err(|_| windows_error("could not create an owner-only Windows ACL"))?;
    let wide_path = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect::<Vec<_>>();
    let applied = unsafe {
        SetFileSecurityW(
            PCWSTR(wide_path.as_ptr()),
            DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
            descriptor,
        )
    };
    let _ = unsafe { LocalFree(Some(HLOCAL(descriptor.0))) };
    applied
        .ok()
        .map_err(|_| windows_error("could not apply an owner-only Windows ACL"))
}
