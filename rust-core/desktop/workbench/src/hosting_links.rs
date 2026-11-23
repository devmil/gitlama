//! Pull requests a repository's branches were last found to have, kept so a branch shows its
//! link at once while the lookup runs again. Entries are disposable and may be outdated; each
//! names the hosting binding it was learned under and stands in only for that binding. The
//! stored format is the one earlier releases wrote, so their entries keep working.

use crate::entry_store::EntryStore;
use crate::rt::{self, TimerHandle};
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::hosting::{
    NativeHostingChangeRequest, NativeHostingChangeRequestState, NativeHostingCheckState,
    NativeHostingCheckSummary, NativeHostingMergeability, NativeHostingReviewSummary,
};
use serde_json::{Map, Value, json};
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::time::Duration;

const SCHEMA: u64 = 1;
/// Entries kept in memory.
const CAPACITY: usize = 32;
/// Branches an entry keeps; the least recently learned go first.
const BRANCH_LIMIT: usize = 300;
const PERSIST_DELAY: Duration = Duration::from_secs(2);

#[derive(Clone, Debug, PartialEq)]
pub struct LinkEntry {
    pub connection_id: String,
    pub provider_repository: String,
    /// Pull requests by provider branch, least recently learned first.
    pub branches: Vec<(String, Vec<NativeHostingChangeRequest>)>,
    /// The open pull requests the account authored, when known.
    pub authored: Option<Vec<NativeHostingChangeRequest>>,
}

impl LinkEntry {
    fn matches(&self, connection_id: &str, provider_repository: &str) -> bool {
        self.connection_id == connection_id && self.provider_repository == provider_repository
    }
}

fn state_name(state: NativeHostingChangeRequestState) -> &'static str {
    match state {
        NativeHostingChangeRequestState::Open => "open",
        NativeHostingChangeRequestState::Closed => "closed",
        NativeHostingChangeRequestState::Merged => "merged",
    }
}

fn state_of(name: &str) -> Option<NativeHostingChangeRequestState> {
    Some(match name {
        "open" => NativeHostingChangeRequestState::Open,
        "closed" => NativeHostingChangeRequestState::Closed,
        "merged" => NativeHostingChangeRequestState::Merged,
        _ => return None,
    })
}

fn checks_name(state: NativeHostingCheckState) -> &'static str {
    match state {
        NativeHostingCheckState::Pending => "pending",
        NativeHostingCheckState::Passing => "passing",
        NativeHostingCheckState::Failing => "failing",
        NativeHostingCheckState::Canceled => "canceled",
        NativeHostingCheckState::Skipped => "skipped",
        NativeHostingCheckState::Unknown => "unknown",
    }
}

fn checks_of(name: &str) -> Option<NativeHostingCheckState> {
    Some(match name {
        "pending" => NativeHostingCheckState::Pending,
        "passing" => NativeHostingCheckState::Passing,
        "failing" => NativeHostingCheckState::Failing,
        "canceled" => NativeHostingCheckState::Canceled,
        "skipped" => NativeHostingCheckState::Skipped,
        "unknown" => NativeHostingCheckState::Unknown,
        _ => return None,
    })
}

fn encode_pull(pull: &NativeHostingChangeRequest) -> Value {
    json!({
        "id": pull.stable_id,
        "number": pull.number,
        "title": pull.title,
        "author": pull.author,
        "state": state_name(pull.state),
        "draft": pull.draft,
        "sourceRepository": pull.source_repository,
        "sourceBranch": pull.source_branch,
        "targetRepository": pull.target_repository,
        "targetBranch": pull.target_branch,
        "head": pull.head_sha,
        "url": pull.web_url,
        "checks": checks_name(pull.checks.state),
    })
}

fn text(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)?.as_str().map(str::to_owned)
}

fn decode_pull(value: &Value) -> Option<NativeHostingChangeRequest> {
    let pull = value.as_object()?;
    Some(NativeHostingChangeRequest {
        stable_id: text(pull, "id")?,
        number: pull.get("number")?.as_u64()?,
        title: text(pull, "title")?,
        author: text(pull, "author")?,
        state: state_of(pull.get("state")?.as_str()?)?,
        draft: pull.get("draft")?.as_bool()?,
        source_repository: text(pull, "sourceRepository")?,
        source_branch: text(pull, "sourceBranch")?,
        target_repository: text(pull, "targetRepository")?,
        target_branch: text(pull, "targetBranch")?,
        head_sha: text(pull, "head")?,
        web_url: text(pull, "url")?,
        // Reviews, mergeability and individual checks are not kept: they are only shown fresh.
        review_summary: NativeHostingReviewSummary::Unknown,
        mergeability: NativeHostingMergeability::Unknown,
        checks: NativeHostingCheckSummary {
            state: checks_of(pull.get("checks")?.as_str()?)?,
            checks: Vec::new(),
        },
    })
}

