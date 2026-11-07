//! The commit-message rule the core and the remote helper share, so a message is accepted on a
//! host exactly when it is accepted on this computer.
use crate::domain::limits::{COMMIT_DESCRIPTION_BYTES, COMMIT_SUBJECT_BYTES};

/// The one commit-message rule: a one-line subject, a bounded description, and well-formed
/// author and co-author identities.
#[must_use]
pub fn valid_commit_message(
    subject_text: &str,
    description: &str,
    coauthors: &[String],
    author: Option<&str>,
) -> bool {
    let subject = subject_text.as_bytes();
    if subject.is_empty()
        || subject_text.trim().is_empty()
        || subject.len() > COMMIT_SUBJECT_BYTES
        || subject.contains(&0)
        || subject.contains(&b'\n')
        || subject.contains(&b'\r')
        || description.len() > COMMIT_DESCRIPTION_BYTES
        || description.contains('\0')
        || coauthors.len() > 32
    {
        return false;
    }
    coauthors.iter().all(|value| valid_identity(value)) && author.is_none_or(valid_identity)
}

fn valid_identity(value: &str) -> bool {
    let value = value.trim();
    !value.is_empty()
        && value.len() <= 512
        && !value.contains(['\0', '\n', '\r'])
        && value.contains('<')
        && value.ends_with('>')
        && value.contains('@')
}
