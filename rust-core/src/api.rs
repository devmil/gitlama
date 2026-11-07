pub use gitlama_contract::avatar::{NativeAvatarImage, NativeAvatarSource};
pub use gitlama_contract::dto::*;

pub fn avatar_image(hash: String, enabled: bool) -> Option<NativeAvatarImage> {
    crate::avatar::avatar_image(hash, enabled)
}

pub fn avatar_clear_cache() {
    crate::avatar::avatar_clear_cache();
}
use devmil_git::version::GitVersion;
pub use gitlama_contract::cli_forwarding::{
    NativeCliCommand, NativeCliCommandKind, NativeCliFailureKind, NativeCliPathPlatform,
    NativeCliPollResult, NativeCliPullStrategy, NativeCliResponseKind, NativeCliStartupResult,
    NativeCliStartupState,
};
pub use gitlama_contract::hosting::{
    NativeHostingAuthentication, NativeHostingBindingResult, NativeHostingBindingState,
    NativeHostingCapability, NativeHostingChangeRequest, NativeHostingChangeRequestState,
    NativeHostingCheck, NativeHostingCheckState, NativeHostingCheckSummary,
    NativeHostingConnection, NativeHostingConnectionResult, NativeHostingCredentialResult,
    NativeHostingCredentialState, NativeHostingFailureKind, NativeHostingIssue,
    NativeHostingIssueState, NativeHostingLinkResult, NativeHostingMergeability,
    NativeHostingPreset, NativeHostingPresetDefaults, NativeHostingPresetDefaultsResult,
    NativeHostingRemote, NativeHostingRemoteReference, NativeHostingRemoteReferenceKind,
    NativeHostingResourceKind, NativeHostingResources, NativeHostingReviewSummary,
};
pub use gitlama_contract::hosting_reference::{
    NativeHostingReferenceApplyResult, NativeHostingReferenceCandidate,
    NativeHostingReferenceFailure, NativeHostingReferenceProjection,
    NativeHostingReferenceProjectionResult,
};
pub use gitlama_contract::hosting_review::{
    NativeHostingCheckRetryPreview, NativeHostingCheckRetryPreviewResult, NativeHostingInlineDraft,
    NativeHostingReviewAction, NativeHostingReviewAnchor, NativeHostingReviewDiff,
    NativeHostingReviewDraft, NativeHostingReviewDraftResult, NativeHostingReviewFailure,
    NativeHostingReviewLoadResult, NativeHostingReviewPage, NativeHostingReviewPreview,
    NativeHostingReviewPreviewResult, NativeHostingReviewSubmitResult,
    NativeHostingReviewSubmitState, NativeHostingReviewThread,
};
pub use gitlama_contract::hosting_runtime::{
    NativeHostingBranchPullRequests, NativeHostingOAuthFailure, NativeHostingOAuthPollResult,
    NativeHostingOAuthSnapshot, NativeHostingOAuthStartResult, NativeHostingOAuthState,
    NativeHostingPullRequestLookupPollResult, NativeHostingPullRequestLookupSnapshot,
    NativeHostingPullRequestLookupStartResult, NativeHostingResourceFailure,
    NativeHostingResourceLoadState, NativeHostingResourcePollResult, NativeHostingResourceSnapshot,
    NativeHostingResourceStartResult,
};

/// Runs through FRB's worker pool and proves the shared Git crate is linked.
#[must_use]
pub fn core_info() -> CoreInfo {
    devmil_logging::record("gitlama.native_ready", "INFO", &[], false);
    let minimum = GitVersion::new(2, 39, 0);
    CoreInfo {
        protocol_version: 1,
        minimum_git_major: minimum.major,
        minimum_git_minor: minimum.minor,
        minimum_git_patch: minimum.patch,
    }
}

/// Where pending remote writes are recorded, beside the settings document.
#[must_use]
pub fn remote_pending_default_directory() -> Option<String> {
    gitlama_application::remote_pending::default_directory()
}

/// Loads pending and recently resolved remote writes. Unreadable or corrupt data is reported,
/// never replaced.
#[must_use]
pub fn remote_pending_load(directory: String) -> NativeRemotePendingLoadResult {
    gitlama_application::remote_pending::load(&directory)
}

/// Atomically replaces the pending remote write record.
#[must_use]
pub fn remote_pending_save(
    directory: String,
    operations: Vec<NativeRemotePendingOperation>,
) -> NativeRemotePendingSaveResult {
    gitlama_application::remote_pending::save(&directory, operations)
}

pub use gitlama_contract::child_process::{
    NativeCapturedProcess, NativeChildEvent, NativeChildEventKind, NativeEnvironmentVariable,
};

/// Starts a child process the application owns outside Git, such as the SSH transport of a
/// remote workspace, and reports its output and exit on `sink`. See [`crate::child_process`].
pub fn child_process_start(
    executable: String,
    arguments: Vec<String>,
    environment: Vec<NativeEnvironmentVariable>,
    sink: crate::frb_generated::StreamSink<NativeChildEvent>,
) {
    crate::child_process::start(executable, arguments, environment, sink);
}

/// Queues bytes for a child's standard input; false once it closed.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn child_process_write(child_id: u64, bytes: Vec<u8>) -> bool {
    crate::child_process::write(child_id, bytes)
}

#[flutter_rust_bridge::frb(sync)]
pub fn child_process_close_stdin(child_id: u64) {
    crate::child_process::close_stdin(child_id);
}

/// Sends SIGTERM, or SIGKILL when `kill`, to a running child.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn child_process_signal(child_id: u64, kill: bool) -> bool {
    crate::child_process::signal(child_id, kill)
}

/// Runs a short probe such as `ssh -V` and keeps its bounded standard error.
#[must_use]
pub fn child_process_run_capture(
    executable: String,
    arguments: Vec<String>,
    timeout_ms: u32,
    maximum_bytes: u32,
) -> NativeCapturedProcess {
    crate::child_process::run_capture(executable, arguments, timeout_ms, maximum_bytes)
}

/// The remote helper ID this library was built with: the helper's compatibility version as 40
/// decimal digits. A remote helper must report the same ID before the client sends it any
/// repository request.
#[must_use]
pub fn remote_helper_build_id() -> String {
    gitlama_application::remote_session_policy::BUILD_ID.to_owned()
}

/// Identifies the installed release for update checks.
#[must_use]
pub fn application_release() -> NativeApplicationRelease {
    NativeApplicationRelease {
        version: gitlama_application::release::RELEASE_VERSION.to_owned(),
        build: gitlama_application::release::RELEASE_BUILD
            .parse()
            .expect("the build script validated the build number"),
    }
}

#[must_use]
pub fn cli_forwarding_prepare_process() -> NativeCliStartupResult {
    crate::cli_forwarding::prepare_process_invocation()
}

#[must_use]
pub fn cli_forwarding_ensure_owner() -> NativeCliStartupResult {
    crate::cli_forwarding::ensure_owner()
}

#[must_use]
pub fn cli_forwarding_poll() -> NativeCliPollResult {
    crate::cli_forwarding::poll()
}

#[must_use]
pub fn cli_forwarding_respond(request_id: u64, response: NativeCliResponseKind) -> bool {
    crate::cli_forwarding::respond(request_id, response)
}

pub fn cli_forwarding_shutdown() {
    crate::cli_forwarding::shutdown();
}

#[must_use]
pub fn hosting_connection_validate(
    connection: NativeHostingConnection,
) -> NativeHostingConnectionResult {
    crate::hosting::validate_native_connection(connection)
}

/// The defaults a new connection of `preset` starts with; `web_base` is the user-entered web
/// origin of a self-hosted preset.
#[must_use]
pub fn hosting_preset_defaults(
    preset: NativeHostingPreset,
    web_base: Option<String>,
) -> NativeHostingPresetDefaultsResult {
    crate::hosting::preset_defaults(preset, web_base)
}

