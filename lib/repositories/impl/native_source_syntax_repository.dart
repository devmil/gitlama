import 'dart:typed_data';

import '../../models/diff_syntax.dart';
import '../../models/repository_state.dart';
import '../../models/source_syntax.dart';
import '../../rust/api.dart' as native;
import '../../rust/third_party/gitlama_contract/diff.dart' as native_diff;
import '../source_syntax_repository.dart';
import 'native_enum_mappers.g.dart';
import 'native_mappers.dart';

/// Parses held text with the in-process core's syntax worker.
final class NativeSourceSyntaxRepository implements SourceSyntaxRepository {
  const NativeSourceSyntaxRepository();

  @override
  Future<SourceSyntaxPage> sourceSyntaxPage({
    required BigInt viewId,
    required BigInt syntaxRequestId,
    required List<int> path,
    required Uint8List source,
    required int firstLine,
    required int maximumLines,
  }) async {
    final result = await native.textSyntaxPage(
      request: native_diff.NativeTextSyntaxRequest(
        viewId: viewId,
        syntaxRequestId: syntaxRequestId,
        path: Uint8List.fromList(path),
        source: source,
        firstLine: firstLine,
        maximumLines: maximumLines,
      ),
    );
    throwRepositoryFailure(result.failure);
    final page = result.page;
    if (page == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return SourceSyntaxPage(
      viewId: page.viewId,
      syntaxRequestId: page.syntaxRequestId,
      firstLine: page.firstLine,
      state: page.state.toModel(),
      lines: List.unmodifiable([
        for (final line in page.lines)
          SourceSyntaxLine(
            state: line.state.toModel(),
            runs: List.unmodifiable([
              for (final span in line.spans)
                DiffSyntaxRun(span.start, span.end, span.kind.toModel()),
            ]),
          ),
      ]),
    );
  }

  @override
  Future<bool> cancelSourceSyntax({
    required BigInt viewId,
    required BigInt syntaxRequestId,
  }) =>
      native.textSyntaxCancel(viewId: viewId, syntaxRequestId: syntaxRequestId);
}
