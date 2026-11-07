//! The local record of remote writes that were sent, or are about to be sent, to a helper.
//!
//! A remote write is persisted here before its first Execute byte leaves the client, and its
//! terminal outcome is recorded before the pending indicator disappears. The record holds
//! identities and outcomes only: no credentials, no output and no replayable request. Its home is
//! `remote/pending/operations.json` beside the settings document.
pub use gitlama_contract::remote_pending::*;
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

const FILE: &str = "operations.json";
const MAX_BYTES: u64 = 1024 * 1024;
/// Operations kept, resolved or not. Unresolved operations are never evicted.
pub const MAX_OPERATIONS: usize = crate::domain::limits::PENDING_OPERATIONS;
const MAX_SUMMARY_CHARS: usize = crate::domain::limits::SUMMARY_CHARACTERS;

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Document {
    schema: u32,
    operations: Vec<NativeRemotePendingOperation>,
}

fn hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn uuid(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 36
        && bytes.iter().enumerate().all(|(index, byte)| match index {
            8 | 13 | 18 | 23 => *byte == b'-',
            _ => byte.is_ascii_digit() || (b'a'..=b'f').contains(byte),
        })
}

fn decimal(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 10
        && value.bytes().all(|b| b.is_ascii_digit())
        && (value == "0" || !value.starts_with('0'))
        && value.parse::<u32>().is_ok()
}

/// The family of the removed undo and redo writes, still found in older stores.
const LEGACY_UNDO_FAMILY: &str = "undo";

fn valid(operation: &NativeRemotePendingOperation) -> bool {
    use crate::wire::contract::{RemoteOutcome, RemoteWriteFamily};
    hex(&operation.operation_id, 32)
        && hex(&operation.epoch, 32)
        && hex(&operation.digest, 64)
        && hex(&operation.store_id, 32)
        && hex(&operation.binding, 64)
        && uuid(&operation.profile_id)
        && decimal(&operation.account_uid)
        && RemoteWriteFamily::parse(&operation.family).is_some()
        && matches!(operation.state.as_str(), "pending" | "terminal")
        && operation
            .outcome
            .as_deref()
            .is_none_or(|outcome| RemoteOutcome::parse(outcome).is_some())
        && (operation.state == "pending" || operation.outcome.is_some())
        && operation
            .result_object_id
            .as_deref()
            .is_none_or(|id| hex(id, 40) || hex(id, 64))
        && operation.summary.chars().count() <= MAX_SUMMARY_CHARS
        && !operation.summary.chars().any(char::is_control)
}

fn validate(operations: &[NativeRemotePendingOperation]) -> bool {
    operations.len() <= MAX_OPERATIONS
        && operations.iter().all(valid)
        && operations.iter().enumerate().all(|(index, operation)| {
            operations[..index]
                .iter()
                .all(|other| other.operation_id != operation.operation_id)
        })
}

/// `remote/pending` beside the default settings document.
#[must_use]
pub fn default_directory() -> Option<String> {
    let settings = crate::storage::settings_default_path().path?;
    let root = Path::new(&settings).parent()?;
    Some(
        root.join("remote")
            .join("pending")
            .to_string_lossy()
            .into_owned(),
    )
}

#[must_use]
pub fn load(directory: &str) -> NativeRemotePendingLoadResult {
    let failure = |state| NativeRemotePendingLoadResult {
        state,
        operations: Vec::new(),
    };
    let path = PathBuf::from(directory).join(FILE);
    let mut file = match File::open(&path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return failure(NativeRemotePendingLoadState::Absent)
        }
        Err(_) => return failure(NativeRemotePendingLoadState::Unreadable),
    };
    let mut bytes = Vec::new();
    if (&mut file)
        .take(MAX_BYTES + 1)
        .read_to_end(&mut bytes)
        .is_err()
    {
        return failure(NativeRemotePendingLoadState::Unreadable);
    }
    if bytes.len() as u64 > MAX_BYTES {
        return failure(NativeRemotePendingLoadState::Corrupt);
    }
    let document = serde_json::from_slice::<Document>(&bytes).map(|mut document| {
        // Undo and redo were removed; no helper can reconcile their writes any more.
        document
            .operations
            .retain(|operation| operation.family != LEGACY_UNDO_FAMILY);
        document
    });
    match document {
        Ok(document) if document.schema == 1 && validate(&document.operations) => {
            NativeRemotePendingLoadResult {
                state: NativeRemotePendingLoadState::Loaded,
                operations: document.operations,
            }
        }
        _ => failure(NativeRemotePendingLoadState::Corrupt),
    }
}

#[must_use]
pub fn save(
    directory: &str,
    operations: Vec<NativeRemotePendingOperation>,
) -> NativeRemotePendingSaveResult {
    NativeRemotePendingSaveResult {
        saved: save_to(Path::new(directory), operations).is_ok(),
    }
}

