import 'diff_syntax.dart';

/// The categories of one line of a text the application holds, such as a
/// conflicted file's side or an unsaved merge result. Runs are UTF-16
/// offsets of the line without its terminator.
final class SourceSyntaxLine {
  const SourceSyntaxLine({required this.state, this.runs = const []});

  final DiffSyntaxSideState state;
  final List<DiffSyntaxRun> runs;
}

/// Contiguous lines of one syntax read from [firstLine], one-based: fewer
/// than requested where the text ends. When [state] is not ready the whole
/// text stays plain and [lines] is empty.
final class SourceSyntaxPage {
  const SourceSyntaxPage({
    required this.viewId,
    required this.syntaxRequestId,
    required this.firstLine,
    required this.state,
    required this.lines,
  });

  final BigInt viewId;
  final BigInt syntaxRequestId;
  final int firstLine;
  final DiffSyntaxSideState state;
  final List<SourceSyntaxLine> lines;
}
