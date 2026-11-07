enum DiffViewLayout { unified, sideBySide }

enum DiffWhitespace { preserve, ignoreAll, ignoreAmount, ignoreEndOfLine }

enum DiffTextEncoding { utf8, latin1 }

enum StagingSide { unstaged, staged }

enum StagingScope { all, files, rows }

enum StagingExecutionState {
  completed,
  stale,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

/// How diffs are shown. One stored choice applies to every diff view.
final class DiffViewPreferences {
  const DiffViewPreferences({
    this.wrap = false,
    this.layout = DiffViewLayout.unified,
    this.whitespace = DiffWhitespace.preserve,
    this.contextLines = 3,
    this.showIndicators = true,
    this.showMinimap = true,
  });

  /// The context line counts the diff toolbar and settings offer.
  static const contextChoices = [0, 3, 6, 10];

  /// The most context lines the store accepts.
  static const maxContextLines = 100;

  /// Long lines wrap instead of scrolling sideways.
  final bool wrap;
  final DiffViewLayout layout;
  final DiffWhitespace whitespace;
  final int contextLines;

  /// Rows show their + and - markers.
  final bool showIndicators;
  final bool showMinimap;

  /// [options] loaded the way these preferences ask, keeping its paths.
  DiffLoadOptions applyTo(DiffLoadOptions options) => options.copyWith(
    contextLines: contextLines,
    whitespace: whitespace,
    layout: layout,
  );

  /// Whether a diff loaded with [options] already shows what these ask.
  bool loads(DiffLoadOptions options) =>
      options.contextLines == contextLines &&
      options.whitespace == whitespace &&
      options.layout == layout;

  /// Whether [other] loads diffs the same way: only wrapping, markers or
  /// the minimap differ.
  bool loadsLike(DiffViewPreferences other) =>
      other.contextLines == contextLines &&
      other.whitespace == whitespace &&
      other.layout == layout;

  /// These preferences with the load choices of [options].
  DiffViewPreferences withLoadOptions(DiffLoadOptions options) => copyWith(
    contextLines: options.contextLines,
    whitespace: options.whitespace,
    layout: options.layout,
  );

  DiffViewPreferences copyWith({
    bool? wrap,
    DiffViewLayout? layout,
    DiffWhitespace? whitespace,
    int? contextLines,
    bool? showIndicators,
    bool? showMinimap,
  }) => DiffViewPreferences(
    wrap: wrap ?? this.wrap,
    layout: layout ?? this.layout,
    whitespace: whitespace ?? this.whitespace,
    contextLines: contextLines ?? this.contextLines,
    showIndicators: showIndicators ?? this.showIndicators,
    showMinimap: showMinimap ?? this.showMinimap,
  );

  @override
  bool operator ==(Object other) =>
      other is DiffViewPreferences &&
      other.wrap == wrap &&
      other.layout == layout &&
      other.whitespace == whitespace &&
      other.contextLines == contextLines &&
      other.showIndicators == showIndicators &&
      other.showMinimap == showMinimap;

  @override
  int get hashCode => Object.hash(
    wrap,
    layout,
    whitespace,
    contextLines,
    showIndicators,
    showMinimap,
  );
}

final class StagingRequest {
  const StagingRequest({
    required this.requestId,
    required this.side,
    required this.scope,
    this.paths = const [],
    this.rowIds = const [],
  });

  /// Zero means fresh whole-file intent; row actions require an accepted diff.
  final BigInt requestId;
  final StagingSide side;
  final StagingScope scope;
  final List<List<int>> paths;
  final List<String> rowIds;
}

final class StagingExecutionResult {
  const StagingExecutionResult({required this.state, this.diagnostic});

  final StagingExecutionState state;
  final StagingDiagnostic? diagnostic;
}

enum StagingFailureCode {
  invalidRequest,
  repositoryUnavailable,
  statusRead,
  indexRead,
  contentRead,
  contentChanged,
  indexPrepare,
  indexLocked,
  indexChanged,
  indexUnsafe,
  indexInstall,
  gitLaunch,
  gitTimeout,
  gitFailed,
  patchUnavailable,
}

/// Allowlisted diagnostics safe to copy into a support report.
final class StagingDiagnostic {
  const StagingDiagnostic({
    required this.code,
    this.activityId,
    this.exitCode,
    this.gitVersion,
  });
  final StagingFailureCode code;
  final BigInt? activityId;
  final int? exitCode;
  final String? gitVersion;
}

enum DiffFileKind {
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

final class DiffSpan {
  const DiffSpan(this.start, this.end);