#[must_use]
pub fn hosting_github_cli_available() -> bool {
    crate::hosting::github_cli_available()
}

#[must_use]
pub fn hosting_gitlab_cli_available() -> bool {
    crate::hosting::gitlab_cli_available()
}

/// Publishes the provider-neutral resource schema before provider adapters populate it.
#[must_use]
pub const fn hosting_empty_resources() -> NativeHostingResources {
    crate::hosting::empty_resources()
}

#[must_use]
pub fn hosting_oauth_start(connection: NativeHostingConnection) -> NativeHostingOAuthStartResult {
    crate::hosting_runtime::oauth_start(connection)
}

#[must_use]
pub fn hosting_oauth_poll(request_id: u64) -> NativeHostingOAuthPollResult {
    crate::hosting_runtime::oauth_poll(request_id)
}

#[must_use]
pub fn hosting_oauth_cancel(request_id: u64) -> bool {
    crate::hosting_runtime::oauth_cancel(request_id)
}

pub fn hosting_runtime_shutdown() {
    crate::hosting_runtime::shutdown();
}

#[must_use]
pub fn hosting_resources_start(
    connection: NativeHostingConnection,
    repository_id: String,
    page: u32,
    manual: bool,
) -> NativeHostingResourceStartResult {
    crate::hosting_runtime::resources_start(connection, repository_id, page, manual)
}

#[must_use]
pub fn hosting_resources_poll(request_id: u64) -> NativeHostingResourcePollResult {
    crate::hosting_runtime::resources_poll(request_id)
}

#[must_use]
pub fn hosting_resources_cancel(request_id: u64) -> bool {
    crate::hosting_runtime::resources_cancel(request_id)
}

#[must_use]
pub fn hosting_pull_request_lookup_start(
    connection: NativeHostingConnection,
    repository_id: String,
    heads: Vec<String>,
    branches: Vec<String>,
    authored_by: Option<String>,
) -> NativeHostingPullRequestLookupStartResult {
    crate::hosting_runtime::pull_request_lookup_start(
        connection,
        repository_id,
        heads,
        branches,
        authored_by,
    )
}

#[must_use]
pub fn hosting_pull_request_lookup_poll(
    request_id: u64,
) -> NativeHostingPullRequestLookupPollResult {
    crate::hosting_runtime::pull_request_lookup_poll(request_id)
}

#[must_use]
pub fn hosting_pull_request_lookup_cancel(request_id: u64) -> bool {
    crate::hosting_runtime::pull_request_lookup_cancel(request_id)
}

pub fn hosting_resources_deactivate(connection_id: String, repository_id: String) {
    crate::hosting_runtime::resources_deactivate(connection_id, repository_id);
}

#[must_use]
pub fn hosting_reference_project(
    text: Vec<u16>,
    selection_base: u32,
    selection_extent: u32,
    revision: u64,
    references: Vec<NativeHostingRemoteReference>,
    stale: bool,
) -> NativeHostingReferenceProjectionResult {
    crate::hosting_reference::project(
        text,
        selection_base,
        selection_extent,
        revision,
        references,
        stale,
    )
}

#[must_use]
pub fn hosting_review_load(
    connection: NativeHostingConnection,
    repository: String,
    pull_request: u64,
    head_sha: String,
    page: Option<String>,
) -> NativeHostingReviewLoadResult {
    crate::hosting_review::review_load(connection, repository, pull_request, head_sha, page)
}

#[must_use]
pub fn hosting_review_preview(
    connection: NativeHostingConnection,
    repository: String,
    pull_request: u64,
    head_sha: String,
    action: NativeHostingReviewAction,
    body: String,
    inline_comments: Vec<NativeHostingInlineDraft>,
) -> NativeHostingReviewPreviewResult {
    crate::hosting_review::review_preview(
        connection,
        repository,
        pull_request,
        head_sha,
        action,
        body,
        inline_comments,
    )
}

#[must_use]
pub fn hosting_review_submit(
    connection: NativeHostingConnection,
    preview: NativeHostingReviewPreview,
) -> NativeHostingReviewSubmitResult {
    crate::hosting_review::review_submit(connection, preview)
}

#[must_use]
pub fn hosting_check_retry_preview(
    connection: NativeHostingConnection,
    repository: String,
    head_sha: String,
    check_stable_id: String,
) -> NativeHostingCheckRetryPreviewResult {
    crate::hosting_review::check_retry_preview(connection, repository, head_sha, check_stable_id)
}

#[must_use]
pub fn hosting_check_retry_submit(
    connection: NativeHostingConnection,
    authorization_id: u64,
    repository: String,
    head_sha: String,
    check_stable_id: String,
) -> NativeHostingReviewSubmitResult {
    crate::hosting_review::check_retry_submit(
        connection,
        authorization_id,
        repository,
        head_sha,
        check_stable_id,
    )
}

#[must_use]
pub fn hosting_review_draft_load(key: String) -> NativeHostingReviewDraftResult {
    crate::hosting_review::draft_load(key)
}

#[must_use]
pub fn hosting_review_draft_save(
    draft: NativeHostingReviewDraft,
) -> NativeHostingReviewDraftResult {
    crate::hosting_review::draft_save(draft)
}

#[must_use]
pub fn hosting_review_draft_delete(key: String) -> NativeHostingReviewDraftResult {
    crate::hosting_review::draft_delete(key)
}

#[must_use]
pub fn hosting_review_cancel(connection_id: String, repository: String, pull_request: u64) -> bool {
    crate::hosting_review::review_cancel(connection_id, repository, pull_request)
}

#[must_use]
pub fn hosting_reference_apply(
    text: Vec<u16>,
    current_revision: u64,
    expected_revision: u64,
    expected_text_hash: u64,
    replace_start: u32,
    replace_end: u32,
    insertion: String,
) -> NativeHostingReferenceApplyResult {
    crate::hosting_reference::apply(
        text,
        current_revision,
        expected_revision,
        expected_text_hash,
        replace_start,
        replace_end,
        insertion,
    )
}

#[must_use]
pub fn hosting_binding_resolve(
    connections: Vec<NativeHostingConnection>,
    remotes: Vec<NativeHostingRemote>,
    override_connection_id: Option<String>,
) -> NativeHostingBindingResult {
    crate::hosting::resolve_binding(connections, remotes, override_connection_id)
}

#[must_use]
pub fn hosting_resource_link(
    connection: NativeHostingConnection,
    provider_repository: String,
    kind: NativeHostingResourceKind,
    number: Option<u64>,
) -> NativeHostingLinkResult {
    crate::hosting::canonical_resource_link(connection, provider_repository, kind, number)
}

#[must_use]
pub fn hosting_credential_state(
    connection: NativeHostingConnection,
) -> NativeHostingCredentialResult {
    crate::hosting::credential_state(connection)
}

#[must_use]
pub fn hosting_credential_remove(
    connection: NativeHostingConnection,
) -> NativeHostingCredentialResult {
    crate::hosting::remove_credential(connection)
}

#[must_use]
pub fn application_settings_load(path: String) -> NativeSettingsLoadResult {
    gitlama_application::storage::settings_load(path)
}

#[must_use]
pub fn application_settings_default_path() -> NativeSettingsPathResult {
    gitlama_application::storage::settings_default_path()
}

#[must_use]
pub fn application_settings_save(
    path: String,
    document: NativeSettingsDocument,
) -> NativeSettingsSaveResult {
    gitlama_application::storage::settings_save(path, document)
}

/// The private directory of the disposable per-repository view cache.
#[must_use]
pub fn application_view_cache_default_directory() -> Option<String> {
    gitlama_application::view_cache::view_cache_default_directory()
}

#[must_use]
pub fn application_view_cache_read(
    directory: String,
    identity: NativePathIdentity,
) -> NativeViewCacheReadResult {
    gitlama_application::view_cache::view_cache_read(directory, identity)
}

