//! Credentials a Git transfer asks for: a private askpass helper that answers from
//! owner-only files and erases them when the lease ends.
//! Application-owned clone attempts around the shared process and validation contracts.

use devmil_git::auth::Credentials;
use std::path::{Path, PathBuf};

#[cfg(unix)]
pub(crate) struct AskpassLease {
    directory: PathBuf,
    executable: PathBuf,
    secret_files: Vec<PathBuf>,
}

#[cfg(unix)]
impl AskpassLease {
    pub(crate) fn new(attempt_id: u64, credentials: &Credentials) -> std::io::Result<Self> {
        let store =
            crate::private_store::PrivateDir::temporary(&format!("gitlama-askpass-{attempt_id}"))?;
        let mut lease = Self {
            executable: store.entry_path("askpass"),
            directory: store.path().to_path_buf(),
            secret_files: Vec::new(),
        };
        for (name, value) in [
            ("username", credentials.username_for_askpass()),
            ("password", credentials.password_for_askpass()),
            ("token", credentials.token_for_askpass()),
        ] {
            if let Some(value) = value {
                store.write_new(name, value.as_bytes())?;
                lease.secret_files.push(store.entry_path(name));
            }
        }
        store.write_new_executable(
            "askpass",
            b"#!/bin/sh\ncase \"$1\" in\n  *sername*|*SERNAME*) file=username ;;\n  *assword*|*ASSWORD*) if [ -f \"${0%/*}/password\" ]; then file=password; else file=token; fi ;;\n  *) exit 1 ;;\nesac\nexec /bin/cat -- \"${0%/*}/$file\"\n",
        )?;
        Ok(lease)
    }

    pub(crate) fn executable(&self) -> &Path {
        &self.executable
    }
}

#[cfg(unix)]
impl Drop for AskpassLease {
    fn drop(&mut self) {
        use std::io::{Seek, SeekFrom, Write};

        for path in &self.secret_files {
            if let Ok(metadata) = std::fs::metadata(path) {
                if let Ok(mut file) = std::fs::OpenOptions::new().write(true).open(path) {
                    let _ = file.seek(SeekFrom::Start(0));
                    let length = usize::try_from(metadata.len()).unwrap_or(0);
                    let _ = file.write_all(&vec![0; length]);
                    let _ = file.sync_all();
                }
            }
            let _ = std::fs::remove_file(path);
        }
        let _ = std::fs::remove_file(&self.executable);
        let _ = std::fs::remove_dir(&self.directory);
    }
}

#[cfg(windows)]
pub(crate) struct AskpassLease {
    directory: PathBuf,
    executable: PathBuf,
    secret_files: Vec<PathBuf>,
}

#[cfg(windows)]
impl AskpassLease {
    pub(crate) fn new(attempt_id: u64, credentials: &Credentials) -> std::io::Result<Self> {
        use std::io::Write as _;

        let mut entropy = [0_u8; 8];
        getrandom::fill(&mut entropy)
            .map_err(|_| std::io::Error::other("secure temporary-name generation failed"))?;
        let suffix = entropy
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let directory = std::env::temp_dir().join(format!(
            "gitlama-askpass-{}-{attempt_id}-{suffix}",
            std::process::id()
        ));
        std::fs::create_dir(&directory)?;
        let mut lease = Self {
            executable: directory.join("askpass"),
            directory,
            secret_files: Vec::new(),
        };
        crate::windows_security::owner_only(&lease.directory)?;
        for (name, value) in [
            ("username", credentials.username_for_askpass()),
            ("password", credentials.password_for_askpass()),
            ("token", credentials.token_for_askpass()),
        ] {
            if let Some(value) = value {
                let path = lease.directory.join(name);
                let mut file = std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&path)?;
                crate::windows_security::owner_only(&path)?;
                file.write_all(value.as_bytes())?;
                file.sync_all()?;
                lease.secret_files.push(path);
            }
        }
        let mut helper = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&lease.executable)?;
        crate::windows_security::owner_only(&lease.executable)?;
        helper.write_all(
            b"#!/bin/sh\ncase \"$1\" in\n  *sername*|*SERNAME*) file=username ;;\n  *assword*|*ASSWORD*) if [ -f \"${0%/*}/password\" ]; then file=password; else file=token; fi ;;\n  *) exit 1 ;;\nesac\nexec /bin/cat -- \"${0%/*}/$file\"\n",
        )?;
        helper.sync_all()?;
        Ok(lease)
    }

    pub(crate) fn executable(&self) -> &Path {
        &self.executable
    }
}

#[cfg(windows)]
impl Drop for AskpassLease {
    fn drop(&mut self) {
        use std::io::{Seek as _, SeekFrom, Write as _};

        for path in &self.secret_files {
            if let Ok(metadata) = std::fs::metadata(path) {
                if let Ok(mut file) = std::fs::OpenOptions::new().write(true).open(path) {
                    let _ = file.seek(SeekFrom::Start(0));
                    let length = usize::try_from(metadata.len()).unwrap_or(0);
                    let _ = file.write_all(&vec![0; length]);
                    let _ = file.sync_all();
                }
            }
            let _ = std::fs::remove_file(path);
        }
        let _ = std::fs::remove_file(&self.executable);
        let _ = std::fs::remove_dir(&self.directory);
    }
}

#[cfg(not(any(unix, windows)))]
pub(crate) struct AskpassLease;

#[cfg(not(any(unix, windows)))]
impl AskpassLease {
    pub(crate) fn new(_attempt_id: u64, _credentials: &Credentials) -> std::io::Result<Self> {
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "credential broker is unavailable on this platform",
        ))
    }

    pub(crate) fn executable(&self) -> &Path {
        Path::new("")
    }
}

#[cfg(test)]
mod tests {
    #[allow(unused_imports)] // The only test is Unix-only.
    use super::*;
    #[cfg(unix)]
    use std::process::Command;
    #[cfg(unix)]
    #[test]
    fn askpass_lease_answers_by_prompt_with_owner_only_files_and_cleans_up() {
        use std::os::unix::fs::PermissionsExt;

        let credentials = Credentials::new(
            Some("private-user".into()),
            Some("private-password".into()),
            Some("private-token".into()),
        )
        .unwrap();
        let lease = AskpassLease::new(9_001, &credentials).unwrap();
        let directory = lease.directory.clone();
        assert_eq!(
            std::fs::metadata(&directory).unwrap().permissions().mode() & 0o777,
            0o700
        );
        for file in &lease.secret_files {
            assert_eq!(
                std::fs::metadata(file).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        let username = Command::new(lease.executable())
            .arg("Username for repository")
            .output()
            .unwrap();
        let password = Command::new(lease.executable())
            .arg("Password for repository")
            .output()
            .unwrap();
        assert_eq!(username.stdout, b"private-user");
        assert_eq!(password.stdout, b"private-password");
        drop(lease);
        assert!(!directory.exists());
    }
}
