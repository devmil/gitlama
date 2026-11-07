//! Zip snapshots of a commit, built in the background and read in pages.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeArchiveFailureKind {
    /// The session is gone or was reopened.
    Stale,
    InvalidRequest,
    /// The commit is not in the repository.
    MissingCommit,
    /// The commit's tree is too large to archive.
    TooLarge,
    /// The session already builds as many archives as it may.
    Busy,
    Git,
    /// The archive could not be written.
    Write,
    Canceled,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeArchiveFailure {
    pub kind: NativeArchiveFailureKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeArchiveState {
    Running,
    Completed,
    Failed,
    Canceled,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeArchiveStartResult {
    pub token: Option<u64>,
    pub failure: Option<NativeArchiveFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeArchiveStatus {
    pub state: NativeArchiveState,
    /// Files written, submodule files included.
    pub files: u64,
    /// Files known so far; grows as submodules are entered.
    pub total_files: u64,
    /// Uncompressed content bytes written.
    pub content_bytes: u64,
    /// The size of the finished zip, once completed.
    pub archive_bytes: u64,
    /// Submodules kept as empty folders; at most a few are named, the count is exact.
    pub missing_submodules: Vec<Vec<u8>>,
    pub missing_submodule_count: u64,
    /// LFS files kept as pointers.
    pub unresolved_lfs: Vec<Vec<u8>>,
    pub unresolved_lfs_count: u64,
    pub failure: Option<NativeArchiveFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeArchivePage {
    pub bytes: Vec<u8>,
    pub failure: Option<NativeArchiveFailure>,
}