  final int start;
  final int end;
}

final class DiffLoadOptions {
  const DiffLoadOptions({
    this.oldPath,
    this.newPath,
    this.contextLines = 3,
    this.whitespace = DiffWhitespace.preserve,
    this.layout = DiffViewLayout.unified,
    this.forceText = false,
  });

  final List<int>? oldPath;
  final List<int>? newPath;
  final int contextLines;
  final DiffWhitespace whitespace;
  final DiffViewLayout layout;

  /// Shows files Git considers binary as text, which may be unreadable.
  final bool forceText;

  DiffLoadOptions copyWith({
    List<int>? oldPath,
    List<int>? newPath,
    int? contextLines,
    DiffWhitespace? whitespace,
    DiffViewLayout? layout,
    bool? forceText,
  }) => DiffLoadOptions(
    oldPath: oldPath ?? this.oldPath,
    newPath: newPath ?? this.newPath,
    contextLines: contextLines ?? this.contextLines,
    whitespace: whitespace ?? this.whitespace,
    layout: layout ?? this.layout,
    forceText: forceText ?? this.forceText,
  );
}

enum DiffRowKind {
  file,
  hunk,
  context,
  addition,
  deletion,
  noNewline,
  binary,
  image,
  submodule,
  modeOnly,
  tooLarge,
}

final class DiffDisplayRow {
  const DiffDisplayRow({
    required this.stableId,
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
    this.selectable = false,
    this.textTruncated = false,
    this.intraLine = const [],
    this.syntax,
    this.fileKind,
    this.oldPath,
    this.newPath,
    this.loading = false,
    this.sectionEnd,
  });

  final String stableId;
  final DiffRowKind kind;
  final List<int> text;
  final int? oldLine;
  final int? newLine;
  final bool selectable;
  final bool textTruncated;
  final List<DiffSpan> intraLine;
  final List<int>? syntax;
  final DiffFileKind? fileKind;
  final List<int>? oldPath;
  final List<int>? newPath;

  /// Exclusive physical row offset of this file's section, on file headers.
  final int? sectionEnd;

  /// A stand-in shown while the row's page loads; never selectable.
  final bool loading;
}

/// Stable line position across context-width reloads of the same diff.
/// Hunk-derived row IDs can change when Git merges adjacent hunks.
String diffContextPosition(DiffDisplayRow row) =>
    '${row.oldPath?.join(',')}/${row.newPath?.join(',')}/'
    '${row.oldLine}/${row.newLine}';

final class DiffPage {
  const DiffPage({
    required this.requestId,
    required this.layout,
    required this.totalRows,
    required this.offset,
    required this.rows,
    required this.payloadBytes,
  });

  final BigInt requestId;
  final DiffViewLayout layout;
  final int totalRows;
  final int offset;
  final List<DiffDisplayRow> rows;
  final int payloadBytes;
}

final class DiffSearchResult {
  const DiffSearchResult({
    required this.requestId,
    required this.matches,
    required this.totalMatches,
    required this.truncated,
  });

  final BigInt requestId;
  final List<int> matches;
  final int totalMatches;
  final bool truncated;
}

enum ImageDecodeFailure {
  busy,
  unsupported,
  malformed,
  tooLarge,
  timedOut,
  canceled,
}

final class DecodedImageContent {
  const DecodedImageContent({
    required this.width,
    required this.height,
    required this.rgba,
    this.encodedBytes,
  });

  final int width;
  final int height;
  final List<int> rgba;

  /// Size of the stored file, when the decoder reported it.
  final int? encodedBytes;
}

/// The stored bytes of both sides of a change, read from a repository on
/// another computer to be decoded, compared or rendered on this one. A side
/// without content is null.
final class ChangeSourceBytes {
  const ChangeSourceBytes({this.old, this.newContent});

  final List<int>? old;
  final List<int>? newContent;
}

final class ImageDiffContent {
  const ImageDiffContent({this.old, this.newImage, this.failure});

  final DecodedImageContent? old;
  final DecodedImageContent? newImage;
  final ImageDecodeFailure? failure;
}

/// Accepts only the newest asynchronous file request. Native cancellation is still
/// requested, but publication correctness never depends on cancellation winning a race.
final class DiffRequestGuard {
  int _latestRequest = 0;

  int begin() => _latestRequest = _latestRequest + 1;

  bool accepts(int requestId) => requestId == _latestRequest;
}

/// The native staging transaction, including its authoritative refresh.
enum StagingPhase { idle, waiting, preparing, updating, refreshing }
