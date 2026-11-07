/// Which accepted diff projection of a session syntax colours belong to.
enum DiffSyntaxOrigin { committed, working }

/// The category of a run of diff text. `plain` is never transmitted as a
/// run; uncovered text is plain.
enum DiffSyntaxKind {
  plain,
  comment,
  keyword,
  string,
  number,
  type,
  function,
  variable,
  constant,
  operator,
  punctuation,
  attribute,
  tag,
}

/// Why one side of a row has, or lacks, colours. Every state but [ready]
/// shows plain text.
enum DiffSyntaxSideState {
  ready,
  unsupported,
  invalidEncoding,
  tooLarge,
  sourceChanged,
  limitReached,

  /// Transient pressure; a later demand may succeed.
  deferred,
  unavailable,
}

/// A category over UTF-8 byte offsets of a row's text, as the core sends it.
final class DiffSyntaxByteSpan {
  const DiffSyntaxByteSpan(this.start, this.end, this.kind);

  final int start;
  final int end;
  final DiffSyntaxKind kind;
}

/// The categories of one row, as the core sends them.
final class DiffSyntaxRowResult {
  const DiffSyntaxRowResult({
    required this.stableId,
    required this.oldState,
    required this.newState,
    this.oldSpans = const [],
    this.newSpans = const [],
  });

  final String stableId;
  final DiffSyntaxSideState oldState;
  final DiffSyntaxSideState newState;
  final List<DiffSyntaxByteSpan> oldSpans;
  final List<DiffSyntaxByteSpan> newSpans;
}

/// Contiguous rows of one syntax read. [nextOffset] is set when the reply
/// bound ended it before the requested rows.
final class DiffSyntaxPage {
  const DiffSyntaxPage({
    required this.origin,
    required this.diffRequestId,
    required this.syntaxRequestId,
    required this.offset,
    required this.rows,
    this.nextOffset,
  });

  final DiffSyntaxOrigin origin;
  final BigInt diffRequestId;
  final BigInt syntaxRequestId;
  final int offset;
  final List<DiffSyntaxRowResult> rows;
  final int? nextOffset;
}

/// A category over UTF-16 offsets of a row's displayed text, ready to paint.
final class DiffSyntaxRun {
  const DiffSyntaxRun(this.start, this.end, this.kind);

  final int start;
  final int end;
  final DiffSyntaxKind kind;

  @override
  bool operator ==(Object other) =>
      other is DiffSyntaxRun &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);
}

/// The paintable colours of one row: runs for the text of each side, or
/// null where that side stays plain.
final class DiffRowSyntax {
  const DiffRowSyntax({this.old, this.current});

  /// Runs over the row's text as the old side shows it.
  final List<DiffSyntaxRun>? old;

  /// Runs over the row's text as the new side shows it.
  final List<DiffSyntaxRun>? current;

  /// The runs a cell shows: a split cell its own side; a unified deletion
  /// the old side, an addition the new side, and context the new side when
  /// it is known, else the old.
  List<DiffSyntaxRun>? forCell({required bool oldSide, required bool split}) =>
      split ? (oldSide ? old : current) : current ?? old;
}
