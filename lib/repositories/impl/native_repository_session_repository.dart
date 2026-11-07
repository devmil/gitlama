import 'dart:convert';
import 'dart:typed_data';

import '../../models/activity.dart';
import '../../models/advanced_rebase.dart';
import '../../models/commit.dart';
import '../../models/conflict.dart';
import '../../models/clone_attempt.dart';
import '../../models/discard.dart';
import '../../models/index_lock.dart';
import '../../models/repository_lock.dart';
import '../../models/diff.dart';
import '../../models/diff_renderer.dart';
import '../../models/diff_syntax.dart';
import '../../models/history.dart';
import '../../models/history_mutation.dart';
import '../../models/integrations.dart';
import '../../models/inspection.dart';
import '../../models/patch.dart';
import '../../models/power_tools.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_state.dart';
import '../../models/status_acceleration.dart';
import '../../models/ref_mutation.dart';
import '../../models/repository_extensions.dart';
import '../../models/rebase.dart';
import '../../models/named_snapshot.dart';
import '../../models/settings.dart';
import '../../models/stash.dart';
import '../../models/transfer.dart';
import '../../rust/api.dart' as rust_api;
import '../../rust/third_party/gitlama_contract/archive.dart' as native_archive;
import '../../models/commit_archive.dart';
import '../../rust/third_party/gitlama_contract/activity.dart'
    as native_activity;
import '../../rust/third_party/gitlama_contract/advanced_rebase.dart'
    as native_advanced;
import '../../rust/third_party/gitlama_contract/dto.dart' as native;
import '../../rust/third_party/gitlama_contract/diff.dart' as native_diff;
import '../../rust/third_party/gitlama_contract/conflict.dart'
    as native_conflict;
import '../../rust/third_party/gitlama_contract/diff_renderer.dart'
    as native_renderer;
import '../../rust/third_party/gitlama_contract/extensions.dart'
    as native_extensions;
import '../../rust/third_party/gitlama_contract/history_operation.dart'
    as native_history_operation;
import '../../rust/third_party/gitlama_contract/image_decoder.dart'
    as native_image;
import '../../rust/third_party/gitlama_contract/integrations.dart'
    as native_integrations;
import '../../rust/third_party/gitlama_contract/power_tools.dart'
    as native_power;
import '../../rust/third_party/gitlama_contract/rebase_operation.dart'
    as native_rebase;
import '../../rust/third_party/gitlama_contract/named_snapshot.dart'
    as native_snapshot;
import '../../rust/third_party/gitlama_contract/stash.dart' as native_stash;
import '../../rust/third_party/gitlama_contract/domain/path_identity.dart'
    as native_storage;
import '../../rust/third_party/gitlama_contract/transfer.dart'
    as native_transfer;
import '../repository_session_repository.dart';
import 'native_mappers.dart';
import 'repository_session_calls.g.dart';
import 'native_enum_mappers.g.dart';

