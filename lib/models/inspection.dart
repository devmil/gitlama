enum CommitTreeEntryKind { directory, file, symlink, submodule }

final class CommitTreeEntry {
  const CommitTreeEntry({
    required this.stableId,
    required this.path,
    required this.objectId,
    required this.kind,
    required this.mode,
    this.size,
  });

  final String stableId;
  final List<int> path;
  final String objectId;
  final CommitTreeEntryKind kind;
  final int mode;
  final int? size;
}

final class CommitTreePage {
  const CommitTreePage({
    required this.commit,
    this.directory,
    required this.entries,
    this.nextOffset,
  });

  final String commit;
  final List<int>? directory;
  final List<CommitTreeEntry> entries;
  final int? nextOffset;
}

enum CommitFileChangeKind {
  modified,
  added,
  deleted,
  renamed,
  copied,
  modeChanged,
  typeChanged,
  binary,
  image,
  submodule,
  conflict,
  untracked,
}

final class CommitFileChange {
  const CommitFileChange({
    required this.oldMode,
    required this.newMode,
    this.oldObjectId,
    this.newObjectId,
    required this.kind,
    this.similarity,
    required this.oldPath,
    required this.newPath,
  });

  final int oldMode;
  final int newMode;
  final String? oldObjectId;
  final String? newObjectId;
  final CommitFileChangeKind kind;
  final int? similarity;
  final List<int> oldPath;
  final List<int> newPath;
}

final class CommitIdentityDetail {
  const CommitIdentityDetail({
    required this.commit,
    required this.tree,
    required this.parents,
    required this.author,
    this.avatarHash = '',
    required this.authorTime,
    required this.authorTimezone,
    required this.committer,
    required this.committerTime,
    required this.committerTimezone,
    required this.message,
  });

  final String commit;
  final String tree;
  final List<String> parents;
  final List<int> author;
  final String avatarHash;
  final int authorTime;
  final List<int> authorTimezone;
  final List<int> committer;
  final int committerTime;
  final List<int> committerTimezone;
  final List<int> message;
}

final class CommitInspection {
  const CommitInspection({required this.detail, required this.files});

  final CommitIdentityDetail detail;
  final List<CommitFileChange> files;
}

final class PathHistoryEntry {
  const PathHistoryEntry({
    required this.stableId,
    required this.commit,
    required this.author,
    required this.authorTime,
    required this.summary,
    required this.path,
    this.oldPath,
  });

  final String stableId;
  final String commit;
  final List<int> author;
  final int authorTime;
  final List<int> summary;
  final List<int> path;
  final List<int>? oldPath;
}

final class PathHistoryPage {
  const PathHistoryPage({
    required this.entries,
    this.nextOffset,
    required this.renameHops,
    required this.incomplete,
  });

  final List<PathHistoryEntry> entries;
  final int? nextOffset;
  final int renameHops;
  final bool incomplete;
}

final class RangeHistoryEntry {
  const RangeHistoryEntry({
    required this.stableId,
    required this.commit,
    required this.author,
    required this.authorTime,
    required this.summary,
  });

  final String stableId;
  final String commit;
  final List<int> author;
  final int authorTime;
  final List<int> summary;
}

final class RangeHistoryResult {
  const RangeHistoryResult({required this.entries, required this.incomplete});

  final List<RangeHistoryEntry> entries;
  final bool incomplete;
}

final class BlameRow {
  const BlameRow({
    required this.stableId,
    required this.finalLine,
    required this.originalLine,
    required this.content,
    this.commit,
    required this.author,
    required this.authorTime,
    required this.summary,
    required this.originalPath,
    required this.boundary,
    required this.spanFirstLine,
    required this.spanLastLine,
  });

  final String stableId;
  final int finalLine;
  final int originalLine;
  final List<int> content;
  final String? commit;
  final List<int> author;
  final int authorTime;
  final List<int> summary;
  final List<int> originalPath;
  final bool boundary;
  final int spanFirstLine;
  final int spanLastLine;
}

final class BlamePage {
  const BlamePage({
    required this.requestId,
    required this.revision,
    required this.path,
    required this.totalRows,
    required this.offset,
    required this.rows,
  });

  final BigInt requestId;
  final String revision;
  final List<int> path;
  final int totalRows;
  final int offset;
  final List<BlameRow> rows;
}

final class RestorePreview {
  const RestorePreview({
    required this.token,
    required this.commit,
    required this.path,
    required this.sourceBytes,
    this.currentBytes,
    this.expectedHead,
  });

  final BigInt token;
  final String commit;
  final List<int> path;
  final List<int> sourceBytes;
  final List<int>? currentBytes;
  final String? expectedHead;
}

enum RestoreState {
  restored,
  stale,
  failed,
  outcomeUncertain,
  reconciledWithWarning,
}

final class RestoreResult {
  const RestoreResult({required this.state, this.failureCode});

  final RestoreState state;
  final String? failureCode;
}