fn encode(entry: &LinkEntry) -> Vec<u8> {
    let branches: Vec<&(String, Vec<NativeHostingChangeRequest>)> = entry
        .branches
        .iter()
        .filter(|(_, pulls)| !pulls.is_empty())
        .collect();
    let skip = branches.len().saturating_sub(BRANCH_LIMIT);
    let value = json!({
        "schema": SCHEMA,
        "connection": entry.connection_id,
        "repository": entry.provider_repository,
        "branches": branches
            .into_iter()
            .skip(skip)
            .map(|(branch, pulls)| json!({
                "branch": branch,
                "pulls": pulls.iter().map(encode_pull).collect::<Vec<_>>(),
            }))
            .collect::<Vec<_>>(),
        "authored": entry
            .authored
            .as_ref()
            .map(|pulls| pulls.iter().map(encode_pull).collect::<Vec<_>>()),
    });
    serde_json::to_vec(&value).unwrap_or_default()
}

/// The entry in `bytes`, or `None` for another schema or damaged data.
fn decode(bytes: &[u8]) -> Option<LinkEntry> {
    let value: Value = serde_json::from_slice(bytes).ok()?;
    let map = value.as_object()?;
    if map.get("schema")?.as_u64()? != SCHEMA {
        return None;
    }
    let mut branches = Vec::new();
    for branch in map.get("branches")?.as_array()? {
        let branch = branch.as_object()?;
        let pulls = branch
            .get("pulls")?
            .as_array()?
            .iter()
            .map(decode_pull)
            .collect::<Option<Vec<_>>>()?;
        branches.push((text(branch, "branch")?, pulls));
    }
    let authored = match map.get("authored") {
        None | Some(Value::Null) => None,
        Some(value) => Some(
            value
                .as_array()?
                .iter()
                .map(decode_pull)
                .collect::<Option<Vec<_>>>()?,
        ),
    };
    Some(LinkEntry {
        connection_id: text(map, "connection")?,
        provider_repository: text(map, "repository")?,
        branches,
        authored,
    })
}

#[derive(Default)]
struct Inner {
    /// Least recently used first.
    entries: Vec<(NativePathIdentity, Rc<LinkEntry>)>,
    pending: Vec<(NativePathIdentity, TimerHandle)>,
}

/// The link cache of every repository, in memory and in private storage.
pub struct LinkCache {
    store: Rc<EntryStore>,
    inner: RefCell<Inner>,
    this: Weak<LinkCache>,
}

impl LinkCache {
    #[must_use]
    pub fn new() -> Rc<Self> {
        Rc::new_cyclic(|this| Self {
            store: EntryStore::new("hosting-links"),
            inner: RefCell::new(Inner::default()),
            this: this.clone(),
        })
    }

    fn known(&self, repository: &NativePathIdentity) -> Option<Rc<LinkEntry>> {
        self.inner
            .borrow()
            .entries
            .iter()
            .find(|(key, _)| key == repository)
            .map(|(_, entry)| Rc::clone(entry))
    }

    fn trim(inner: &mut Inner) {
        while inner.entries.len() > CAPACITY {
            inner.entries.remove(0);
        }
    }

    /// The links last learned for `repository` under the given binding, from memory or
    /// private storage.
    pub async fn cached(
        &self,
        repository: &NativePathIdentity,
        connection_id: &str,
        provider_repository: &str,
    ) -> Option<Rc<LinkEntry>> {
        if repository.remote.is_some() {
            return None;
        }
        let entry = match self.known(repository) {
            Some(entry) => entry,
            None => {
                let bytes = self.store.read(repository).await?;
                let decoded = rt::blocking(move || decode(&bytes)).await;
                let Some(decoded) = decoded else {
                    // Another schema or damaged data; the links are looked up again.
                    self.store.remove(repository).await;
                    return None;
                };
                let mut inner = self.inner.borrow_mut();
                // What this run has learned meanwhile is newer than the storage.
                match inner.entries.iter().find(|(key, _)| key == repository) {
                    Some((_, entry)) => Rc::clone(entry),
                    None => {
                        let entry = Rc::new(decoded);
                        inner.entries.push((repository.clone(), Rc::clone(&entry)));
                        Self::trim(&mut inner);
                        entry
                    }
                }
            }
        };
        entry
            .matches(connection_id, provider_repository)
            .then_some(entry)
    }