final class NativeRepositorySessionRepository
    implements CompleteSessionBackend, ChangeSourceRepositorySessionRepository {
  NativeRepositorySessionRepository([
    this._calls = const FfiRepositorySessionCalls(),
  ]) : _authority = null,
       _onOpened = null;

  /// The sessions of one remote connection over its wire [calls]. Sessions
  /// opened here are remote sessions, and every absolute path they report
  /// carries [authority], so a remote path can never satisfy a local path
  /// boundary. [onOpened] learns the host path and native id of each opened
  /// session, so the connection can remember its workspace binding.
  NativeRepositorySessionRepository.remote(
    this._calls, {
    required RemoteAuthority this._authority,
    this._onOpened,
  });

  /// The bridge this adapter maps. A remote session substitutes the wire
  /// implementation, so local and remote sessions share every projection.
  final RepositorySessionCalls _calls;

  /// The connection whose sessions this adapter serves; null for this
  /// computer.
  final RemoteAuthority? _authority;
  final void Function(List<int> path, BigInt sessionId)? _onOpened;

  /// [path] as this adapter reports it: marked with the connection's
  /// authority for a remote adapter.
  NativePathIdentity _path(NativePathIdentity path) => switch (_authority) {
    final authority? => NativePathIdentity(
      platform: path.platform,
      units: path.units,
      remote: authority,
    ),
    null => path,
  };

  NativePathIdentity _pathFromNative(native_storage.NativePathIdentity path) =>
      _path(pathIdentityFromNative(path));

  /// [snapshot] with every absolute identity marked as this adapter's.
  RepositorySnapshot _snapshot(native.NativeRepositorySnapshot snapshot) {
    final mapped = repositorySnapshotFromNative(snapshot);
    final identity = mapped.identity;
    if (_authority == null || identity == null) return mapped;
    return mapped.copyWith(
      identity: RepositoryIdentity(
        commonGitDir: _path(identity.commonGitDir),
        worktreeRoot: _path(identity.worktreeRoot),
        gitDir: _path(identity.gitDir),
        kind: identity.kind,
        headKind: identity.headKind,
        headReference: identity.headReference,
        headObjectId: identity.headObjectId,
        gitMajor: identity.gitMajor,
        gitMinor: identity.gitMinor,
        gitPatch: identity.gitPatch,
      ),
    );
  }

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  open(String path, int generation) async {
    final result = await _calls.repositorySessionOpen(
      path: path,
      generation: BigInt.from(generation),
    );
    return _opened(result);
  }

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) async {
    // A remote workspace opens through its own helper connection, never as
    // a local path nor on another connection.
    if (identity.remote != _authority) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOptions),
      );
    }
    // The helper receives the bare host path; the authority stays here.
    final result = await _calls.repositorySessionOpenIdentity(
      identity: pathIdentityToNative(
        NativePathIdentity(platform: identity.platform, units: identity.units),
      ),
      generation: BigInt.from(generation),
    );
    final opened = _opened(result);
    _onOpened?.call(identity.units, opened.identity.nativeId);
    return opened;
  }

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  }) async {
    final result = await _calls.repositoryInitialize(
      path: path,
      initialBranch: initialBranch,
      bare: bare,
      generation: BigInt.from(generation),
    );
    return _opened(result);
  }

  ({RepositorySessionIdentity identity, RepositorySnapshot snapshot}) _opened(
    native.NativeRepositoryOpenResult result,
  ) {
    throwRepositoryFailure(result.failure);
    final session = result.session;
    if (session == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    final mapped = repositorySessionFromNative(session);
    if (_authority == null) return mapped;
    return (
      identity: RepositorySessionIdentity(
        nativeId: mapped.identity.nativeId,
        generation: mapped.identity.generation,
        backend: RepositoryBackendKind.remote,
      ),
      snapshot: _snapshot(session.snapshot),
    );
  }

  @override
  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  }) async {
    final result = await _calls.repositorySessionEvents(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      maximumEvents: maximumEvents,
    );
    throwRepositoryFailure(result.failure);
    return [for (final event in result.events) _event(event)];
  }

  @override
  Future<void> refresh(RepositorySessionIdentity identity) async {
    final result = await _calls.repositorySessionRefresh(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    throwRepositoryFailure(result.failure);
    if (!result.accepted) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.closed),
      );
    }
  }

  @override
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) async {
    final result = await _calls.repositorySessionActivity(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      maximumRecords: maximumRecords,
    );
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return ActivityPage(
      records: [for (final record in page.records) _activityRecord(record)],
      evictedThroughId: page.evictedThroughId,
    );
  }

  @override
  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) async {
    final result = await _calls.repositorySessionActivityRecord(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      activityId: activityId,
    );
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return ActivityPage(
      records: [for (final record in page.records) _activityRecord(record)],
      evictedThroughId: page.evictedThroughId,
    );
  }

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = ContractLimits.pageRows,
  }) async => _historyPage(
    await _calls.repositorySessionHistoryLoad(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      complete: complete,
      maximumRows: maximumRows,
      otherRefs: otherRefs,
    ),
  );

  @override
  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) async => _historyPage(
    await _calls.repositorySessionHistoryPage(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    ),
  );

  @override
  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = ContractLimits.pageRows,
  }) async => _historyPage(
    await _calls.repositorySessionHistoryComplete(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      maximumRows: maximumRows,
    ),
  );

  @override
  Future<HistoryPage> selectHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String? objectId,
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) async => _historyPage(
    await _calls.repositorySessionHistorySelect(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      options: native.NativeHistorySelectionOptions(
        objectId: objectId,
        toggle: toggle,
        reveal: reveal,
        focus: focus,
        offset: BigInt.from(offset),
        maximumRows: maximumRows,
      ),
    ),
  );

  @override
  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  }) async => _historyPage(
    await _calls.repositorySessionHistoryQuery(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      options: native.NativeHistoryQueryOptions(
        text: query.text,
        searchHash: query.searchHash,
        searchMessage: query.searchMessage,
        searchAuthor: query.searchAuthor,
        searchPath: query.searchPath,
        offset: BigInt.from(offset),
        maximumRows: maximumRows,
      ),
    ),
  );

  @override
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  }) async {
    final result = await _calls.repositorySessionHistoryBranchFilter(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      references: [
        for (final reference in filter.references)
          Uint8List.fromList(utf8.encode(reference)),
      ],
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    );
    throwRepositoryFailure(result.failure);
    return result.page == null ? null : _historyPage(result);
  }

  @override
  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  }) async => _historyPage(
    await _calls.repositorySessionHistoryCollapse(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      objectId: objectId,
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    ),
  );

  @override
  Future<ReflogPage> reflog(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximumRows = 256,
  }) async {
    final result = await _calls.repositorySessionReflog(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    );
    return ReflogPage(
      entries: [
        for (final entry in result.page.entries)
          ReflogEntry(
            id: entry.id,
            reference: List.unmodifiable(entry.reference),
            commit: entry.commit,
            recordedAtUnixSeconds: entry.recordedAtUnixSeconds.toInt(),
            timezone: List.unmodifiable(entry.timezone),
            summary: List.unmodifiable(entry.summary),
            actorName: List.unmodifiable(entry.actorName),
            actorEmail: List.unmodifiable(entry.actorEmail),
            actions: {for (final action in entry.actions) action.toModel()},
          ),
      ],
      nextOffset: result.page.nextOffset?.toInt(),
      activityId: result.page.activityId,
      retainedAfterFailure: result.page.retainedAfterFailure,
      failureCode: repositoryFailureFromNative(result.failure)?.code.name,
    );
  }

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) async {
    final result = await _calls.repositorySessionCommitInspection(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      commit: commit,
      firstParent: firstParent,
    );
    throwRepositoryFailure(result.failure);
    final value = result.inspection;
    if (value == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return CommitInspection(
      detail: CommitIdentityDetail(
        commit: value.detail.commit,
        tree: value.detail.tree,
        parents: List.unmodifiable(value.detail.parents),
        author: List.unmodifiable(value.detail.author),
        avatarHash: value.detail.avatarHash,
        authorTime: value.detail.authorTime.toInt(),
        authorTimezone: List.unmodifiable(value.detail.authorTimezone),
        committer: List.unmodifiable(value.detail.committer),
        committerTime: value.detail.committerTime.toInt(),
        committerTimezone: List.unmodifiable(value.detail.committerTimezone),
        message: List.unmodifiable(value.detail.message),
      ),
      files: [
        for (final file in value.files)
          CommitFileChange(
            oldMode: file.oldMode,
            newMode: file.newMode,
            oldObjectId: file.oldObjectId,
            newObjectId: file.newObjectId,
            kind: file.kind.toModel(),
            similarity: file.similarity,
            oldPath: List.unmodifiable(file.oldPath),
            newPath: List.unmodifiable(file.newPath),
          ),
      ],
    );
  }

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) async {
    final result = await _calls.repositorySessionTree(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      commit: commit,
      directory: directory == null ? null : Uint8List.fromList(directory),
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    );
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return CommitTreePage(
      commit: page.commit,
      directory: page.directory == null
          ? null
          : List.unmodifiable(page.directory!),
      entries: [
        for (final entry in page.entries)
          CommitTreeEntry(
            stableId: entry.stableId,
            path: List.unmodifiable(entry.path),
            objectId: entry.objectId,
            kind: entry.kind.toModel(),
            mode: entry.mode,
            size: entry.size?.toInt(),
          ),
      ],
      nextOffset: page.nextOffset?.toInt(),
    );
  }

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) async {
    final result = await _calls.repositorySessionCommitFileContent(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      commit: commit,
      path: Uint8List.fromList(path),
    );
    throwRepositoryFailure(result.failure);
    final bytes = result.bytes;
    if (bytes == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return List.unmodifiable(bytes);
  }

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) async {
    final result = await _calls.repositorySessionPathHistory(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      options: native.NativePathHistoryOptions(
        revision: revision,
        path: Uint8List.fromList(path),
        directory: directory,
        offset: BigInt.from(offset),
        maximumRows: maximumRows,
        renameHopsBefore: BigInt.from(renameHopsBefore),
      ),
    );
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return PathHistoryPage(
      entries: [
        for (final entry in page.entries)
          PathHistoryEntry(
            stableId: entry.stableId,
            commit: entry.commit,
            author: List.unmodifiable(entry.author),
            authorTime: entry.authorTime.toInt(),
            summary: List.unmodifiable(entry.summary),
            path: List.unmodifiable(entry.path),
            oldPath: entry.oldPath == null
                ? null
                : List.unmodifiable(entry.oldPath!),
          ),
      ],
      nextOffset: page.nextOffset?.toInt(),
      renameHops: page.renameHops.toInt(),
      incomplete: page.incomplete,
    );
  }

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) async {
    final result = await _calls.repositorySessionRangeHistory(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      revision: revision,
      path: Uint8List.fromList(path),
      firstLine: firstLine,
      lastLine: lastLine,
      maximumRows: maximumRows,
    );
    throwRepositoryFailure(result.failure);
    return RangeHistoryResult(
      entries: [
        for (final entry in result.entries)
          RangeHistoryEntry(
            stableId: entry.stableId,
            commit: entry.commit,
            author: List.unmodifiable(entry.author),
            authorTime: entry.authorTime.toInt(),
            summary: List.unmodifiable(entry.summary),
          ),
      ],
      incomplete: result.incomplete,
    );
  }

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = ContractLimits.pageRows,
  }) async => _blamePage(
    await _calls.repositorySessionBlameLoad(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      options: native.NativeBlameOptions(
        revision: revision,
        path: Uint8List.fromList(path),
        firstLine: firstLine == null ? null : BigInt.from(firstLine),
        lastLine: lastLine == null ? null : BigInt.from(lastLine),
        detectMoves: detectMoves,
        detectCopies: detectCopies,
        maximumRows: maximumRows,
      ),
    ),
  );

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) async => _blamePage(
    await _calls.repositorySessionBlamePage(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    ),
  );

  BlamePage _blamePage(native.NativeBlameResult result) {
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return BlamePage(
      requestId: page.requestId,
      revision: page.revision,
      path: List.unmodifiable(page.path),
      totalRows: page.totalRows.toInt(),
      offset: page.offset.toInt(),
      rows: [
        for (final row in page.rows)
          BlameRow(
            stableId: row.stableId,
            finalLine: row.finalLine.toInt(),
            originalLine: row.originalLine.toInt(),
            content: List.unmodifiable(row.content),
            commit: row.commit,
            author: List.unmodifiable(row.author),
            authorTime: row.authorTime.toInt(),
            summary: List.unmodifiable(row.summary),
            originalPath: List.unmodifiable(row.originalPath),
            boundary: row.boundary,
            spanFirstLine: row.spanFirstLine.toInt(),
            spanLastLine: row.spanLastLine.toInt(),
          ),
      ],
    );
  }

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) async {
    final result = await _calls.repositorySessionRestorePreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      commit: commit,
      path: Uint8List.fromList(path),
      byteLimit: byteLimit,
    );
    throwRepositoryFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return RestorePreview(
      token: preview.token,
      commit: preview.commit,
      path: List.unmodifiable(preview.path),
      sourceBytes: List.unmodifiable(preview.sourceBytes),
      currentBytes: preview.currentBytes == null
          ? null
          : List.unmodifiable(preview.currentBytes!),
      expectedHead: preview.expectedHead,
    );
  }

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) async {
    final result = await _calls.repositorySessionRestoreFile(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return RestoreResult(
      state: result.state.toModel(),
      failureCode: repositoryFailureFromNative(result.failure)?.code.name,
    );
  }

  HistoryPage _historyPage(native.NativeHistoryResult result) {
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return HistoryPage(
      requestId: page.requestId,
      complete: page.topologyComplete,
      totalRows: page.totalRows.toInt(),
      offset: page.offset.toInt(),
      rows: [
        for (final row in page.rows)
          HistoryTopologyRow(
            objectId: row.objectId,
            parents: List.unmodifiable(row.parents),
            refs: List.unmodifiable(row.refs),
            refCount: row.refCount,
            refsTruncated: row.refsTruncated,
            lane: row.lane,
            shape: row.shape.index,
            subject: List.unmodifiable(row.subject),
            author: List.unmodifiable(row.author),
            avatarHash: row.avatarHash,
            authorTime: row.authorTime.toInt(),
            metadataFailure: row.metadataFailure?.toModel(),
            selected: row.selected,
            current: row.current,
            lit: row.lit,
            compared: row.compared,
            wipChangedFiles: row.wipChangedFiles,
            wipStagedFiles: row.wipStagedFiles,
          ),
      ],
      segments: [
        for (final segment in page.segments)
          HistoryTopologySegment(
            fromRow: segment.fromRow.toInt(),
            toRow: segment.toRow?.toInt(),
            lit: segment.lit,
            fromObjectId: segment.fromObjectId,
            toObjectId: segment.toObjectId,
            parentOrdinal: segment.parentOrdinal,
            fromLane: segment.fromLane,
            toLane: segment.toLane,
            kind: segment.kind.index,
          ),
      ],
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes.toInt(),
      lightingActive: page.lightingActive,
      currentObjectId: page.currentObjectId,
      selectedObjectIds: List.unmodifiable(page.selectedObjectIds),
      focusedObjectId: page.focusedObjectId,
      comparisonOldObjectId: page.comparisonOldObjectId,
      comparisonNewObjectId: page.comparisonNewObjectId,
      revealSequence: page.revealSequence.toInt(),
      revealObjectId: page.revealObjectId,
      revealIndex: page.revealIndex?.toInt(),
      querySequence: page.querySequence.toInt(),
      queryActive: page.queryActive,
      acceptedQuery: page.acceptedQuery,
      branchFilter: page.branchFilter.isEmpty
          ? HistoryBranchFilter.none
          : HistoryBranchFilter(
              page.branchFilter.map(
                (reference) => utf8.decode(reference, allowMalformed: true),
              ),
            ),
      selectedFilteredOut: page.selectedFilteredOut,
      collapsedCommits: page.collapsedCommits.toInt(),
      otherRefs: page.otherRefs,
    );
  }

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = ContractLimits.pageRows,
  }) async => _diffPage(
    await _calls.repositorySessionCommitDiffLoad(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      options: native.NativeCommitDiffOptions(
        commit: commit,
        firstParent: firstParent,
        oldPath: options.oldPath == null
            ? null
            : Uint8List.fromList(options.oldPath!),
        newPath: options.newPath == null
            ? null
            : Uint8List.fromList(options.newPath!),
        contextLines: options.contextLines,
        whitespace: options.whitespace.toNative(),
        layout: options.layout.toNative(),
        maximumRows: maximumRows,
        forceText: options.forceText,
      ),
    ),
  );

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) async => _diffPage(
    await _calls.repositorySessionDiffPage(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    ),
  );

  @override
  Future<DiffPage> workingDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = ContractLimits.pageRows,
  }) async => _diffPage(
    await _calls.repositorySessionWorkingDiffLoad(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      options: native.NativeWorkingDiffOptions(
        side: side.toNative(),
        oldPath: oldPath == null ? null : Uint8List.fromList(oldPath),
        newPath: newPath == null ? null : Uint8List.fromList(newPath),
        contextLines: contextLines,
        whitespace: whitespace.toNative(),
        layout: layout.toNative(),
        maximumRows: maximumRows,
        forceText: forceText,
      ),
    ),
  );

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) async => _diffPage(
    await _calls.repositorySessionWorkingDiffPage(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      offset: BigInt.from(offset),
      maximumRows: maximumRows,
    ),
  );

  @override
  Future<StagingPhase?> stagingPhase(
    RepositorySessionIdentity identity,
  ) async => (await _calls.repositorySessionStagingPhase(
    sessionId: identity.nativeId,
    generation: BigInt.from(identity.generation),
  ))?.toModel();

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) async {
    final result = await _calls.repositorySessionStagingExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native.NativeStagingRequest(
        requestId: request.requestId,
        side: request.side.toNative(),
        scope: request.scope.toNative(),
        paths: [for (final path in request.paths) Uint8List.fromList(path)],
        rowIds: request.rowIds,
      ),
    );
    if (result.failure case final failure?) {
      if (result.state != native.NativeStagingExecutionState.failed) {
        throwRepositoryFailure(failure);
      }
    }
    return StagingExecutionResult(
      state: result.state.toModel(),
      diagnostic: result.diagnostic == null
          ? null
          : StagingDiagnostic(
              code: result.diagnostic!.code.toModel(),
              activityId: result.diagnostic!.activityId,
              exitCode: result.diagnostic!.exitCode,
              gitVersion: result.diagnostic!.gitVersion,
            ),
    );
  }

  @override
  Future<CommitTools> commitTools(RepositorySessionIdentity identity) async {
    final result = await _calls.repositorySessionCommitTools(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    throwRepositoryFailure(result.failure);
    final tools = result.tools;
    if (tools == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return CommitTools(
      recent: [
        for (final message in tools.recent)
          RecentCommitMessage(
            objectId: message.objectId,
            subject: message.subject,
            description: message.description,
          ),
      ],
      template: tools.template,
    );
  }

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) async {
    final result = await _calls.repositorySessionCommitPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native.NativeCommitRequest(
        subject: request.subject,
        description: request.description,
        coauthors: request.coauthors,
        author: request.author,
        amend: request.amend,
        skipHooks: request.skipHooks,
        signing: request.signing.toNative(),
        signOff: request.signOff,
      ),
    );
    throwRepositoryFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return CommitPreview(
      token: preview.token,
      warnings: [for (final warning in preview.warnings) warning.toModel()],
      arguments: List.unmodifiable(preview.arguments),
    );
  }

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionCommitExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    if (result.failure case final failure?) {
      if (result.state != native.NativeCommitExecutionState.failed) {
        throwRepositoryFailure(failure);
      }
    }
    return CommitExecutionResult(
      state: result.state.toModel(),
      commit: result.commit,
      failureKind: result.failureKind?.toModel(),
      exitCode: result.exitCode,
      output: List.unmodifiable(result.output),
    );
  }

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) async {
    final result = await _calls.repositorySessionDiscardPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native.NativeDiscardRequest(
        kind: request.kind.toNative(),
        scope: request.scope.toNative(),
        workingDiffRequestId: request.workingDiffRequestId,
        paths: [for (final path in request.paths) Uint8List.fromList(path)],
        rowIds: request.rowIds,
      ),
    );
    throwRepositoryFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return DiscardPreview(
      token: preview.token,
      kind: preview.kind.toModel(),
      fileCount: preview.fileCount.toInt(),
      arguments: List.unmodifiable(preview.arguments),
    );
  }

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionDiscardExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    if (result.failure case final failure?) {
      if (result.state != native.NativeDiscardExecutionState.failed) {
        throwRepositoryFailure(failure);
      }
    }
    return DiscardExecutionResult(state: result.state.toModel());
  }

  @override
  Future<PatchExportPreview> previewPatchExport(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async {
    final result = await _calls.repositorySessionPatchExportPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: _nativePatchExportRequest(request),
    );
    throwRepositoryFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return PatchExportPreview(
      token: preview.token,
      scope: preview.scope.toModel(),
      format: preview.format.toModel(),
      filename: preview.filename,
      destination: preview.destination,
      byteCount: preview.byteCount.toInt(),
      requiresOverwrite: preview.requiresOverwrite,
    );
  }

  native.NativePatchExportRequest _nativePatchExportRequest(
    PatchExportRequest request,
  ) => native.NativePatchExportRequest(
    workingDiffRequestId: request.workingDiffRequestId,
    rowIds: request.rowIds,
    selectedSide: request.selectedSide?.toNative(),
    selectedPaths: [
      for (final path in request.selectedPaths) Uint8List.fromList(path),
    ],
    focusedSide: request.focusedSide?.toNative(),
    comparisonOld: request.comparisonOld,
    comparisonNew: request.comparisonNew,
    rangeCommits: request.rangeCommits,
    commit: request.commit,
    historyPaths: [
      for (final path in request.historyPaths) Uint8List.fromList(path),
    ],
    workspaceDefault: request.workspaceDefault,
    destinationDirectory: request.destinationDirectory,
    overwrite: request.overwrite,
  );

  @override
  Future<PatchExportContent> patchExportContent(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async {
    final generation = BigInt.from(identity.generation);
    final result = await _calls.repositorySessionPatchExportContent(
      sessionId: identity.nativeId,
      generation: generation,
      request: _nativePatchExportRequest(request),
    );
    throwRepositoryFailure(result.failure);
    final content = result.content;
    if (content == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    final total = content.totalBytes.toInt();
    final bytes = BytesBuilder(copy: false)..add(content.first);
    while (bytes.length < total) {
      final page = await _calls.repositorySessionPatchExportContentPage(
        sessionId: identity.nativeId,
        generation: generation,
        token: content.token,
        offset: BigInt.from(bytes.length),
      );
      throwRepositoryFailure(page.failure);
      // A page that adds nothing would never finish.
      if (page.bytes.isEmpty) {
        throw const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.invalidOutput),
        );
      }
      bytes.add(page.bytes);
    }
    if (bytes.length != total) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return PatchExportContent(
      scope: content.scope.toModel(),
      format: content.format.toModel(),
      filename: content.filename,
      bytes: bytes.takeBytes(),
    );
  }

  @override
  Future<PatchExportPreview> previewPatchSave(
    PatchExportContent content, {
    required String destinationDirectory,
    required bool overwrite,
  }) async {
    final result = await _calls.patchExportSavePreview(
      destinationDirectory: destinationDirectory,
      filename: content.filename,
      bytes: Uint8List.fromList(content.bytes),
      overwrite: overwrite,
    );
    throwRepositoryFailure(result.failure);
    final destination = result.destination;
    if (destination == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return PatchExportPreview(
      token: result.token,
      scope: content.scope,
      format: content.format,
      filename: content.filename,
      destination: destination,
      byteCount: content.bytes.length,
      requiresOverwrite: result.requiresOverwrite,
    );
  }

  @override
  Future<PatchExportExecutionResult> executePatchSave(BigInt token) async {
    final result = await _calls.patchExportSaveExecute(token: token);
    if (result.failure case final failure?) {
      if (result.state != native.NativePatchExportExecutionState.failed) {
        throwRepositoryFailure(failure);
      }
    }
    return PatchExportExecutionResult(
      state: result.state.toModel(),
      destination: result.destination,
    );
  }

  @override
  Future<PatchExportExecutionResult> executePatchExport(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionPatchExportExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    if (result.failure case final failure?) {
      if (result.state != native.NativePatchExportExecutionState.failed) {
        throwRepositoryFailure(failure);
      }
    }
    return PatchExportExecutionResult(
      state: result.state.toModel(),
      destination: result.destination,
    );
  }

  @override
  Future<PatchApplyPreview> previewPatchApply(
    RepositorySessionIdentity identity,
    String patchPath,
  ) async {
    final result = await _calls.repositorySessionPatchApplyPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      patchPath: patchPath,
    );
    throwRepositoryFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return PatchApplyPreview(
      token: preview.token,
      paths: [for (final path in preview.paths) List.unmodifiable(path)],
      binary: preview.binary,
      arguments: List.unmodifiable(preview.arguments),
    );
  }

  @override
  Future<PatchApplyExecutionResult> executePatchApply(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionPatchApplyExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    if (result.failure case final failure?) {
      if (result.state != native.NativePatchApplyExecutionState.failed) {
        throwRepositoryFailure(failure);
      }
    }
    return PatchApplyExecutionResult(state: result.state.toModel());
  }

  @override
  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) async {
    final result = await _calls.repositorySessionDiffSearch(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      query: Uint8List.fromList(query),
      caseSensitive: caseSensitive,
      maximumMatches: maximumMatches,
    );
    throwRepositoryFailure(result.failure);
    return DiffSearchResult(
      requestId: result.requestId,
      matches: [for (final value in result.matches) value.toInt()],
      totalMatches: result.totalMatches.toInt(),
      truncated: result.truncated,
    );
  }

  @override
  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  }) async {
    final result = await _calls.repositorySessionDiffSelectionPatch(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      working: working,
      rowIds: rowIds,
    );
    throwRepositoryFailure(result.failure);
    return result.patch;
  }

  @override
  Future<List<int>> diffHunks(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumPositions = 10000,
  }) async {
    final result = await _calls.repositorySessionDiffHunks(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      maximumPositions: maximumPositions,
    );
    throwRepositoryFailure(result.failure);
    return [for (final value in result.positions) value.toInt()];
  }

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async {
    final result = await _calls.repositorySessionImageDiff(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      oldRevision: oldRevision,
      newRevision: newRevision,
      oldPath: Uint8List.fromList(oldPath),
      newPath: Uint8List.fromList(newPath),
      byteLimit: byteLimit,
    );
    return _imageDiffContent(result);
  }

  @override
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => _imageDiffContent(
    await _calls.repositorySessionWorkingImageDiff(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      side: side.toNative(),
      oldPath: oldPath == null ? null : Uint8List.fromList(oldPath),
      newPath: newPath == null ? null : Uint8List.fromList(newPath),
      byteLimit: byteLimit,
    ),
  );

  @override
  Future<ChangeSourceBytes> changeSource(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    List<int>? oldPath,
    List<int>? newPath,
    required int byteLimit,
  }) async => _readChangeSource(
    identity,
    await _calls.repositorySessionChangeSource(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      oldRevision: oldRevision,
      newRevision: newRevision,
      oldPath: oldPath == null ? null : Uint8List.fromList(oldPath),
      newPath: newPath == null ? null : Uint8List.fromList(newPath),
      byteLimit: byteLimit,
    ),
  );

  @override
  Future<ChangeSourceBytes> workingChangeSource(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    required int byteLimit,
  }) async => _readChangeSource(
    identity,
    await _calls.repositorySessionWorkingChangeSource(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      side: side.toNative(),
      oldPath: oldPath == null ? null : Uint8List.fromList(oldPath),
      newPath: newPath == null ? null : Uint8List.fromList(newPath),
      byteLimit: byteLimit,
    ),
  );

  /// Reads both kept sides of [source] page by page.
  Future<ChangeSourceBytes> _readChangeSource(
    RepositorySessionIdentity identity,
    native.NativeChangeSourceResult source,
  ) async {
    throwRepositoryFailure(source.failure);
    Future<List<int>?> side(BigInt? total, {required bool newSide}) async {
      if (total == null) return null;
      final bytes = BytesBuilder(copy: false);
      while (bytes.length < total.toInt()) {
        final page = await _calls.repositorySessionChangeSourcePage(
          sessionId: identity.nativeId,
          generation: BigInt.from(identity.generation),
          token: source.token,
          newSide: newSide,
          offset: BigInt.from(bytes.length),
        );
        throwRepositoryFailure(page.failure);
        // A page that adds nothing would never finish.
        if (page.bytes.isEmpty) {
          throw const RepositorySessionException(
            RepositoryFailure(RepositoryFailureCode.invalidOutput),
          );
        }
        bytes.add(page.bytes);
      }
      if (bytes.length != total.toInt()) {
        throw const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.invalidOutput),
        );
      }
      return bytes.takeBytes();
    }

    return ChangeSourceBytes(
      old: await side(source.oldBytes, newSide: false),
      newContent: await side(source.newBytes, newSide: true),
    );
  }

  @override
  Future<List<int>> diffRendererInput(
    RepositorySessionIdentity identity,
    BigInt requestId,
  ) async {
    final result = await _calls.repositorySessionDiffRendererInput(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
    );
    if (result.failure case final failure?) {
      throw DiffRendererException(failure.kind.toModel());
    }
    final input = result.input;
    if (input == null) {
      throw const DiffRendererException(DiffRendererFailureCode.stale);
    }
    return input;
  }

  @override
  Future<ImageDiffContent> decodeImage(ChangeSourceBytes source) async =>
      _imageDiffContent(
        await _calls.imageDecodePair(
          old: source.old == null ? null : Uint8List.fromList(source.old!),
          new_: source.newContent == null
              ? null
              : Uint8List.fromList(source.newContent!),
        ),
      );

  @override
  Future<IntegrationPreview> previewDetachedDiffTool(
    ChangeSourceBytes source,
    IntegrationDefinition definition,
  ) async {
    final result = await _calls.externalDiffDetachedPreview(
      old: Uint8List.fromList(source.old ?? const []),
      new_: Uint8List.fromList(source.newContent ?? const []),
      configured: _integrationDefinitionToNative(definition),
    );
    _throwIntegrationFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const IntegrationException(IntegrationFailureCode.read);
    }
    return _integrationPreview(preview);
  }

  @override
  Future<IntegrationExecutionResult> executeDetachedIntegration(
    BigInt token, {
    required bool confirmed,
  }) async => _integrationExecution(
    await _calls.externalDiffDetachedExecute(
      token: token,
      confirmed: confirmed,
    ),
  );

  @override
  Future<bool> cancelDetachedIntegration(BigInt token) =>
      _calls.externalDiffDetachedCancel(token: token);

  @override
  Future<DiffRendererPreview> validateDetachedDiffRenderer(
    RepositorySessionIdentity source,
    DiffRendererDefinition definition,
  ) async => _rendererPreview(
    source,
    await _calls.diffRendererDetachedValidate(
      definition: _rendererDefinitionToNative(definition),
    ),
  );

  @override
  Future<DiffRendererPreview> previewDetachedDiffRenderer(
    RepositorySessionIdentity source,
    List<int> input,
    DiffRendererDefinition definition,
  ) async => _rendererPreview(
    source,
    await _calls.diffRendererDetachedPreview(
      input: Uint8List.fromList(input),
      definition: _rendererDefinitionToNative(definition),
    ),
  );

  @override
  Future<DiffRendererResult> executeDetachedDiffRenderer(BigInt token) async =>
      _rendererResult(await _calls.diffRendererDetachedExecute(token: token));

  @override
  Future<DiffRendererResult> pollDetachedDiffRenderer(BigInt token) async =>
      _rendererResult(await _calls.diffRendererDetachedPoll(token: token));

  @override
  Future<bool> cancelDetachedDiffRenderer(BigInt token) =>
      _calls.diffRendererDetachedCancel(token: token);

  ImageDiffContent _imageDiffContent(native.NativeImageDiffResult result) {
    throwRepositoryFailure(result.failure);
    DecodedImageContent? image(native_image.NativeDecodedImage? value) =>
        value == null
        ? null
        : DecodedImageContent(
            width: value.width,
            height: value.height,
            rgba: List.unmodifiable(value.rgba),
            encodedBytes: value.encodedBytes.toInt(),
          );
    return ImageDiffContent(
      old: image(result.old),
      newImage: image(result.new_),
      failure: switch (result.decodeFailure) {
        native_image.NativeImageDecodeFailureKind.busy =>
          ImageDecodeFailure.busy,
        native_image.NativeImageDecodeFailureKind.unsupported =>
          ImageDecodeFailure.unsupported,
        native_image.NativeImageDecodeFailureKind.malformed =>
          ImageDecodeFailure.malformed,
        native_image.NativeImageDecodeFailureKind.tooLarge =>
          ImageDecodeFailure.tooLarge,
        native_image.NativeImageDecodeFailureKind.timedOut =>
          ImageDecodeFailure.timedOut,
        native_image.NativeImageDecodeFailureKind.canceled =>
          ImageDecodeFailure.canceled,
        null => null,
      },
    );
  }

  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) async {
    final result = await _calls.repositorySessionRefMutationPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native.NativeRefMutationRequest(
        kind: request.kind.toNative(),
        name: request.name,
        secondName: request.secondName,
        target: request.target,
        message: request.message,
        url: request.url,
        force: request.force,
        resetMode: request.resetMode?.toNative(),
        checkout: request.checkout,
      ),
    );
    throwRepositoryFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return RefMutationPreview(
      token: preview.token,
      kind: preview.kind.toModel(),
      arguments: List.unmodifiable(preview.arguments),
      warnings: [for (final warning in preview.warnings) warning.toModel()],
    );
  }

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionRefMutationExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return RefMutationExecutionResult(state: result.state.toModel());
  }

  @override
  Future<TransferPreview> previewTransfer(
    RepositorySessionIdentity identity,
    TransferRequest request,
  ) async {
    final result = await _calls.repositorySessionTransferPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native_transfer.NativeTransferRequest(
        kind: request.kind.toNative(),
        remote: request.remote,
        branch: request.branch,
        pullStrategy: request.pullStrategy.toNative(),
        allowDirty: request.allowDirty,
        stashBeforePull: request.stashBeforePull,
        forceWithLease: request.forceWithLease,
        setUpstream: request.setUpstream,
        refetch: request.refetch,
        prune: request.prune,
      ),
    );
    final failure = result.failure;
    if (failure != null) {
      throw TransferException(failure.kind.toModel());
    }
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return TransferPreview(
      token: preview.token,
      kind: preview.kind.toModel(),
      remote: preview.remote,
      branch: preview.branch,
      arguments: List.unmodifiable(preview.arguments),
      ahead: preview.ahead,
      behind: preview.behind,
      dirty: preview.dirty,
      expectedRemoteObjectId: preview.expectedRemoteObjectId,
      forceWithLease: preview.forceWithLease,
    );
  }

  @override
  Future<TransferExecutionResult> executeTransfer(
    RepositorySessionIdentity identity,
    BigInt token, {
    TransferCredentials? credentials,
  }) async {
    final result = credentials == null
        ? await _calls.repositorySessionTransferExecute(
            sessionId: identity.nativeId,
            generation: BigInt.from(identity.generation),
            token: token,
          )
        : await _calls.repositorySessionTransferExecuteWithCredentials(
            sessionId: identity.nativeId,
            generation: BigInt.from(identity.generation),
            token: token,
            username: credentials.username,
            password: credentials.password,
            credentialToken: credentials.token,
          );
    return _transferResult(result);
  }

  @override
  Future<TransferExecutionResult> executeBackgroundFetch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => _transferResult(
    await _calls.repositorySessionTransferExecuteBackground(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    ),
  );

  TransferExecutionResult _transferResult(
    native_transfer.NativeTransferExecutionResult result,
  ) => TransferExecutionResult(
    state: result.state.toModel(),
    failure: result.failure?.kind.toModel(),
    diagnosis: switch (result.diagnosis) {
      final diagnosis? => TransferDiagnosis(
        kind: diagnosis.kind.toModel(),
        reference: diagnosis.reference,
        related: List.unmodifiable(diagnosis.related),
      ),
      null => null,
    },
    stash: switch (result.stash) {
      final saved? => PullStashResult(
        objectId: saved.objectId,
        pullCompleted: saved.pullCompleted,
        reapplyCompleted: saved.reapplyCompleted,
        conflicted: saved.conflicted,
      ),
      null => null,
    },
    activityId: result.activityId,
    ahead: result.ahead,
    behind: result.behind,
  );

  @override
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity identity,
    List<String> references,
  ) async => _transferResult(
    await _calls.repositorySessionDeleteTrackingRefs(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      references: references,
    ),
  );

  @override
  Future<bool> cancelTransfer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionTransferCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<HostKeyChallenge> probeTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionTransferProbeHostKey(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    final failure = result.failure;
    if (failure != null) {
      throw CloneException(CloneFailure(failure.kind.toModel()));
    }
    final challenge = result.challenge;
    if (challenge == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return HostKeyChallenge(
      challengeId: challenge.challengeId,
      host: challenge.host,
      port: challenge.port,
      algorithm: challenge.algorithm,
      fingerprint: challenge.fingerprint,
    );
  }

  @override
  Future<void> resolveTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
    HostKeyChallenge challenge, {
    required bool accept,
  }) async {
    final result = await _calls.repositorySessionTransferResolveHostKey(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
      challengeId: challenge.challengeId,
      accept: accept,
    );
    final failure = result.failure;
    if (failure != null) {
      throw CloneException(CloneFailure(failure.kind.toModel()));
    }
  }

  @override
  Future<StashPreview> previewStash(
    RepositorySessionIdentity identity,
    StashRequest request,
  ) async {
    final result = await _calls.repositorySessionStashPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native_stash.NativeStashRequest(
        kind: request.kind.toNative(),
        message: request.message,
        selector: request.selector,
        objectId: request.objectId,
        paths: [for (final path in request.paths) Uint8List.fromList(path)],
        includeUntracked: request.includeUntracked,
        keepIndex: request.keepIndex,
        targetBranch: request.targetBranch,
      ),
    );
    final failure = result.failure;
    if (failure != null) {
      throw StashException(failure.kind.toModel());
    }
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return StashPreview(
      token: preview.token,
      kind: preview.kind.toModel(),
      commands: [
        for (final command in preview.commands)
          List.unmodifiable(command.arguments),
      ],
      affectedPaths: preview.affectedPaths,
      includesUntracked: preview.includesUntracked,
      keepsIndex: preview.keepsIndex,
      selectedObjectId: preview.selectedObjectId,
      targetBranch: preview.targetBranch,
      destructive: preview.destructive,
    );
  }

  @override
  Future<StashExecutionResult> executeStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionStashExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return StashExecutionResult(
      state: result.state.toModel(),
      failure: result.failure?.kind.toModel(),
      activityIds: List.unmodifiable(result.activityIds),
      stashCreated: result.stashCreated,
      checkoutCompleted: result.checkoutCompleted,
      reapplyCompleted: result.reapplyCompleted,
      stashRetained: result.stashRetained,
    );
  }

  @override
  Future<bool> cancelStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionStashCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<HistoryMutationPreview> previewHistoryMutation(
    RepositorySessionIdentity identity,
    HistoryMutationRequest request,
  ) async {
    final result = await _calls.repositorySessionHistoryMutationPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native_history_operation.NativeHistoryMutationRequest(
        kind: request.kind.toNative(),
        targets: request.targets,
        sourceName: request.sourceName == null
            ? null
            : Uint8List.fromList(request.sourceName!),
        mergeMode: request.mergeMode.toNative(),
        acknowledgePublishedHistory: request.acknowledgePublishedHistory,
        noCommit: request.noCommit,
      ),
    );
    final failure = result.failure;
    if (failure != null) {
      throw HistoryMutationException(failure.kind.toModel());
    }
    final preview = result.preview;
    if (preview == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return HistoryMutationPreview(
      token: preview.token,
      kind: preview.kind.toModel(),
      arguments: List.unmodifiable(preview.arguments),
      targets: List.unmodifiable(preview.targets),
      sourceName: preview.sourceName?.toList(growable: false),
      currentBranch: preview.currentBranch.toList(growable: false),
      currentHead: preview.currentHead,
      publishedHistory: preview.publishedHistory,
      alreadyContained: preview.alreadyContained,
      noCommit: preview.noCommit,
    );
  }

  @override
  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionHistoryMutationExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return HistoryMutationExecutionResult(
      state: result.state.toModel(),
      failure: result.failure?.kind.toModel(),
      activityIds: List.unmodifiable(result.activityIds),
      conflictingPaths: [
        for (final path in result.conflictingPaths)
          path.toList(growable: false),
      ],
      sequencer: result.sequencer?.toModel(),
    );
  }

  @override
  Future<bool> cancelHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionHistoryMutationCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<BigInt> beginConflictPrediction(
    RepositorySessionIdentity identity,
  ) async {
    final result = await _calls.repositorySessionConflictPredictionBegin(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    final failure = result.failure;
    if (failure != null) {
      throw HistoryMutationException(failure.kind.toModel());
    }
    final token = result.token;
    if (token == null) {
      throw const HistoryMutationException(HistoryMutationFailureCode.read);
    }
    return token;
  }

  @override
  Future<ConflictPredictionResult> executeConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
    ConflictPredictionKind kind,
    String target,
  ) async {
    final result = await _calls.repositorySessionConflictPrediction(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
      kind: kind.toNative(),
      target: target,
    );
    return ConflictPredictionResult(
      kind: result.kind.toModel(),
      target: result.target,
      conflictingPaths: [
        for (final path in result.conflictingPaths)
          path.toList(growable: false),
      ],
      analyzedCommits: result.analyzedCommits,
      totalCommits: result.totalCommits,
      complete: result.complete,
      activityIds: List.unmodifiable(result.activityIds),
      failure: result.failure?.kind.toModel(),
    );
  }

  @override
  Future<bool> cancelConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionConflictPredictionCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<RebasePlan> loadRebasePlan(
    RepositorySessionIdentity identity,
    String onto,
    List<int>? ontoName,
  ) async {
    final result = await _calls.repositorySessionRebasePlan(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      onto: onto,
      ontoName: ontoName == null ? null : Uint8List.fromList(ontoName),
    );
    _throwRebaseFailure(result.failure);
    return RebasePlan(
      token: result.token!,
      onto: result.onto,
      ontoName: result.ontoName?.toList(growable: false),
      currentBranch: result.currentBranch.toList(growable: false),
      currentHead: result.currentHead,
      instructions: [
        for (final instruction in result.instructions)
          _rebaseInstruction(instruction),
      ],
      publishedCount: result.publishedCount,
      activityIds: List.unmodifiable(result.activityIds),
    );
  }

  @override
  Future<RebasePreview> previewRebase(
    RepositorySessionIdentity identity,
    BigInt token,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) async {
    final result = await _calls.repositorySessionRebasePreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
      instructions: [
        for (final instruction in instructions)
          native_rebase.NativeRebaseInstruction(
            id: instruction.id,
            action: instruction.action.toNative(),
            oid: instruction.oid,
            subject: Uint8List.fromList(instruction.subject),
            published: instruction.published,
            replacementMessage: instruction.replacementMessage == null
                ? null
                : Uint8List.fromList(instruction.replacementMessage!),
            autosquashBaseId: instruction.autosquashBaseId,
          ),
      ],
      acknowledgePublishedHistory: acknowledgePublishedHistory,
      applyAutosquash: applyAutosquash,
    );
    _throwRebaseFailure(result.failure);
    return RebasePreview(
      token: result.token!,
      arguments: List.unmodifiable(result.arguments),
      todo: result.todo.toList(growable: false),
      instructionCount: result.instructionCount,
      publishedCount: result.publishedCount,
      instructions: [
        for (final instruction in result.instructions)
          _rebaseInstruction(instruction),
      ],
      autosquashApplied: result.autosquashApplied,
    );
  }

  @override
  Future<RebaseExecutionResult> executeRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionRebaseExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return RebaseExecutionResult(
      state: result.state.toModel(),
      failure: result.failure?.kind.toModel(),
      activityIds: List.unmodifiable(result.activityIds),
      conflictingPaths: [
        for (final path in result.conflictingPaths)
          path.toList(growable: false),
      ],
      runningInstruction: result.runningInstruction?.toList(growable: false),
    );
  }

  @override
  Future<bool> cancelRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionRebaseCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<ConflictSnapshot> loadConflicts(
    RepositorySessionIdentity identity,
  ) async {
    final result = await _calls.repositorySessionConflicts(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    return _conflictSnapshot(result);
  }

  @override
  Future<ConflictSnapshot> saveConflictResult(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    List<int> result,
  ) async => _conflictSnapshot(
    await _calls.repositorySessionConflictSaveResult(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(path),
      expectedFingerprint: expectedFingerprint,
      result: Uint8List.fromList(result),
    ),
  );

  @override
  Future<ConflictSnapshot> chooseConflictSide(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    ConflictSideChoice choice,
  ) async => _conflictSnapshot(
    await _calls.repositorySessionConflictChooseSide(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(path),
      expectedFingerprint: expectedFingerprint,
      choice: choice.toNative(),
    ),
  );

  @override
  Future<ConflictSnapshot> takeConflictRegion(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    int regionIndex,
    ConflictRegionChoice choice,
  ) async => _conflictSnapshot(
    await _calls.repositorySessionConflictTakeRegion(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(path),
      expectedFingerprint: expectedFingerprint,
      regionIndex: regionIndex,
      choice: choice.toNative(),
    ),
  );

  @override
  Future<ConflictSnapshot> undoConflictResolution(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async => _conflictSnapshot(
    await _calls.repositorySessionConflictUndoResolution(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(path),
    ),
  );

  @override
  Future<ConflictContinuationResult> continueConflictOperation(
    RepositorySessionIdentity identity,
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) async {
    final result = mergeMessage == null
        ? await _calls.repositorySessionConflictContinue(
            sessionId: identity.nativeId,
            generation: BigInt.from(identity.generation),
            action: action.toNative(),
          )
        : await _calls.repositorySessionConflictContinueWithMessage(
            sessionId: identity.nativeId,
            generation: BigInt.from(identity.generation),
            action: action.toNative(),
            message: mergeMessage,
          );
    return ConflictContinuationResult(
      state: result.state.toModel(),
      activityIds: List.unmodifiable(result.activityIds),
      failure: result.failure?.kind.toModel(),
    );
  }

  static ConflictSnapshot _conflictSnapshot(
    native_conflict.NativeConflictSnapshotResult result,
  ) {
    if (result.failure != null) {
      throw ConflictException(result.failure!.kind.toModel());
    }
    final snapshot = result.snapshot!;
    return ConflictSnapshot(
      operation: snapshot.operation.toModel(),
      currentLabel: snapshot.currentLabel.toList(growable: false),
      incomingLabel: snapshot.incomingLabel.toList(growable: false),
      currentStep: snapshot.currentStep,
      totalSteps: snapshot.totalSteps,
      suggestedMessage: snapshot.suggestedMessage,
      files: [for (final file in snapshot.files) _conflictFile(file)],
      resolvedUndoPaths: [
        for (final path in snapshot.resolvedUndoPaths)
          path.toList(growable: false),
      ],
      canContinue: snapshot.canContinue,
      canSkip: snapshot.canSkip,
    );
  }

  static ConflictFile _conflictFile(native_conflict.NativeConflictFile file) =>
      ConflictFile(
        path: file.path.toList(growable: false),
        kind: file.kind.toModel(),
        ancestor: _conflictSide(file.ancestor),
        current: _conflictSide(file.current),
        incoming: _conflictSide(file.incoming),
        result: file.result?.toList(growable: false),
        resultPresent: file.resultPresent,
        resultMode: file.resultMode,
        markerFree: file.markerFree,
        regions: [
          for (final region in file.regions)
            ConflictRegion(
              index: region.index,
              current: region.current.toList(growable: false),
              incoming: region.incoming.toList(growable: false),
              ancestor: region.ancestor?.toList(growable: false),
            ),
        ],
        fingerprint: file.fingerprint,
        canUndoResolution: file.canUndoResolution,
      );

  static ConflictSide _conflictSide(native_conflict.NativeConflictSide side) =>
      ConflictSide(
        present: side.present,
        mode: side.mode,
        content: side.content?.toList(growable: false),
        byteCount: side.byteCount.toInt(),
      );

  @override
  Future<FixupSuggestion> suggestFixupBase(
    RepositorySessionIdentity identity, {
    String? selectedCommit,
    List<List<int>> paths = const [],
  }) async {
    final result = await _calls.repositorySessionFixupSuggestion(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      selectedCommit: selectedCommit,
      paths: [for (final path in paths) Uint8List.fromList(path)],
    );
    _throwAdvancedFailure(result.failure);
    return FixupSuggestion(
      state: result.state.toModel(),
      candidate: result.candidate,
      subject: result.subject?.toList(growable: false),
      fixupMessage: result.fixupMessage?.toList(growable: false),
      squashMessage: result.squashMessage?.toList(growable: false),
      evidence: [
        for (final evidence in result.evidence)
          FixupEvidence(
            path: evidence.path?.toList(growable: false),
            commit: evidence.commit,
            subject: evidence.subject.toList(growable: false),
          ),
      ],
      activityIds: List.unmodifiable(result.activityIds),
    );
  }

  @override
  Future<RestackPlan> planRestack(
    RepositorySessionIdentity identity,
    List<int> rootBranch,
  ) async {
    final result = await _calls.repositorySessionRestackPlan(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      rootBranch: Uint8List.fromList(rootBranch),
    );
    _throwAdvancedFailure(result.failure);
    return RestackPlan(
      token: result.token!,
      rootBranch: result.rootBranch.toList(growable: false),
      steps: [
        for (final step in result.steps)
          RestackStep(
            id: step.id,
            branch: step.branch.toList(growable: false),
            expectedHead: step.expectedHead,
            oldParent: step.oldParent,
            newParent: step.newParent.toList(growable: false),
            expectedNewParentHead: step.expectedNewParentHead,
            published: step.published,
          ),
      ],
      publishedCount: result.publishedCount,
      incomplete: result.incomplete,
      activityIds: List.unmodifiable(result.activityIds),
    );
  }

  @override
  Future<RestackExecutionResult> executeRestack(
    RepositorySessionIdentity identity,
    BigInt token,
    bool acknowledgePublishedHistory,
  ) async {
    final result = await _calls.repositorySessionRestackExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
      acknowledgePublishedHistory: acknowledgePublishedHistory,
    );
    return RestackExecutionResult(
      state: result.state.toModel(),
      completedSteps: result.completedSteps,
      totalSteps: result.totalSteps,
      currentBranch: result.currentBranch?.toList(growable: false),
      recoveryRefs: [
        for (final reference in result.recoveryRefs)
          reference.toList(growable: false),
      ],
      conflictingPaths: [
        for (final path in result.conflictingPaths)
          path.toList(growable: false),
      ],
      activityIds: List.unmodifiable(result.activityIds),
      failure: result.failure?.kind.toModel(),
    );
  }

  @override
  Future<bool> cancelRestack(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionRestackCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<NamedSnapshotPage> namedSnapshots(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximum = 32,
  }) async {
    final result = await _calls.repositorySessionNamedSnapshots(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      offset: offset,
      maximum: maximum,
    );
    _throwNamedSnapshotFailure(result.failure);
    return NamedSnapshotPage(
      entries: result.entries.map(_namedSnapshot).toList(growable: false),
      total: result.total,
      nextOffset: result.nextOffset,
    );
  }

  @override
  Future<NamedSnapshotExecutionResult> createNamedSnapshot(
    RepositorySessionIdentity identity, {
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) async => _namedSnapshotExecution(
    await _calls.repositorySessionNamedSnapshotCreate(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      name: name,
      includeUntracked: includeUntracked,
      keepIndex: keepIndex,
    ),
  );

  @override
  Future<NamedSnapshotRestorePreview> previewNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) async {
    final result = await _calls.repositorySessionNamedSnapshotRestorePreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      snapshotId: snapshotId,
    );
    _throwNamedSnapshotFailure(result.failure);
    final preview = result.preview!;
    return NamedSnapshotRestorePreview(
      token: preview.token,
      snapshot: _namedSnapshot(preview.snapshot),
      replacementPaths: [
        for (final path in preview.replacementPaths)
          path.toList(growable: false),
      ],
      replacementPathsTruncated: preview.replacementPathsTruncated,
      replacesIndex: preview.replacesIndex,
      replacesWorktree: preview.replacesWorktree,
    );
  }

  @override
  Future<NamedSnapshotExecutionResult> executeNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => _namedSnapshotExecution(
    await _calls.repositorySessionNamedSnapshotRestoreExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    ),
  );

  @override
  Future<bool> cancelNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionNamedSnapshotRestoreCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryCommandFailure(result);
    return result.accepted;
  }

  @override
  Future<NamedSnapshotExecutionResult> branchFromNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
    List<int> branch,
  ) async => _namedSnapshotExecution(
    await _calls.repositorySessionNamedSnapshotBranch(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      snapshotId: snapshotId,
      branch: Uint8List.fromList(branch),
    ),
  );

  @override
  Future<NamedSnapshotExecutionResult> deleteNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) async => _namedSnapshotExecution(
    await _calls.repositorySessionNamedSnapshotDelete(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      snapshotId: snapshotId,
    ),
  );

  static NamedSnapshot _namedSnapshot(
    native_snapshot.NativeNamedSnapshot value,
  ) => NamedSnapshot(
    id: value.id,
    name: value.name,
    createdAtUnixMs: value.createdAtUnixMs,
    baseRef: value.baseRef?.toList(growable: false),
    baseOid: value.baseOid,
    objectId: value.objectId,
    stagedCount: value.stagedCount,
    unstagedCount: value.unstagedCount,
    untrackedCount: value.untrackedCount,
    includesUntracked: value.includesUntracked,
    keepsIndex: value.keepsIndex,
    state: value.state.toModel(),
  );

  static NamedSnapshotExecutionResult _namedSnapshotExecution(
    native_snapshot.NativeNamedSnapshotExecutionResult result,
  ) => NamedSnapshotExecutionResult(
    state: result.state.toModel(),
    snapshot: result.snapshot == null ? null : _namedSnapshot(result.snapshot!),
    recoveryRef: result.recoveryRef?.toList(growable: false),
    conflictingPaths: [
      for (final path in result.conflictingPaths) path.toList(growable: false),
    ],
    activityIds: List.unmodifiable(result.activityIds),
    failure: result.failure?.kind.toModel(),
  );

  static void _throwNamedSnapshotFailure(
    native_snapshot.NativeNamedSnapshotFailure? failure,
  ) {
    if (failure != null) {
      throw NamedSnapshotException(failure.kind.toModel());
    }
  }

  @override
  Future<RepositoryExtensionInventory> repositoryExtensions(
    RepositorySessionIdentity identity,
  ) async {
    final result = await _calls.repositorySessionExtensions(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    _throwExtensionFailure(result.failure);
    final inventory = result.inventory!;
    return RepositoryExtensionInventory(
      worktrees: [
        for (final entry in inventory.worktrees)
          WorktreeEntry(
            worktreeRoot: _pathFromNative(entry.worktreeRoot),
            gitDir: _pathFromNative(entry.gitDir),
            commonGitDir: _pathFromNative(entry.commonGitDir),
            head: entry.head,
            branch: entry.branch?.toList(growable: false),
            locked: entry.locked,
            prunable: entry.prunable,
            current: entry.current,
          ),
      ],
      submodules: [
        for (final entry in inventory.submodules)
          SubmoduleEntry(
            path: entry.path.toList(growable: false),
            commit: entry.commit,
            state: entry.state.toModel(),
          ),
      ],
      lfsAvailable: inventory.lfsAvailable,
      lfsUnavailableReason: inventory.lfsUnavailableReason,
      lfsEntries: [
        for (final entry in inventory.lfsEntries)
          LfsEntry(
            path: entry.path.toList(growable: false),
            state: entry.state.toModel(),
            pointer: entry.pointer == null
                ? null
                : LfsPointer(
                    oidSha256: entry.pointer!.oidSha256,
                    size: entry.pointer!.size,
                  ),
          ),
      ],
      activityIds: List.unmodifiable(inventory.activityIds),
    );
  }

  @override
  Future<NativePathIdentity> enterSubmodule(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    final result = await _calls.repositorySessionSubmoduleEnter(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(path),
    );
    _throwExtensionFailure(result.failure);
    return _pathFromNative(result.worktreeRoot!);
  }

  @override
  Future<LfsPointer?> inspectLfsPointer(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    final result = await _calls.repositorySessionLfsPointer(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(path),
    );
    _throwExtensionFailure(result.failure);
    final pointer = result.pointer;
    return pointer == null
        ? null
        : LfsPointer(oidSha256: pointer.oidSha256, size: pointer.size);
  }

  @override
  String? exactIgnorePattern(List<int> path, {required bool directory}) =>
      rust_api.ignoreExactPattern(
        path: Uint8List.fromList(path),
        directory: directory,
      );

  @override
  Future<RepositoryExtensionMutationResult> executeRepositoryExtension(
    RepositorySessionIdentity identity,
    RepositoryExtensionMutationRequest request,
  ) async {
    final result = await _calls.repositorySessionExtensionExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native_extensions.NativeExtensionMutationRequest(
        kind: request.kind.toNative(),
        path: request.path == null ? null : Uint8List.fromList(request.path!),
        worktreeRoot: request.worktreeRoot == null
            ? null
            : pathIdentityToNative(request.worktreeRoot!),
        pattern: request.pattern,
        reference: request.reference,
      ),
    );
    return RepositoryExtensionMutationResult(
      state: result.state.toModel(),
      activityIds: List.unmodifiable(result.activityIds),
      failure: result.failure?.kind.toModel(),
    );
  }

  static void _throwExtensionFailure(
    native_extensions.NativeExtensionFailure? failure,
  ) {
    if (failure != null) {
      throw RepositoryExtensionException(failure.kind.toModel());
    }
  }

  @override
  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) async {
    final result = await _calls.integrationDiscover(kind: kind.toNative());
    return [
      for (final candidate in result.candidates)
        IntegrationCandidate(
          id: candidate.id,
          kind: candidate.kind.toModel(),
          executable: pathIdentityFromNative(candidate.executable),
          launchMode: candidate.launchMode.toModel(),
        ),
    ];
  }

  @override
  Future<IntegrationPreview> previewIntegration(
    RepositorySessionIdentity identity,
    IntegrationRequest request,
  ) async {
    final result = await _calls.repositorySessionIntegrationPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: _integrationRequestToNative(request),
    );
    _throwIntegrationFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const IntegrationException(IntegrationFailureCode.read);
    }
    return _integrationPreview(preview);
  }

  @override
  Future<IntegrationPreview> previewExternalConflictMerge(
    RepositorySessionIdentity identity,
    ConflictFile file,
    IntegrationDefinition definition,
  ) async {
    final result = await _calls.repositorySessionConflictExternalMergePreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      path: Uint8List.fromList(file.path),
      expectedFingerprint: file.fingerprint,
      configured: _integrationDefinitionToNative(definition),
    );
    _throwIntegrationFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const IntegrationException(IntegrationFailureCode.read);
    }
    return _integrationPreview(preview);
  }

  @override
  Future<IntegrationPreview> previewExternalCommitDiff(
    RepositorySessionIdentity identity, {
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  }) async {
    final result = await _calls.repositorySessionCommitExternalDiffPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      oldRevision: oldRevision,
      newRevision: newRevision,
      oldPath: oldPath == null ? null : Uint8List.fromList(oldPath),
      newPath: newPath == null ? null : Uint8List.fromList(newPath),
      configured: _integrationDefinitionToNative(definition),
    );
    _throwIntegrationFailure(result.failure);
    final preview = result.preview;
    if (preview == null) {
      throw const IntegrationException(IntegrationFailureCode.read);
    }
    return _integrationPreview(preview);
  }

  @override
  Future<IntegrationExecutionResult> executeIntegration(
    RepositorySessionIdentity identity,
    BigInt token, {
    required bool confirmed,
  }) async {
    return _integrationExecution(
      await _calls.repositorySessionIntegrationExecute(
        sessionId: identity.nativeId,
        generation: BigInt.from(identity.generation),
        token: token,
        confirmed: confirmed,
      ),
    );
  }

  static IntegrationExecutionResult _integrationExecution(
    native_integrations.NativeIntegrationExecutionResult result,
  ) => IntegrationExecutionResult(
    state: result.state.toModel(),
    activityId: result.activityId,
    processId: result.processId,
    failure: result.failure?.kind.toModel(),
  );

  @override
  Future<bool> cancelIntegration(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionIntegrationCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  static native_integrations.NativeIntegrationRequest
  _integrationRequestToNative(IntegrationRequest request) =>
      native_integrations.NativeIntegrationRequest(
        kind: request.kind.toNative(),
        discoveredId: request.discoveredId,
        configured: request.configured == null
            ? null
            : _integrationDefinitionToNative(request.configured!),
        variables: native_integrations.NativeIntegrationVariables(
          url: request.variables.url,
          file: request.variables.file == null
              ? null
              : pathIdentityToNative(request.variables.file!),
          currentBranch: request.variables.currentBranch == null
              ? null
              : Uint8List.fromList(request.variables.currentBranch!),
          selectedCommit: request.variables.selectedCommit,
          diffLeft: request.variables.diffLeft == null
              ? null
              : pathIdentityToNative(request.variables.diffLeft!),
          diffRight: request.variables.diffRight == null
              ? null
              : pathIdentityToNative(request.variables.diffRight!),
          mergeBase: request.variables.mergeBase == null
              ? null
              : pathIdentityToNative(request.variables.mergeBase!),
          mergeCurrent: request.variables.mergeCurrent == null
              ? null
              : pathIdentityToNative(request.variables.mergeCurrent!),
          mergeIncoming: request.variables.mergeIncoming == null
              ? null
              : pathIdentityToNative(request.variables.mergeIncoming!),
          mergeResult: request.variables.mergeResult == null
              ? null
              : pathIdentityToNative(request.variables.mergeResult!),
        ),
      );

  static native_integrations.NativeIntegrationDefinition
  _integrationDefinitionToNative(IntegrationDefinition definition) =>
      native_integrations.NativeIntegrationDefinition(
        id: definition.id,
        kind: definition.kind.toNative(),
        executable: pathIdentityToNative(definition.executable),
        arguments: definition.arguments,
        execution: definition.execution.toNative(),
        launchMode: definition.launchMode.toNative(),
        requiresConfirmation: definition.requiresConfirmation,
        timeoutSeconds: definition.timeoutSeconds,
      );

  static IntegrationPreview _integrationPreview(
    native_integrations.NativeIntegrationPreview preview,
  ) => IntegrationPreview(
    token: preview.token,
    kind: preview.kind.toModel(),
    definitionId: preview.definitionId,
    executable: preview.executable,
    arguments: List.unmodifiable(preview.arguments),
    explicitShell: preview.explicitShell,
    waitsForExit: preview.waitsForExit,
    requiresConfirmation: preview.requiresConfirmation,
  );

  static void _throwIntegrationFailure(
    native_integrations.NativeIntegrationFailure? failure,
  ) {
    if (failure != null) {
      throw IntegrationException(failure.kind.toModel());
    }
  }

  @override
  Future<BigInt> startDiffContentSearch(
    RepositorySessionIdentity identity, {
    required String query,
    required int maximumCommits,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
    bool otherRefs = false,
  }) async {
    final result = await _calls
        .repositorySessionDiffContentSearchStartConfigured(
          sessionId: identity.nativeId,
          generation: BigInt.from(identity.generation),
          options: native_power.NativeDiffSearchOptions(
            query: query,
            maximumCommits: maximumCommits,
            caseSensitive: caseSensitive,
            scope: switch (scope) {
              DiffSearchScope.allRefs =>
                native_power.NativeDiffSearchScope.allRefs,
              DiffSearchScope.currentBranch =>
                native_power.NativeDiffSearchScope.currentBranch,
            },
            otherRefs: otherRefs,
          ),
        );
    _throwPowerFailure(result.failure);
    return result.token!;
  }

  @override
  Future<DiffContentSearchResult> pollDiffContentSearch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionDiffContentSearchPoll(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return DiffContentSearchResult(
      state: result.state.toModel(),
      matches: [
        for (final match in result.matches)
          DiffContentMatch(commit: match.commit, summary: match.summary),
      ],
      examinedCommits: result.examinedCommits.toInt(),
      completeness: result.completeness?.toModel(),
      activityIds: List.unmodifiable(result.activityIds),
      failure: result.failure?.kind.toModel(),
    );
  }

  @override
  Future<CommitArchiveStatus> saveCommitArchive(
    RepositorySessionIdentity identity, {
    required String commit,
    required String prefix,
    required String destination,
    required void Function(CommitArchiveStatus status) onProgress,
    required bool Function() isCanceled,
  }) async {
    final sessionId = identity.nativeId;
    final generation = BigInt.from(identity.generation);
    final started = await _calls.repositorySessionArchiveStart(
      sessionId: sessionId,
      generation: generation,
      commit: commit,
      prefix: prefix,
    );
    if (started.failure case final failure?) {
      throw CommitArchiveException(failure.kind.toModel());
    }
    final token = started.token!;
    BigInt? file;
    try {
      void stopIfCanceled() {
        if (isCanceled()) {
          throw const CommitArchiveException(CommitArchiveFailureCode.canceled);
        }
      }

      CommitArchiveStatus status;
      while (true) {
        stopIfCanceled();
        status = _archiveStatus(
          await _calls.repositorySessionArchiveStatus(
            sessionId: sessionId,
            generation: generation,
            token: token,
          ),
        );
        onProgress(status);
        if (status.state != CommitArchiveState.running) break;
        await Future<void>.delayed(_archivePollInterval);
      }
      if (status.state != CommitArchiveState.completed) {
        throw CommitArchiveException(
          status.failure ?? CommitArchiveFailureCode.git,
        );
      }
      final sink = await rust_api.archiveFileBegin(destination: destination);
      if (sink == null) {
        throw const CommitArchiveException(CommitArchiveFailureCode.write);
      }
      file = sink;
      var offset = BigInt.zero;
      while (true) {
        stopIfCanceled();
        final page = await _calls.repositorySessionArchivePage(
          sessionId: sessionId,
          generation: generation,
          token: token,
          offset: offset,
        );
        if (page.failure case final failure?) {
          throw CommitArchiveException(failure.kind.toModel());
        }
        if (page.bytes.isEmpty) break;
        if (!await rust_api.archiveFileAppend(token: sink, bytes: page.bytes)) {
          file = null;
          throw const CommitArchiveException(CommitArchiveFailureCode.write);
        }
        offset += BigInt.from(page.bytes.length);
      }
      if (offset != BigInt.from(status.archiveBytes)) {
        throw const CommitArchiveException(CommitArchiveFailureCode.write);
      }
      final written = await rust_api.archiveFileCommit(token: sink);
      file = null;
      if (!written) {
        throw const CommitArchiveException(CommitArchiveFailureCode.write);
      }
      return status;
    } finally {
      if (file != null) await rust_api.archiveFileAbort(token: file);
      try {
        await _calls.repositorySessionArchiveRelease(
          sessionId: sessionId,
          generation: generation,
          token: token,
        );
      } on Object {
        // The host deletes the snapshot when the session closes.
      }
    }
  }

  static const _archivePollInterval = Duration(milliseconds: 100);

  static CommitArchiveStatus _archiveStatus(
    native_archive.NativeArchiveStatus status,
  ) => CommitArchiveStatus(
    state: status.state.toModel(),
    files: status.files.toInt(),
    totalFiles: status.totalFiles.toInt(),
    archiveBytes: status.archiveBytes.toInt(),
    missingSubmodules: List.unmodifiable(status.missingSubmodules),
    missingSubmoduleCount: status.missingSubmoduleCount.toInt(),
    unresolvedLfs: List.unmodifiable(status.unresolvedLfs),
    unresolvedLfsCount: status.unresolvedLfsCount.toInt(),
    failure: status.failure?.kind.toModel(),
  );

  @override
  Future<BigInt> startRepositoryStatistics(
    RepositorySessionIdentity identity,
  ) async {
    final result = await _calls.repositorySessionStatisticsStart(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    _throwPowerFailure(result.failure);
    return result.token!;
  }

  @override
  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionStatisticsPoll(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return RepositoryStatisticsResult(
      state: result.state.toModel(),
      commitCount: result.commitCount.toInt(),
      localBranchCount: result.localBranchCount.toInt(),
      tagCount: result.tagCount.toInt(),
      changedPathCount: result.changedPathCount.toInt(),
      incomplete: result.incomplete,
      activityIds: List.unmodifiable(result.activityIds),
      failure: result.failure?.kind.toModel(),
    );
  }

  @override
  Future<bool> cancelPowerJob(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionPowerJobCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  @override
  Future<BisectState> bisectState(RepositorySessionIdentity identity) async {
    final result = await _calls.repositorySessionBisectState(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    _throwPowerFailure(result.failure);
    return _bisectState(result.state!);
  }

  @override
  Future<BisectPreview> previewBisect(
    RepositorySessionIdentity identity,
    BisectAction action, {
    String? good,
    String? bad,
  }) async {
    final result = await _calls.repositorySessionBisectPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      action: action.toNative(),
      good: good,
      bad: bad,
    );
    _throwPowerFailure(result.failure);
    final preview = result.preview!;
    return BisectPreview(
      token: preview.token,
      action: preview.action.toModel(),
      arguments: List.unmodifiable(preview.arguments),
    );
  }

  @override
  Future<BisectExecutionResult> executeBisect(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionBisectExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    return BisectExecutionResult(
      state: result.state.toModel(),
      bisect: result.bisect == null ? null : _bisectState(result.bisect!),
      activityId: result.activityId,
      failure: result.failure?.kind.toModel(),
    );
  }

  @override
  Future<bool> cancelBisectPreview(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionBisectCancelPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  static BisectState _bisectState(native_power.NativeBisectState state) =>
      BisectState(
        active: state.active,
        current: state.current,
        originalHead: state.originalHead,
        timeline: [
          for (final entry in state.timeline)
            BisectTimelineEntry(
              revision: entry.revision,
              mark: entry.mark.toModel(),
            ),
        ],
        remainingSteps: state.remainingSteps?.toInt(),
        nextStepSummary: state.nextStepSummary,
      );

  static void _throwPowerFailure(native_power.NativePowerFailure? failure) {
    if (failure != null) {
      throw PowerToolsException(failure.kind.toModel());
    }
  }

  static void _throwAdvancedFailure(
    native_advanced.NativeAdvancedRebaseFailure? failure,
  ) {
    if (failure != null) {
      throw AdvancedRebaseException(failure.kind.toModel());
    }
  }

  static RebaseInstruction _rebaseInstruction(
    native_rebase.NativeRebaseInstruction instruction,
  ) => RebaseInstruction(
    id: instruction.id,
    action: instruction.action.toModel(),
    oid: instruction.oid,
    subject: instruction.subject.toList(growable: false),
    published: instruction.published,
    replacementMessage: instruction.replacementMessage?.toList(growable: false),
    autosquashBaseId: instruction.autosquashBaseId,
  );

  static void _throwRebaseFailure(native_rebase.NativeRebaseFailure? failure) {
    if (failure != null) {
      throw RebaseException(failure.kind.toModel());
    }
  }

  @override
  Future<DiffSyntaxPage> diffSyntaxPage(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
    required int offset,
    required int maximumRows,
  }) async {
    final result = await _calls.repositorySessionDiffSyntaxPage(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      request: native_diff.NativeDiffSyntaxRequest(
        origin: origin.toNative(),
        diffRequestId: diffRequestId,
        syntaxRequestId: syntaxRequestId,
        offset: BigInt.from(offset),
        maximumRows: maximumRows,
      ),
    );
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null || page.rows.length != page.rowCount) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    List<DiffSyntaxByteSpan> spans(List<native_diff.NativeSyntaxSpan> spans) =>
        List.unmodifiable([
          for (final span in spans)
            DiffSyntaxByteSpan(span.start, span.end, span.kind.toModel()),
        ]);
    return DiffSyntaxPage(
      origin: page.origin.toModel(),
      diffRequestId: page.diffRequestId,
      syntaxRequestId: page.syntaxRequestId,
      offset: page.offset.toInt(),
      nextOffset: page.nextOffset?.toInt(),
      rows: List.unmodifiable([
        for (final row in page.rows)
          DiffSyntaxRowResult(
            stableId: row.stableId,
            oldState: row.oldState.toModel(),
            newState: row.newState.toModel(),
            oldSpans: spans(row.oldSpans),
            newSpans: spans(row.newSpans),
          ),
      ]),
    );
  }

  @override
  Future<bool> cancelDiffSyntax(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
  }) async {
    final result = await _calls.repositorySessionDiffSyntaxCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      origin: origin.toNative(),
      diffRequestId: diffRequestId,
      syntaxRequestId: syntaxRequestId,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  DiffPage _diffPage(native.NativeDiffResult result) {
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return DiffPage(
      requestId: page.requestId,
      layout: page.layout.toModel(),
      totalRows: page.totalRows.toInt(),
      offset: page.offset.toInt(),
      rows: [
        for (final row in page.rows)
          DiffDisplayRow(
            stableId: row.stableId,
            kind: row.kind.toModel(),
            text: List.unmodifiable(row.text),
            oldLine: row.oldLine,
            newLine: row.newLine,
            selectable: row.selectable,
            textTruncated: row.textTruncated,
            intraLine: [
              for (final span in row.intraLine) DiffSpan(span.start, span.end),
            ],
            syntax: row.syntax == null ? null : List.unmodifiable(row.syntax!),
            fileKind: row.fileKind?.toModel(),
            oldPath: row.oldPath == null
                ? null
                : List.unmodifiable(row.oldPath!),
            newPath: row.newPath == null
                ? null
                : List.unmodifiable(row.newPath!),
            sectionEnd: row.sectionEnd?.toInt(),
          ),
      ],
      payloadBytes: page.payloadBytes.toInt(),
    );
  }

  @override
  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  }) async {
    final result = await _calls.repositorySessionHistoryMetadata(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      objectIds: objectIds,
    );
    throwRepositoryFailure(result.failure);
    return [
      for (final row in result.rows)
        HistoryMetadata(
          objectId: row.objectId,
          subject: List.unmodifiable(row.subject),
          author: List.unmodifiable(row.author),
          avatarHash: row.avatarHash,
          authorTime: row.authorTime.toInt(),
          failure: row.failure?.toModel(),
        ),
    ];
  }

  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) async {
    final result = await _calls.repositorySessionInspectIndexLock(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    if (result.failure case final failure?) {
      throw IndexLockException(failure.toModel());
    }
    return IndexLockInspection(
      present: result.present,
      token: result.token,
      sizeBytes: result.sizeBytes,
    );
  }

  @override
  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionRemoveIndexLock(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    if (result.failure case final failure?) {
      throw IndexLockException(failure.toModel());
    }
    if (!result.removed) {
      throw const IndexLockException(IndexLockFailureCode.invalidToken);
    }
  }

  @override
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  ) async {
    final result = await _calls.repositorySessionInspectLocks(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    if (result.failure case final failure?) {
      throw IndexLockException(failure.toModel());
    }
    return RepositoryLockInspection(
      locks: [
        for (final lock in result.locks)
          RepositoryLock(
            token: lock.token,
            path: lock.path,
            worktreeScoped: lock.worktreeScoped,
            sizeBytes: lock.sizeBytes.toInt(),
            age: switch (lock.ageSeconds) {
              final seconds? => Duration(seconds: seconds.toInt()),
              null => null,
            },
          ),
      ],
      truncated: result.truncated,
    );
  }

  @override
  Future<StatusAcceleration> statusAcceleration(
    RepositorySessionIdentity identity,
  ) async => _statusAcceleration(
    await _calls.repositorySessionStatusAcceleration(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    ),
  );

  @override
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  ) async => _statusAcceleration(
    await _calls.repositorySessionEnableStatusAcceleration(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    ),
  );

  StatusAcceleration _statusAcceleration(
    native.NativeStatusAccelerationResult result,
  ) {
    throwRepositoryFailure(result.failure);
    final acceleration = result.acceleration;
    if (acceleration == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return StatusAcceleration(
      untrackedCache: acceleration.untrackedCache,
      fsmonitor: acceleration.fsmonitor,
      fsmonitorAvailable: acceleration.fsmonitorAvailable,
      lastScan: switch (acceleration.lastScanMillis) {
        final millis? => Duration(milliseconds: millis.toInt()),
        null => null,
      },
    );
  }

  @override
  Future<bool> removeRepositoryLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionRemoveLock(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    if (result.failure case final failure?) {
      // Gone already: whoever held it has finished.
      final code = failure.toModel();
      if (code == IndexLockFailureCode.missing) return false;
      throw IndexLockException(code);
    }
    return result.removed;
  }

  @override
  Future<DiffRendererPreview> validateDiffRenderer(
    RepositorySessionIdentity identity,
    DiffRendererDefinition definition,
  ) async {
    final result = await _calls.repositorySessionDiffRendererValidate(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      definition: _rendererDefinitionToNative(definition),
    );
    return _rendererPreview(identity, result);
  }

  @override
  Future<DiffRendererPreview> previewDiffRenderer(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required DiffRendererDefinition definition,
  }) async {
    final result = await _calls.repositorySessionDiffRendererPreview(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      requestId: requestId,
      definition: _rendererDefinitionToNative(definition),
    );
    return _rendererPreview(identity, result);
  }

  @override
  Future<DiffRendererResult> executeDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => _rendererResult(
    await _calls.repositorySessionDiffRendererExecute(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    ),
  );

  @override
  Future<DiffRendererResult> pollDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => _rendererResult(
    await _calls.repositorySessionDiffRendererPoll(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    ),
  );

  @override
  Future<bool> cancelDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final result = await _calls.repositorySessionDiffRendererCancel(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
      token: token,
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  static native_renderer.NativeDiffRendererDefinition
  _rendererDefinitionToNative(DiffRendererDefinition definition) =>
      native_renderer.NativeDiffRendererDefinition(
        id: definition.id,
        title: definition.title,
        executable: pathIdentityToNative(definition.executable),
        arguments: definition.arguments,
      );

  static DiffRendererPreview _rendererPreview(
    RepositorySessionIdentity source,
    native_renderer.NativeDiffRendererPreviewResult result,
  ) {
    if (result.failure case final failure?) {
      throw DiffRendererException(failure.kind.toModel());
    }
    final preview = result.preview!;
    return DiffRendererPreview(
      token: preview.token,
      source: source,
      title: preview.title,
      executable: preview.executable,
      capabilityArguments: List.unmodifiable(preview.capabilityArguments),
      arguments: List.unmodifiable(preview.arguments),
      protocol: preview.protocol,
      mediaType: preview.mediaType,
      inputBytes: preview.inputBytes.toInt(),
      outputLimitBytes: preview.outputLimitBytes.toInt(),
      timeoutSeconds: preview.timeoutSeconds,
    );
  }

  static DiffRendererResult _rendererResult(
    native_renderer.NativeDiffRendererResult result,
  ) => DiffRendererResult(
    state: result.state.toModel(),
    title: result.title,
    text: result.text,
    accessibilityText: result.accessibilityText,
    activityIds: List.unmodifiable(result.activityIds),
    failure: result.failure?.kind.toModel(),
  );

  @override
  Future<bool> close(RepositorySessionIdentity identity) async {
    final result = await _calls.repositorySessionClose(
      sessionId: identity.nativeId,
      generation: BigInt.from(identity.generation),
    );
    throwRepositoryFailure(result.failure);
    return result.accepted;
  }

  RepositorySessionEvent _event(native.NativeRepositoryEvent event) =>
      RepositorySessionEvent(
        kind: switch (event.kind) {
          native.NativeRepositoryEventKind.snapshot =>
            RepositorySessionEventKind.snapshot,
          native.NativeRepositoryEventKind.resynchronize =>
            RepositorySessionEventKind.resynchronize,
          native.NativeRepositoryEventKind.readCompleted =>
            RepositorySessionEventKind.readCompleted,
          native.NativeRepositoryEventKind.watchOverflow =>
            RepositorySessionEventKind.watchOverflow,
        },
        snapshot: event.snapshot == null ? null : _snapshot(event.snapshot!),
        readId: event.readId,
        cacheHit: event.cacheHit,
        watchOverflowRevision: event.watchOverflowRevision,
      );

  ActivityRecord _activityRecord(native_activity.NativeActivityRecord record) =>
      ActivityRecord(
        id: record.id,
        executable: record.executable,
        arguments: List.unmodifiable(record.arguments),
        startedAtUnixMs: record.startedAtUnixMs,
        finishedAtUnixMs: record.finishedAtUnixMs,
        status: record.status.toModel(),
        exitCode: record.exitCode,
        stdout: record.stdout,
        stdoutTotalBytes: record.stdoutTotalBytes,
        stdoutTruncated: record.stdoutTruncated,
        stderr: record.stderr,
        stderrTotalBytes: record.stderrTotalBytes,
        stderrTruncated: record.stderrTruncated,
        progress: switch (record.progress) {
          final progress? => ActivityProgress(
            phase: progress.phase,
            completed: progress.completed,
            total: progress.total,
            unit: progress.unit,
          ),
          null => null,
        },
      );
}