fn save_to(directory: &Path, operations: Vec<NativeRemotePendingOperation>) -> Result<(), ()> {
    if !directory.is_absolute() || !validate(&operations) {
        return Err(());
    }
    let mut bytes = serde_json::to_vec_pretty(&Document {
        schema: 1,
        operations,
    })
    .map_err(|_| ())?;
    bytes.push(b'\n');
    if bytes.len() as u64 > MAX_BYTES {
        return Err(());
    }
    // The operations name repositories and refs: owner-only, replaced atomically.
    crate::private_store::PrivateDir::application(directory)
        .and_then(|store| store.replace(FILE, &bytes))
        .map_err(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    #[cfg(unix)]
    #[test]
    fn the_record_is_owner_only() {
        // Regression: the record was created with the default permissions.
        use std::os::unix::fs::PermissionsExt as _;
        let root = directory("private");
        assert!(save(&root.to_string_lossy(), vec![operation(1, "pending", None)]).saved);
        let mode = |path: &Path| fs::metadata(path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&root), 0o700);
        assert_eq!(mode(&root.join(FILE)), 0o600);
        fs::remove_dir_all(root).unwrap();
    }

    fn operation(id: u8, state: &str, outcome: Option<&str>) -> NativeRemotePendingOperation {
        NativeRemotePendingOperation {
            operation_id: format!("{id:02x}").repeat(16),
            epoch: "e".repeat(32),
            digest: "d".repeat(64),
            family: "commit".into(),
            profile_id: "123e4567-e89b-12d3-a456-426614174000".into(),
            store_id: "a".repeat(32),
            account_uid: "1000".into(),
            binding: "b".repeat(64),
            state: state.into(),
            outcome: outcome.map(str::to_owned),
            result_object_id: None,
            summary: "Remote commit".into(),
            created_at_ms: 1,
            updated_at_ms: 2,
        }
    }

    fn directory(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "gitlama-pending-{name}-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&path);
        path
    }

    #[test]
    fn writes_of_the_removed_undo_family_are_dropped_on_load() {
        let root = directory("legacy-undo");
        let text = root.to_string_lossy().into_owned();
        assert!(save(&text, vec![operation(1, "pending", None)]).saved);
        let mut undo = operation(2, "pending", None);
        undo.family = LEGACY_UNDO_FAMILY.into();
        let bytes = serde_json::to_vec(&Document {
            schema: 1,
            operations: vec![operation(1, "pending", None), undo],
        })
        .unwrap();
        fs::write(root.join(FILE), bytes).unwrap();
        let loaded = load(&text);
        assert_eq!(loaded.state, NativeRemotePendingLoadState::Loaded);
        assert_eq!(loaded.operations, vec![operation(1, "pending", None)]);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn operations_round_trip_and_absent_is_not_corrupt() {
        let root = directory("round-trip");
        let text = root.to_string_lossy().into_owned();
        assert_eq!(load(&text).state, NativeRemotePendingLoadState::Absent);
        let mut operations = vec![
            operation(1, "pending", None),
            operation(2, "terminal", Some("unknown")),
        ];
        for (index, family) in [
            "refs",
            "stash",
            "transfer",
            "discard",
            "history",
            "rebase",
            "restack",
            "bisect",
            "conflict",
            "sequencer",
            "snapshot",
            "snapshotRestore",
            "restore",
            "indexLock",
            "patch",
            "extension",
        ]
        .into_iter()
        .enumerate()
        {
            let mut entry = operation(
                5 + u8::try_from(index).unwrap(),
                "terminal",
                Some("partial"),
            );
            entry.family = family.into();
            operations.push(entry);
        }
        assert!(save(&text, operations.clone()).saved);
        let loaded = load(&text);
        assert_eq!(loaded.state, NativeRemotePendingLoadState::Loaded);
        assert_eq!(loaded.operations, operations);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn invalid_records_are_never_saved_and_corruption_is_kept() {
        let root = directory("invalid");
        let text = root.to_string_lossy().into_owned();
        assert!(!save(&text, vec![operation(1, "terminal", None)]).saved);
        assert!(
            !save(
                &text,
                vec![operation(1, "pending", None), operation(1, "pending", None)]
            )
            .saved
        );
        let mut bad = operation(3, "pending", None);
        bad.summary = "line\nbreak".into();
        assert!(!save(&text, vec![bad]).saved);
        let mut unknown_family = operation(4, "pending", None);
        unknown_family.family = "reset".into();
        assert!(!save(&text, vec![unknown_family]).saved);
        let too_many: Vec<_> = (0..=MAX_OPERATIONS)
            .map(|index| {
                let mut entry = operation(0, "pending", None);
                entry.operation_id = format!("{index:032x}");
                entry
            })
            .collect();
        assert!(!save(&text, too_many).saved);
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join(FILE), b"{not json").unwrap();
        assert_eq!(load(&text).state, NativeRemotePendingLoadState::Corrupt);
        assert_eq!(fs::read(root.join(FILE)).unwrap(), b"{not json");
        assert!(!save("relative/path", vec![]).saved);
        fs::remove_dir_all(root).unwrap();
    }
}