    /// Keeps `entry` for `repository`, writing it to private storage shortly.
    pub fn remember(&self, repository: &NativePathIdentity, entry: LinkEntry) {
        if repository.remote.is_some() {
            return;
        }
        let mut inner = self.inner.borrow_mut();
        inner.entries.retain(|(key, _)| key != repository);
        inner.entries.push((repository.clone(), Rc::new(entry)));
        Self::trim(&mut inner);
        inner.pending.retain(|(key, _)| key != repository);
        let this = self.this.clone();
        let key = repository.clone();
        let timer = TimerHandle::start(PERSIST_DELAY, move || {
            if let Some(this) = this.upgrade() {
                this.inner
                    .borrow_mut()
                    .pending
                    .retain(|(pending, _)| pending != &key);
                rt::spawn_detached(async move { this.write(&key).await });
            }
        });
        inner.pending.push((repository.clone(), timer));
    }

    async fn write(&self, repository: &NativePathIdentity) {
        let Some(entry) = self.known(repository) else {
            return;
        };
        let entry = (*entry).clone();
        let bytes = rt::blocking(move || encode(&entry)).await;
        self.store.write(repository, bytes).await;
    }

    /// Writes every changed entry now.
    pub async fn flush(&self) {
        let repositories: Vec<NativePathIdentity> = self
            .inner
            .borrow_mut()
            .pending
            .drain(..)
            .map(|(key, mut timer)| {
                timer.cancel();
                key
            })
            .collect();
        for repository in repositories {
            self.write(&repository).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pull(number: u64) -> NativeHostingChangeRequest {
        NativeHostingChangeRequest {
            stable_id: format!("id-{number}"),
            number,
            title: "Title".to_owned(),
            author: "someone".to_owned(),
            state: NativeHostingChangeRequestState::Open,
            draft: false,
            source_repository: "owner/repo".to_owned(),
            source_branch: "feature".to_owned(),
            target_repository: "owner/repo".to_owned(),
            target_branch: "main".to_owned(),
            head_sha: "a".repeat(40),
            web_url: "https://example.invalid/pull/1".to_owned(),
            review_summary: NativeHostingReviewSummary::Unknown,
            mergeability: NativeHostingMergeability::Unknown,
            checks: NativeHostingCheckSummary {
                state: NativeHostingCheckState::Passing,
                checks: Vec::new(),
            },
        }
    }

    #[test]
    fn entries_round_trip_in_the_stored_format_of_earlier_releases() {
        let entry = LinkEntry {
            connection_id: "connection".to_owned(),
            provider_repository: "owner/repo".to_owned(),
            branches: vec![("feature".to_owned(), vec![pull(1)])],
            authored: Some(vec![pull(2)]),
        };
        let bytes = encode(&entry);
        assert_eq!(decode(&bytes), Some(entry));
        // As an earlier release wrote it.
        let earlier = br#"{"schema":1,"connection":"c","repository":"o/r","branches":[{"branch":"b","pulls":[{"id":"x","number":3,"title":"t","author":"a","state":"merged","draft":true,"sourceRepository":"o/r","sourceBranch":"b","targetRepository":"o/r","targetBranch":"main","head":"h","url":"u","checks":"failing"}]}],"authored":null}"#;
        let decoded = decode(earlier).expect("an earlier entry");
        assert_eq!(
            decoded.branches[0].1[0].state,
            NativeHostingChangeRequestState::Merged
        );
        assert_eq!(
            decoded.branches[0].1[0].checks.state,
            NativeHostingCheckState::Failing
        );
        assert!(decoded.authored.is_none());
        assert!(decode(br#"{"schema":2}"#).is_none());
    }

    #[test]
    fn only_the_most_recent_branches_are_kept() {
        let entry = LinkEntry {
            connection_id: "c".to_owned(),
            provider_repository: "o/r".to_owned(),
            branches: (0..BRANCH_LIMIT + 5)
                .map(|index| (format!("b{index}"), vec![pull(index as u64)]))
                .chain(std::iter::once(("empty".to_owned(), Vec::new())))
                .collect(),
            authored: None,
        };
        let decoded = decode(&encode(&entry)).unwrap();
        assert_eq!(decoded.branches.len(), BRANCH_LIMIT);
        assert_eq!(decoded.branches[0].0, "b5");
    }
}