#[must_use]
pub fn application_view_cache_write(
    directory: String,
    identity: NativePathIdentity,
    bytes: Vec<u8>,
) -> NativeViewCacheCommandResult {
    gitlama_application::view_cache::view_cache_write(directory, identity, bytes)
}

#[must_use]
pub fn application_view_cache_remove(
    directory: String,
    identity: NativePathIdentity,
) -> NativeViewCacheCommandResult {
    gitlama_application::view_cache::view_cache_remove(directory, identity)
}

#[must_use]
pub fn application_recovery_begin(directory: String) -> NativeRecoveryStartResult {
    gitlama_application::recovery::recovery_begin(directory)
}

#[must_use]
pub fn application_recovery_default_directory() -> NativeRecoveryPathResult {
    gitlama_application::recovery::recovery_default_directory()
}

#[must_use]
pub fn application_recovery_checkpoint(
    directory: String,
    document: NativeSettingsDocument,
) -> NativeRecoveryCommandResult {
    gitlama_application::recovery::recovery_checkpoint(directory, document)
}

#[must_use]
pub fn application_recovery_finish_clean(
    directory: String,
    document: NativeSettingsDocument,
) -> NativeRecoveryCommandResult {
    gitlama_application::recovery::recovery_finish_clean(directory, document)
}

#[must_use]
pub fn application_recovery_inspect_repository(path: String) -> NativeSequencerInspectionResult {
    gitlama_application::recovery::recovery_inspect_repository(path)
}

#[must_use]
pub fn repository_clone_create(
    source: String,
    destination: String,
    initial_branch: Option<String>,
    generation: u64,
) -> NativeCloneCreateResult {
    gitlama_application::clone::clone_create(source, destination, initial_branch, generation)
}

#[must_use]
pub fn repository_clone_run(attempt_id: u64, generation: u64) -> NativeCloneRunResult {
    gitlama_application::clone::clone_run(
        &gitlama_application::application::session::SessionRegistry,
        attempt_id,
        generation,
    )
}

#[must_use]
pub fn repository_clone_run_with_credentials(
    attempt_id: u64,
    generation: u64,
    username: Option<String>,
    password: Option<String>,
    token: Option<String>,
) -> NativeCloneRunResult {
    gitlama_application::clone::clone_run_with_credentials(
        &gitlama_application::application::session::SessionRegistry,
        attempt_id,
        generation,
        username,
        password,
        token,
    )
}

#[must_use]
pub fn repository_clone_probe_host_key(attempt_id: u64, generation: u64) -> NativeHostKeyResult {
    gitlama_application::clone::clone_probe_host_key(attempt_id, generation)
}

#[must_use]
pub fn repository_clone_accept_host_key(
    attempt_id: u64,
    generation: u64,
    challenge_id: u64,
) -> NativeCloneCommandResult {
    gitlama_application::clone::clone_accept_host_key(attempt_id, generation, challenge_id)
}

#[must_use]
pub fn repository_clone_reject_host_key(
    attempt_id: u64,
    generation: u64,
    challenge_id: u64,
) -> NativeCloneCommandResult {
    gitlama_application::clone::clone_reject_host_key(attempt_id, generation, challenge_id)
}

#[must_use]
pub fn repository_clone_run_with_host_key(
    attempt_id: u64,
    generation: u64,
) -> NativeCloneRunResult {
    gitlama_application::clone::clone_run_with_host_key(
        &gitlama_application::application::session::SessionRegistry,
        attempt_id,
        generation,
    )
}

#[must_use]
pub fn repository_clone_snapshot(attempt_id: u64, generation: u64) -> NativeCloneSnapshotResult {
    gitlama_application::clone::clone_snapshot(attempt_id, generation)
}

#[must_use]
pub fn repository_clone_cancel(attempt_id: u64, generation: u64) -> NativeCloneCommandResult {
    gitlama_application::clone::clone_cancel(attempt_id, generation)
}

#[must_use]
pub fn repository_clone_retry(attempt_id: u64, generation: u64) -> NativeCloneSnapshotResult {
    gitlama_application::clone::clone_retry(attempt_id, generation)
}

#[must_use]
pub fn repository_clone_retry_at_destination(
    attempt_id: u64,
    generation: u64,
    destination: String,
) -> NativeCloneSnapshotResult {
    gitlama_application::clone::clone_retry_at_destination(attempt_id, generation, destination)
}

#[must_use]
pub fn repository_clone_dismiss(attempt_id: u64, generation: u64) -> NativeCloneCommandResult {
    gitlama_application::clone::clone_dismiss(attempt_id, generation)
}

#[must_use]
pub fn repository_session_open(path: String, generation: u64) -> NativeRepositoryOpenResult {
    gitlama_application::application::session::repository_session_open(path, generation)
}

#[must_use]
pub fn repository_session_open_identity(
    identity: NativePathIdentity,
    generation: u64,
) -> NativeRepositoryOpenResult {
    gitlama_application::application::session::repository_session_open_identity(
        identity, generation,
    )
}

#[must_use]
pub fn repository_initialize(
    path: String,
    initial_branch: String,
    bare: bool,
    generation: u64,
) -> NativeRepositoryOpenResult {
    gitlama_application::application::session::repository_initialize(
        path,
        initial_branch,
        bare,
        generation,
    )
}

#[must_use]
pub fn repository_session_activity(
    session_id: u64,
    generation: u64,
    maximum_records: u32,
) -> NativeRepositoryActivityResult {
    gitlama_application::application::session::repository_session_activity(
        session_id,
        generation,
        maximum_records,
    )
}

/// Loads one retained command, including its bounded output, by activity identity.
#[must_use]
pub fn repository_session_activity_record(
    session_id: u64,
    generation: u64,
    activity_id: u64,
) -> NativeRepositoryActivityResult {
    gitlama_application::application::session::repository_session_activity_record(
        session_id,
        generation,
        activity_id,
    )
}

/// Loads a bounded reflog page while retaining the last successfully loaded rows on failure.
#[must_use]
pub fn repository_session_reflog(
    session_id: u64,
    generation: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeReflogResult {
    gitlama_application::application::inspection::repository_session_reflog(
        session_id,
        generation,
        offset,
        maximum_rows,
    )
}

#[must_use]
pub fn repository_session_ref_mutation_preview(
    session_id: u64,
    generation: u64,
    request: NativeRefMutationRequest,
) -> NativeRefMutationPreviewResult {
    gitlama_application::application::refs::repository_session_ref_mutation_preview(
        session_id, generation, request,
    )
}

#[must_use]
pub fn repository_session_ref_mutation_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRefMutationExecutionResult {
    gitlama_application::application::refs::repository_session_ref_mutation_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_transfer_preview(
    session_id: u64,
    generation: u64,
    request: NativeTransferRequest,
) -> NativeTransferPreviewResult {
    gitlama_application::application::transfer::repository_session_transfer_preview(
        session_id, generation, request,
    )
}

#[must_use]
pub fn repository_session_transfer_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeTransferExecutionResult {
    gitlama_application::application::transfer::repository_session_transfer_execute(
        session_id, generation, token,
    )
}

/// Runs a previewed fetch that the application started by itself. It never
/// prompts, and the operation center lists it as background work.
#[must_use]
pub fn repository_session_transfer_execute_background(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeTransferExecutionResult {
    gitlama_application::application::transfer::repository_session_transfer_execute_background(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_transfer_execute_with_credentials(
    session_id: u64,
    generation: u64,
    token: u64,
    username: Option<String>,
    password: Option<String>,
    credential_token: Option<String>,
) -> NativeTransferExecutionResult {
    gitlama_application::application::transfer::repository_session_transfer_execute_with_credentials(
        session_id,
        generation,
        token,
        username,
        password,
        credential_token,
    )
}

#[must_use]
pub fn repository_session_transfer_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::transfer::repository_session_transfer_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_transfer_probe_host_key(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeHostKeyResult {
    gitlama_application::application::transfer::repository_session_transfer_probe_host_key(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_transfer_resolve_host_key(
    session_id: u64,
    generation: u64,
    token: u64,
    challenge_id: u64,
    accept: bool,
) -> NativeCloneCommandResult {
    gitlama_application::application::transfer::repository_session_transfer_resolve_host_key(
        session_id,
        generation,
        token,
        challenge_id,
        accept,
    )
}

#[must_use]
pub fn repository_session_stash_preview(
    session_id: u64,
    generation: u64,
    request: NativeStashRequest,
) -> NativeStashPreviewResult {
    gitlama_application::application::stash::repository_session_stash_preview(
        session_id, generation, request,
    )
}

#[must_use]
pub fn repository_session_stash_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeStashExecutionResult {
    gitlama_application::application::stash::repository_session_stash_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_stash_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::stash::repository_session_stash_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_named_snapshots(
    session_id: u64,
    generation: u64,
    offset: u32,
    maximum: u32,
) -> NativeNamedSnapshotListResult {
    gitlama_application::application::snapshots::repository_session_named_snapshots(
        session_id, generation, offset, maximum,
    )
}

#[must_use]
pub fn repository_session_named_snapshot_create(
    session_id: u64,
    generation: u64,
    name: String,
    include_untracked: bool,
    keep_index: bool,
) -> NativeNamedSnapshotExecutionResult {
    gitlama_application::application::snapshots::repository_session_named_snapshot_create(
        session_id,
        generation,
        name,
        include_untracked,
        keep_index,
    )
}

#[must_use]
pub fn repository_session_named_snapshot_restore_preview(
    session_id: u64,
    generation: u64,
    snapshot_id: u64,
) -> NativeNamedSnapshotRestorePreviewResult {
    gitlama_application::application::snapshots::repository_session_named_snapshot_restore_preview(
        session_id,
        generation,
        snapshot_id,
    )
}

#[must_use]
pub fn repository_session_named_snapshot_restore_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeNamedSnapshotExecutionResult {
    gitlama_application::application::snapshots::repository_session_named_snapshot_restore_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_named_snapshot_restore_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::snapshots::repository_session_named_snapshot_restore_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_named_snapshot_branch(
    session_id: u64,
    generation: u64,
    snapshot_id: u64,
    branch: Vec<u8>,
) -> NativeNamedSnapshotExecutionResult {
    gitlama_application::application::snapshots::repository_session_named_snapshot_branch(
        session_id,
        generation,
        snapshot_id,
        branch,
    )
}

#[must_use]
pub fn repository_session_named_snapshot_delete(
    session_id: u64,
    generation: u64,
    snapshot_id: u64,
) -> NativeNamedSnapshotExecutionResult {
    gitlama_application::application::snapshots::repository_session_named_snapshot_delete(
        session_id,
        generation,
        snapshot_id,
    )
}

#[must_use]
pub fn repository_session_extensions(
    session_id: u64,
    generation: u64,
) -> NativeExtensionInventoryResult {
    gitlama_application::application::extensions::repository_session_extensions(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_submodule_enter(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
) -> NativeSubmoduleEnterResult {
    gitlama_application::application::extensions::repository_session_submodule_enter(
        session_id, generation, path,
    )
}

#[must_use]
pub fn repository_session_lfs_pointer(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
) -> NativeLfsPointerResult {
    gitlama_application::application::extensions::repository_session_lfs_pointer(
        session_id, generation, path,
    )
}

/// The top-level `.gitignore` pattern that matches exactly this repository-relative path, or
/// `None` when no ignore line can express it.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn ignore_exact_pattern(path: Vec<u8>, directory: bool) -> Option<String> {
    devmil_git::ignore::exact_pattern(&path, directory)
}

#[must_use]
pub fn repository_session_extension_execute(
    session_id: u64,
    generation: u64,
    request: NativeExtensionMutationRequest,
) -> NativeExtensionMutationResult {
    gitlama_application::application::extensions::repository_session_extension_execute(
        session_id, generation, request,
    )
}

#[must_use]
pub fn integration_discover(kind: NativeIntegrationKind) -> NativeIntegrationDiscoveryResult {
    gitlama_application::application::integrations::integration_discover(kind)
}

#[must_use]
pub fn repository_session_integration_preview(
    session_id: u64,
    generation: u64,
    request: NativeIntegrationRequest,
) -> NativeIntegrationPreviewResult {
    gitlama_application::application::integrations::repository_session_integration_preview(
        session_id, generation, request,
    )
}

#[must_use]
pub fn repository_session_conflict_external_merge_preview(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    gitlama_application::application::integrations::repository_session_conflict_external_merge_preview(
        session_id,
        generation,
        path,
        expected_fingerprint,
        configured,
    )
}

#[must_use]
pub fn repository_session_commit_external_diff_preview(
    session_id: u64,
    generation: u64,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    gitlama_application::application::integrations::repository_session_commit_external_diff_preview(
        session_id,
        generation,
        old_revision,
        new_revision,
        old_path,
        new_path,
        configured,
    )
}

#[must_use]
pub fn repository_session_integration_execute(
    session_id: u64,
    generation: u64,
    token: u64,
    confirmed: bool,
) -> NativeIntegrationExecutionResult {
    gitlama_application::application::integrations::repository_session_integration_execute(
        session_id, generation, token, confirmed,
    )
}

#[must_use]
pub fn repository_session_integration_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::integrations::repository_session_integration_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_diff_content_search_start(
    session_id: u64,
    generation: u64,
    query: String,
    maximum_commits: u32,
) -> NativePowerJobStartResult {
    gitlama_application::application::power_tools::repository_session_diff_content_search_start(
        session_id,
        generation,
        query,
        maximum_commits,
    )
}

#[must_use]
pub fn repository_session_diff_content_search_start_configured(
    session_id: u64,
    generation: u64,
    options: NativeDiffSearchOptions,
) -> NativePowerJobStartResult {
    gitlama_application::application::power_tools::repository_session_diff_content_search_start_configured(
        session_id, generation, options,
    )
}

#[must_use]
pub fn repository_session_diff_content_search_poll(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiffContentSearchResult {
    gitlama_application::application::power_tools::repository_session_diff_content_search_poll(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_statistics_start(
    session_id: u64,
    generation: u64,
) -> NativePowerJobStartResult {
    gitlama_application::application::power_tools::repository_session_statistics_start(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_statistics_poll(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryStatisticsResult {
    gitlama_application::application::power_tools::repository_session_statistics_poll(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_power_job_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::power_tools::repository_session_power_job_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_bisect_state(
    session_id: u64,
    generation: u64,
) -> NativeBisectStateResult {
    gitlama_application::application::power_tools::repository_session_bisect_state(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_bisect_preview(
    session_id: u64,
    generation: u64,
    action: NativeBisectAction,
    good: Option<String>,
    bad: Option<String>,
) -> NativeBisectPreviewResult {
    gitlama_application::application::power_tools::repository_session_bisect_preview(
        session_id, generation, action, good, bad,
    )
}

#[must_use]
pub fn repository_session_bisect_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeBisectExecutionResult {
    gitlama_application::application::power_tools::repository_session_bisect_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_bisect_cancel_preview(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::power_tools::repository_session_bisect_cancel_preview(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_history_mutation_preview(
    session_id: u64,
    generation: u64,
    request: NativeHistoryMutationRequest,
) -> NativeHistoryMutationPreviewResult {
    gitlama_application::application::history_mutations::repository_session_history_mutation_preview(
        session_id, generation, request,
    )
}

#[must_use]
pub fn repository_session_history_mutation_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeHistoryMutationExecutionResult {
    gitlama_application::application::history_mutations::repository_session_history_mutation_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_history_mutation_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::history_mutations::repository_session_history_mutation_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_conflict_prediction_begin(
    session_id: u64,
    generation: u64,
) -> NativeConflictPredictionStartResult {
    gitlama_application::application::history_mutations::repository_session_conflict_prediction_begin(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_conflict_prediction(
    session_id: u64,
    generation: u64,
    token: u64,
    kind: NativeConflictPredictionKind,
    target: String,
) -> NativeConflictPredictionResult {
    gitlama_application::application::history_mutations::repository_session_conflict_prediction(
        session_id, generation, token, kind, target,
    )
}

#[must_use]
pub fn repository_session_conflict_prediction_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::history_mutations::repository_session_conflict_prediction_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_rebase_plan(
    session_id: u64,
    generation: u64,
    onto: String,
    onto_name: Option<Vec<u8>>,
) -> NativeRebasePlanResult {
    gitlama_application::application::rebase::repository_session_rebase_plan(
        session_id, generation, onto, onto_name,
    )
}

#[must_use]
pub fn repository_session_rebase_preview(
    session_id: u64,
    generation: u64,
    token: u64,
    instructions: Vec<NativeRebaseInstruction>,
    acknowledge_published_history: bool,
    apply_autosquash: bool,
) -> NativeRebasePreviewResult {
    gitlama_application::application::rebase::repository_session_rebase_preview(
        session_id,
        generation,
        token,
        instructions,
        acknowledge_published_history,
        apply_autosquash,
    )
}

#[must_use]
pub fn repository_session_rebase_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRebaseExecutionResult {
    gitlama_application::application::rebase::repository_session_rebase_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_rebase_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::rebase::repository_session_rebase_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_fixup_suggestion(
    session_id: u64,
    generation: u64,
    selected_commit: Option<String>,
    paths: Vec<Vec<u8>>,
) -> NativeFixupSuggestionResult {
    gitlama_application::application::rebase::repository_session_fixup_suggestion(
        session_id,
        generation,
        selected_commit,
        paths,
    )
}

#[must_use]
pub fn repository_session_restack_plan(
    session_id: u64,
    generation: u64,
    root_branch: Vec<u8>,
) -> NativeRestackPlanResult {
    gitlama_application::application::rebase::repository_session_restack_plan(
        session_id,
        generation,
        root_branch,
    )
}

#[must_use]
pub fn repository_session_restack_execute(
    session_id: u64,
    generation: u64,
    token: u64,
    acknowledge_published_history: bool,
) -> NativeRestackExecutionResult {
    gitlama_application::application::rebase::repository_session_restack_execute(
        session_id,
        generation,
        token,
        acknowledge_published_history,
    )
}

#[must_use]
pub fn repository_session_restack_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::rebase::repository_session_restack_cancel(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_conflicts(
    session_id: u64,
    generation: u64,
) -> NativeConflictSnapshotResult {
    gitlama_application::application::conflicts::repository_session_conflicts(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_conflict_save_result(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    result: Vec<u8>,
) -> NativeConflictSnapshotResult {
    gitlama_application::application::conflicts::repository_session_conflict_save_result(
        session_id,
        generation,
        path,
        expected_fingerprint,
        result,
    )
}

#[must_use]
pub fn repository_session_conflict_choose_side(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    choice: NativeConflictSideChoice,
) -> NativeConflictSnapshotResult {
    gitlama_application::application::conflicts::repository_session_conflict_choose_side(
        session_id,
        generation,
        path,
        expected_fingerprint,
        choice,
    )
}

#[must_use]
pub fn repository_session_conflict_take_region(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    region_index: u32,
    choice: NativeConflictRegionChoice,
) -> NativeConflictSnapshotResult {
    gitlama_application::application::conflicts::repository_session_conflict_take_region(
        session_id,
        generation,
        path,
        expected_fingerprint,
        region_index,
        choice,
    )
}

#[must_use]
pub fn repository_session_conflict_undo_resolution(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
) -> NativeConflictSnapshotResult {
    gitlama_application::application::conflicts::repository_session_conflict_undo_resolution(
        session_id, generation, path,
    )
}

#[must_use]
pub fn repository_session_conflict_continue(
    session_id: u64,
    generation: u64,
    action: NativeConflictSequencerAction,
) -> NativeConflictContinuationResult {
    gitlama_application::application::conflicts::repository_session_conflict_continue(
        session_id, generation, action,
    )
}

#[must_use]
pub fn repository_session_conflict_continue_with_message(
    session_id: u64,
    generation: u64,
    action: NativeConflictSequencerAction,
    message: String,
) -> NativeConflictContinuationResult {
    gitlama_application::application::conflicts::repository_session_conflict_continue_with_message(
        session_id, generation, action, message,
    )
}

/// Loads byte-preserving commit metadata and its changed-file inventory.
#[must_use]
pub fn repository_session_commit_inspection(
    session_id: u64,
    generation: u64,
    commit: String,
    first_parent: Option<String>,
) -> NativeCommitInspectionResult {
    gitlama_application::application::inspection::repository_session_commit_inspection(
        session_id,
        generation,
        commit,
        first_parent,
    )
}

/// Loads an ordered commit-detail batch with one shared cached Git invocation.
#[must_use]
pub fn repository_session_commit_details(
    session_id: u64,
    generation: u64,
    commits: Vec<String>,
) -> NativeCommitDetailsResult {
    gitlama_application::application::inspection::repository_session_commit_details(
        session_id, generation, commits,
    )
}

/// Loads one commit directory through the repository cache and pages its immutable snapshot.
#[must_use]
pub fn repository_session_tree(
    session_id: u64,
    generation: u64,
    commit: String,
    directory: Option<Vec<u8>>,
    offset: u64,
    maximum_rows: u32,
) -> NativeTreeResult {
    gitlama_application::application::inspection::repository_session_tree(
        session_id,
        generation,
        commit,
        directory,
        offset,
        maximum_rows,
    )
}

/// Reads the selected commit's file bytes for the bounded tree preview.
#[must_use]
pub fn repository_session_commit_file_content(
    session_id: u64,
    generation: u64,
    commit: String,
    path: Vec<u8>,
) -> NativeCommitFileContentResult {
    gitlama_application::application::inspection::repository_session_commit_file_content(
        session_id, generation, commit, path,
    )
}

#[must_use]
pub fn repository_session_path_history(
    session_id: u64,
    generation: u64,
    options: NativePathHistoryOptions,
) -> NativePathHistoryResult {
    gitlama_application::application::inspection::repository_session_path_history(
        session_id, generation, options,
    )
}

#[must_use]
pub fn repository_session_range_history(
    session_id: u64,
    generation: u64,
    revision: String,
    path: Vec<u8>,
    first_line: u32,
    last_line: u32,
    maximum_rows: u32,
) -> NativeRangeHistoryResult {
    gitlama_application::application::inspection::repository_session_range_history(
        session_id,
        generation,
        revision,
        path,
        first_line,
        last_line,
        maximum_rows,
    )
}

#[must_use]
pub fn repository_session_blame_load(
    session_id: u64,
    generation: u64,
    options: NativeBlameOptions,
) -> NativeBlameResult {
    gitlama_application::application::inspection::repository_session_blame_load(
        session_id, generation, options,
    )
}

#[must_use]
pub fn repository_session_blame_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeBlameResult {
    gitlama_application::application::inspection::repository_session_blame_page(
        session_id,
        generation,
        request_id,
        offset,
        maximum_rows,
    )
}

/// Previews a byte-exact file restore and retains current-target preconditions.
#[must_use]
pub fn repository_session_restore_preview(
    session_id: u64,
    generation: u64,
    commit: String,
    path: Vec<u8>,
    byte_limit: u32,
) -> NativeRestorePreviewResult {
    gitlama_application::application::restore::repository_session_restore_preview(
        session_id, generation, commit, path, byte_limit,
    )
}

/// Restores a previewed file only while HEAD and current bytes match the preview.
#[must_use]
pub fn repository_session_restore_file(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRestoreResult {
    gitlama_application::application::restore::repository_session_restore_file(
        session_id, generation, token,
    )
}

/// Loads a frozen topological history projection and returns its first bounded page.
///
/// Lane reservations use complete topology even for the first bounded page: a prefix
/// cannot identify HEAD ancestry through parents outside that prefix. The accepted
/// projection remains session-owned for cheap bounded
/// window reads and is replaced only by the newest request.
///
/// The history starts from HEAD, branches, remote-tracking branches, tags and the stash.
/// With `other_refs` it also starts from every other reference, such as notes or a tool's
/// checkpoints.
#[must_use]
pub fn repository_session_history_load(
    session_id: u64,
    generation: u64,
    complete: bool,
    maximum_rows: u32,
    other_refs: bool,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_load(
        session_id,
        generation,
        complete,
        maximum_rows,
        other_refs,
    )
}

#[must_use]
pub fn repository_session_history_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_page(
        session_id,
        generation,
        request_id,
        offset,
        maximum_rows,
    )
}

/// Completes a retained preview against the same frozen tips and request identity.
#[must_use]
pub fn repository_session_history_complete(
    session_id: u64,
    generation: u64,
    request_id: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_complete(
        session_id,
        generation,
        request_id,
        maximum_rows,
    )
}

/// Replaces the accepted query over the retained complete topology.
///
/// Metadata and path matches are loaded through shared repository reads. Publication is
/// conditional on the newest query sequence, so a delayed query cannot replace a newer one.
#[must_use]
pub fn repository_session_history_query(
    session_id: u64,
    generation: u64,
    request_id: u64,
    options: NativeHistoryQueryOptions,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_query(
        session_id, generation, request_id, options,
    )
}

/// Replaces the session's history branch filter.
///
/// The filter shows every commit reachable from the named references and
/// survives history reloads, so later previews and completions publish already
/// filtered. An empty filter shows all references. When the retained history
/// matches `request_id`, its view is rebuilt only if the filter changed and the
/// requested window is returned; otherwise the result carries no page. Unknown
/// references match nothing.
#[must_use]
pub fn repository_session_history_branch_filter(
    session_id: u64,
    generation: u64,
    request_id: u64,
    references: Vec<Vec<u8>>,
    offset: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_branch_filter(
        session_id,
        generation,
        request_id,
        references,
        offset,
        maximum_rows,
    )
}

/// Toggles one merge side-branch collapse while retaining identity-based selection.
#[must_use]
pub fn repository_session_history_collapse(
    session_id: u64,
    generation: u64,
    request_id: u64,
    object_id: String,
    offset: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_collapse(
        session_id,
        generation,
        request_id,
        object_id,
        offset,
        maximum_rows,
    )
}

/// Applies ancestry lighting to the retained topology without rebuilding it.
#[must_use]
pub fn repository_session_history_select(
    session_id: u64,
    generation: u64,
    request_id: u64,
    options: NativeHistorySelectionOptions,
) -> NativeHistoryResult {
    gitlama_application::application::history::repository_session_history_select(
        session_id, generation, request_id, options,
    )
}

/// Hydrates one caller-prioritized bounded metadata batch for the retained topology.
#[must_use]
pub fn repository_session_history_metadata(
    session_id: u64,
    generation: u64,
    request_id: u64,
    object_ids: Vec<String>,
) -> NativeHistoryMetadataResult {
    gitlama_application::application::history::repository_session_history_metadata(
        session_id, generation, request_id, object_ids,
    )
}

/// Loads a committed diff through the shared repository cache and publishes one bounded page.
#[must_use]
pub fn repository_session_commit_diff_load(
    session_id: u64,
    generation: u64,
    options: NativeCommitDiffOptions,
) -> NativeDiffResult {
    gitlama_application::application::diff::repository_session_commit_diff_load(
        session_id, generation, options,
    )
}

#[must_use]
pub fn repository_session_diff_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeDiffResult {
    gitlama_application::application::diff::repository_session_diff_page(
        session_id,
        generation,
        request_id,
        offset,
        maximum_rows,
    )
}

/// Builds a forward unified patch for the change lines among [row_ids] of the
/// current commit diff or, when [working] is set, the current working diff.
/// Context rows are accepted and stay context. `patch` is `None` when the
/// selection holds no change line.
#[must_use]
pub fn repository_session_diff_selection_patch(
    session_id: u64,
    generation: u64,
    request_id: u64,
    working: bool,
    row_ids: Vec<String>,
) -> NativeDiffSelectionPatchResult {
    gitlama_application::application::diff::repository_session_diff_selection_patch(
        session_id, generation, request_id, working, row_ids,
    )
}

#[must_use]
pub fn repository_session_diff_search(
    session_id: u64,
    generation: u64,
    request_id: u64,
    query: Vec<u8>,
    case_sensitive: bool,
    maximum_matches: u32,
) -> NativeDiffSearchResult {
    gitlama_application::application::diff::repository_session_diff_search(
        session_id,
        generation,
        request_id,
        query,
        case_sensitive,
        maximum_matches,
    )
}

#[must_use]
pub fn repository_session_diff_hunks(
    session_id: u64,
    generation: u64,
    request_id: u64,
    maximum_positions: u32,
) -> NativeDiffPositionsResult {
    gitlama_application::application::diff::repository_session_diff_hunks(
        session_id,
        generation,
        request_id,
        maximum_positions,
    )
}

/// Loads an authoritative staged or unstaged diff and retains exact index/worktree preconditions.
#[must_use]
pub fn repository_session_working_diff_load(
    session_id: u64,
    generation: u64,
    options: NativeWorkingDiffOptions,
) -> NativeDiffResult {
    gitlama_application::application::diff::repository_session_working_diff_load(
        session_id, generation, options,
    )
}

#[must_use]
pub fn repository_session_working_diff_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeDiffResult {
    gitlama_application::application::diff::repository_session_working_diff_page(
        session_id,
        generation,
        request_id,
        offset,
        maximum_rows,
    )
}

/// Syntax categories for rows of the session's accepted committed or working diff. Plain text
/// stays authoritative; any side without exact categories reports why in its state.
#[must_use]
pub fn repository_session_diff_syntax_page(
    session_id: u64,
    generation: u64,
    request: NativeDiffSyntaxRequest,
) -> NativeDiffSyntaxResult {
    gitlama_application::application::diff_syntax::repository_session_diff_syntax_page(
        session_id, generation, request,
    )
}

/// Cancels one syntax request; idempotent.
#[must_use]
pub fn repository_session_diff_syntax_cancel(
    session_id: u64,
    generation: u64,
    origin: NativeDiffSyntaxOrigin,
    diff_request_id: u64,
    syntax_request_id: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::diff_syntax::repository_session_diff_syntax_cancel(
        session_id,
        generation,
        origin,
        diff_request_id,
        syntax_request_id,
    )
}

/// Syntax categories for lines of text the caller holds, such as a conflicted file's sides or
/// its unsaved merge result, parsed on this machine. Plain text stays authoritative.
#[must_use]
pub fn text_syntax_page(request: NativeTextSyntaxRequest) -> NativeTextSyntaxResult {
    gitlama_application::application::diff_syntax::text_syntax_page(request)
}

/// Cancels one text syntax request; idempotent.
#[must_use]
pub fn text_syntax_cancel(view_id: u64, syntax_request_id: u64) -> bool {
    gitlama_application::application::diff_syntax::text_syntax_cancel(view_id, syntax_request_id)
}

/// The current staging phase, without waiting for the Git worker.
#[must_use]
pub fn repository_session_staging_phase(
    session_id: u64,
    generation: u64,
) -> Option<NativeStagingPhase> {
    gitlama_application::application::staging::repository_session_staging_phase(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_staging_execute(
    session_id: u64,
    generation: u64,
    request: NativeStagingRequest,
) -> NativeStagingExecutionResult {
    gitlama_application::application::staging::repository_session_staging_execute(
        session_id, generation, request,
    )
}

/// Loads bounded recent messages and the configured commit template through the shared worker.
#[must_use]
pub fn repository_session_commit_tools(
    session_id: u64,
    generation: u64,
) -> NativeCommitToolsResult {
    gitlama_application::application::commit::repository_session_commit_tools(
        session_id, generation,
    )
}

/// Validates a commit request and retains the exact HEAD and index accepted by the user.
#[must_use]
pub fn repository_session_commit_preview(
    session_id: u64,
    generation: u64,
    request: NativeCommitRequest,
) -> NativeCommitPreviewResult {
    gitlama_application::application::commit::repository_session_commit_preview(
        session_id, generation, request,
    )
}

/// Executes one accepted commit. A requested push is a separate terminal outcome.
#[must_use]
pub fn repository_session_commit_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeCommitExecutionResult {
    gitlama_application::application::commit::repository_session_commit_execute(
        session_id, generation, token,
    )
}

/// Freezes the exact paths or working-diff rows that an irreversible action may change.
#[must_use]
pub fn repository_session_discard_preview(
    session_id: u64,
    generation: u64,
    request: NativeDiscardRequest,
) -> NativeDiscardPreviewResult {
    gitlama_application::application::discard::repository_session_discard_preview(
        session_id, generation, request,
    )
}

/// Executes one confirmed irreversible action.
#[must_use]
pub fn repository_session_discard_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiscardExecutionResult {
    gitlama_application::application::discard::repository_session_discard_execute(
        session_id, generation, token,
    )
}

/// Resolves patch scope in product precedence order and freezes one nonempty output.
#[must_use]
pub fn repository_session_patch_export_preview(
    session_id: u64,
    generation: u64,
    request: NativePatchExportRequest,
) -> NativePatchExportPreviewResult {
    gitlama_application::application::patch::repository_session_patch_export_preview(
        session_id, generation, request,
    )
}

#[must_use]
pub fn repository_session_patch_export_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativePatchExportExecutionResult {
    gitlama_application::application::patch::repository_session_patch_export_execute(
        session_id, generation, token,
    )
}

/// Builds the patch `request` names without writing it, for a repository whose patch is saved
/// on another computer: the first page comes with it and
/// [`repository_session_patch_export_content_page`] returns the rest of the same bytes. The
/// destination fields of `request` are ignored.
#[must_use]
pub fn repository_session_patch_export_content(
    session_id: u64,
    generation: u64,
    request: NativePatchExportRequest,
) -> NativePatchExportContentResult {
    gitlama_application::application::patch::repository_session_patch_export_content(
        session_id, generation, request,
    )
}

/// The bytes of a built patch from `offset`, at most one page.
#[must_use]
pub fn repository_session_patch_export_content_page(
    session_id: u64,
    generation: u64,
    token: u64,
    offset: u64,
) -> NativePatchExportContentPage {
    gitlama_application::application::patch::repository_session_patch_export_content_page(
        session_id, generation, token, offset,
    )
}

/// Starts the zip snapshot of `commit` under the top folder `prefix`.
#[must_use]
pub fn repository_session_archive_start(
    session_id: u64,
    generation: u64,
    commit: String,
    prefix: String,
) -> NativeArchiveStartResult {
    gitlama_application::application::archive::repository_session_archive_start(
        session_id, generation, commit, prefix,
    )
}

/// The progress or result of a zip snapshot.
#[must_use]
pub fn repository_session_archive_status(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeArchiveStatus {
    gitlama_application::application::archive::repository_session_archive_status(
        session_id, generation, token,
    )
}

/// One page of a finished zip snapshot from `offset`; empty at the end.
#[must_use]
pub fn repository_session_archive_page(
    session_id: u64,
    generation: u64,
    token: u64,
    offset: u64,
) -> NativeArchivePage {
    gitlama_application::application::archive::repository_session_archive_page(
        session_id, generation, token, offset,
    )
}

/// Stops and deletes a zip snapshot.
#[must_use]
pub fn repository_session_archive_release(session_id: u64, generation: u64, token: u64) -> bool {
    gitlama_application::application::archive::repository_session_archive_release(
        session_id, generation, token,
    )
}

/// Starts writing a zip snapshot to `destination` on this computer.
#[must_use]
pub fn archive_file_begin(destination: String) -> Option<u64> {
    gitlama_application::application::archive::archive_file_begin(destination)
}

/// Appends one page to a zip snapshot write.
#[must_use]
pub fn archive_file_append(token: u64, bytes: Vec<u8>) -> bool {
    gitlama_application::application::archive::archive_file_append(token, bytes)
}

/// Completes a zip snapshot write, replacing the destination.
#[must_use]
pub fn archive_file_commit(token: u64) -> bool {
    gitlama_application::application::archive::archive_file_commit(token)
}

/// Abandons a zip snapshot write.
pub fn archive_file_abort(token: u64) {
    gitlama_application::application::archive::archive_file_abort(token);
}

/// Prepares saving patch `bytes` built on another computer as `filename` in the local
/// `destination_directory`, with the destination checks of a local export.
#[must_use]
pub fn patch_export_save_preview(
    destination_directory: String,
    filename: String,
    bytes: Vec<u8>,
    overwrite: bool,
) -> NativePatchSavePreviewResult {
    gitlama_application::application::patch::patch_export_save_preview(
        destination_directory,
        filename,
        bytes,
        overwrite,
    )
}

/// Writes a prepared patch save once; a destination that changed since is stale.
#[must_use]
pub fn patch_export_save_execute(token: u64) -> NativePatchExportExecutionResult {
    gitlama_application::application::patch::patch_export_save_execute(token)
}

/// Parses and checks a patch and freezes the affected paths.
#[must_use]
pub fn repository_session_patch_apply_preview(
    session_id: u64,
    generation: u64,
    patch_path: String,
) -> NativePatchApplyPreviewResult {
    gitlama_application::application::patch::repository_session_patch_apply_preview(
        session_id, generation, patch_path,
    )
}

#[must_use]
pub fn repository_session_patch_apply_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativePatchApplyExecutionResult {
    gitlama_application::application::patch::repository_session_patch_apply_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_image_diff(
    session_id: u64,
    generation: u64,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Vec<u8>,
    new_path: Vec<u8>,
    byte_limit: u32,
) -> NativeImageDiffResult {
    gitlama_application::application::diff::repository_session_image_diff(
        session_id,
        generation,
        old_revision,
        new_revision,
        old_path,
        new_path,
        byte_limit,
    )
}

/// Decodes the image sides of one staged or unstaged working-tree change.
///
/// A missing path loads no image for that side, so additions and deletions
/// compare against an empty side.
#[must_use]
pub fn repository_session_working_image_diff(
    session_id: u64,
    generation: u64,
    side: NativeStagingSide,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
) -> NativeImageDiffResult {
    gitlama_application::application::diff::repository_session_working_image_diff(
        session_id, generation, side, old_path, new_path, byte_limit,
    )
}

/// Keeps the stored bytes of both sides of a file changed between commits for another computer
/// that decodes, compares or renders them itself;
/// [`repository_session_change_source_page`] returns them. A missing path has no side.
#[must_use]
pub fn repository_session_change_source(
    session_id: u64,
    generation: u64,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
) -> NativeChangeSourceResult {
    gitlama_application::application::diff::repository_session_change_source(
        session_id,
        generation,
        old_revision,
        new_revision,
        old_path,
        new_path,
        byte_limit,
    )
}

/// Keeps the stored bytes of both sides of one staged or unstaged working-tree change for
/// another computer.
#[must_use]
pub fn repository_session_working_change_source(
    session_id: u64,
    generation: u64,
    side: NativeStagingSide,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
) -> NativeChangeSourceResult {
    gitlama_application::application::diff::repository_session_working_change_source(
        session_id, generation, side, old_path, new_path, byte_limit,
    )
}

/// Bytes of a kept change side from `offset`, at most one page.
#[must_use]
pub fn repository_session_change_source_page(
    session_id: u64,
    generation: u64,
    token: u64,
    new_side: bool,
    offset: u64,
) -> NativeChangeSourcePage {
    gitlama_application::application::diff::repository_session_change_source_page(
        session_id, generation, token, new_side, offset,
    )
}

/// Decodes image bytes read from a repository on another computer, as an image diff of a local
/// repository decodes its own.
#[must_use]
pub fn image_decode_pair(old: Option<Vec<u8>>, new: Option<Vec<u8>>) -> NativeImageDiffResult {
    gitlama_application::application::diff::image_decode_pair(old, new)
}

#[must_use]
pub fn repository_session_diff_renderer_preview(
    session_id: u64,
    generation: u64,
    request_id: u64,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    gitlama_application::application::diff_renderers::repository_session_diff_renderer_preview(
        session_id, generation, request_id, definition,
    )
}

#[must_use]
pub fn repository_session_diff_renderer_validate(
    session_id: u64,
    generation: u64,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    gitlama_application::application::diff_renderers::repository_session_diff_renderer_validate(
        session_id, generation, definition,
    )
}

#[must_use]
pub fn repository_session_diff_renderer_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiffRendererResult {
    gitlama_application::application::diff_renderers::repository_session_diff_renderer_execute(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_diff_renderer_poll(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiffRendererResult {
    gitlama_application::application::diff_renderers::repository_session_diff_renderer_poll(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_diff_renderer_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::diff_renderers::repository_session_diff_renderer_cancel(
        session_id, generation, token,
    )
}

/// The diff a renderer would read, for a repository on another computer whose renderer runs on
/// this one. A diff above the renderer's input limit is refused as too large.
#[must_use]
pub fn repository_session_diff_renderer_input(
    session_id: u64,
    generation: u64,
    request_id: u64,
) -> NativeDiffRendererInputResult {
    gitlama_application::application::diff_renderers::repository_session_diff_renderer_input(
        session_id, generation, request_id,
    )
}

/// Previews a renderer on this computer for a diff read from a repository on another computer.
#[must_use]
pub fn diff_renderer_detached_preview(
    input: Vec<u8>,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    gitlama_application::application::diff_renderers::diff_renderer_detached_preview(
        input, definition,
    )
}

#[must_use]
pub fn diff_renderer_detached_validate(
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    gitlama_application::application::diff_renderers::diff_renderer_detached_validate(definition)
}

#[must_use]
pub fn diff_renderer_detached_execute(token: u64) -> NativeDiffRendererResult {
    gitlama_application::application::diff_renderers::diff_renderer_detached_execute(token)
}

#[must_use]
pub fn diff_renderer_detached_poll(token: u64) -> NativeDiffRendererResult {
    gitlama_application::application::diff_renderers::diff_renderer_detached_poll(token)
}

#[must_use]
pub fn diff_renderer_detached_cancel(token: u64) -> bool {
    gitlama_application::application::diff_renderers::diff_renderer_detached_cancel(token)
}

/// Previews a diff tool on this computer for two versions of a file read from a repository on
/// another computer.
#[must_use]
pub fn external_diff_detached_preview(
    old: Vec<u8>,
    new: Vec<u8>,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    gitlama_application::application::diff_renderers::external_diff_detached_preview(
        old, new, configured,
    )
}

#[must_use]
pub fn external_diff_detached_execute(
    token: u64,
    confirmed: bool,
) -> NativeIntegrationExecutionResult {
    gitlama_application::application::diff_renderers::external_diff_detached_execute(
        token, confirmed,
    )
}

#[must_use]
pub fn external_diff_detached_cancel(token: u64) -> bool {
    gitlama_application::application::diff_renderers::external_diff_detached_cancel(token)
}

#[must_use]
pub fn repository_session_events(
    session_id: u64,
    generation: u64,
    maximum_events: u32,
) -> NativeRepositoryEventsResult {
    gitlama_application::application::session::repository_session_events(
        session_id,
        generation,
        maximum_events,
    )
}

#[must_use]
pub fn repository_session_refresh(
    session_id: u64,
    generation: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::session::repository_session_refresh(session_id, generation)
}

#[must_use]
pub fn repository_session_inspect_index_lock(
    session_id: u64,
    generation: u64,
) -> NativeIndexLockInspectionResult {
    gitlama_application::application::index_lock::repository_session_inspect_index_lock(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_remove_index_lock(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeIndexLockRemovalResult {
    gitlama_application::application::index_lock::repository_session_remove_index_lock(
        session_id, generation, token,
    )
}

#[must_use]
pub fn repository_session_delete_tracking_refs(
    session_id: u64,
    generation: u64,
    references: Vec<String>,
) -> NativeTransferExecutionResult {
    gitlama_application::application::transfer::repository_session_delete_tracking_refs(
        session_id, generation, references,
    )
}

#[must_use]
pub fn repository_session_inspect_locks(
    session_id: u64,
    generation: u64,
) -> NativeRepositoryLockInspectionResult {
    gitlama_application::application::repository_locks::repository_session_inspect_locks(
        session_id, generation,
    )
}

#[must_use]
pub fn repository_session_remove_lock(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeIndexLockRemovalResult {
    gitlama_application::application::repository_locks::repository_session_remove_lock(
        session_id, generation, token,
    )
}

/// Reads the repository's status accelerators and the duration of its last status scan.
#[must_use]
pub fn repository_session_status_acceleration(
    session_id: u64,
    generation: u64,
) -> NativeStatusAccelerationResult {
    gitlama_application::application::status_acceleration::repository_session_status_acceleration(
        session_id, generation,
    )
}

/// Enables the accelerators the repository lacks in its local Git configuration.
#[must_use]
pub fn repository_session_enable_status_acceleration(
    session_id: u64,
    generation: u64,
) -> NativeStatusAccelerationResult {
    gitlama_application::application::status_acceleration::repository_session_enable_status_acceleration(
        session_id, generation,
    )
}

#[must_use]
pub fn application_operation_center(maximum_entries: u32) -> NativeOperationCenterResult {
    gitlama_application::application::operation_center::application_operation_center(
        maximum_entries,
    )
}

#[must_use]
pub fn application_operation_dismiss(
    session_id: u64,
    generation: u64,
    activity_id: u64,
) -> NativeRepositoryCommandResult {
    gitlama_application::application::operation_center::application_operation_dismiss(
        session_id,
        generation,
        activity_id,
    )
}

#[must_use]
pub fn application_operation_dismiss_all() -> NativeRepositoryCommandResult {
    gitlama_application::application::operation_center::application_operation_dismiss_all()
}

#[must_use]
pub fn repository_session_close(session_id: u64, generation: u64) -> NativeRepositoryCommandResult {
    gitlama_application::application::session::repository_session_close(session_id, generation)
}

/// Drops the native StreamSink before Dart cancels its stream subscription.
pub fn detach_native_diagnostics() {
    devmil_logging::set_detailed(false);
    devmil_logging::install_hook(None);
}
/// Installs the Dart diagnostic availability hook. At most one notification is
/// outstanding until the bounded native history is drained.
pub fn watch_native_diagnostics(sink: crate::frb_generated::StreamSink<()>) {
    devmil_logging::install_hook(Some(std::sync::Arc::new(move || sink.add(()).is_ok())));
    devmil_logging::record("native.hook_ready", "INFO", &[], false);
}
pub fn drain_native_diagnostics() -> Vec<String> {
    devmil_logging::drain()
}
pub fn configure_native_diagnostics(detailed: bool, clear: bool) {
    devmil_logging::set_detailed(detailed);
    if clear {
        devmil_logging::clear();
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::wildcard_imports)]

    use crate::api::core_info;

    use devmil_git::version::GitVersion;

    #[test]
    fn handshake_matches_the_required_git_floor() {
        let info = core_info();
        assert_eq!(info.protocol_version, 1);
        assert_eq!(
            GitVersion::new(
                info.minimum_git_major,
                info.minimum_git_minor,
                info.minimum_git_patch
            ),
            GitVersion::parse(b"git version 2.39.0").unwrap()
        );
    }
}
