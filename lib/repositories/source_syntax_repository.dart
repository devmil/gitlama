import 'dart:typed_data';

import '../models/source_syntax.dart';

/// Syntax colours for text the application already holds, parsed on this
/// computer whichever computer the repository lives on.
abstract interface class SourceSyntaxRepository {
  /// Categories for up to `ContractLimits.textSyntaxPageLines` lines from
  /// the one-based [firstLine] of [source]. [path] only selects the grammar.
  Future<SourceSyntaxPage> sourceSyntaxPage({
    required BigInt viewId,
    required BigInt syntaxRequestId,
    required List<int> path,
    required Uint8List source,
    required int firstLine,
    required int maximumLines,
  });

  /// Cancels one request; idempotent.
  Future<bool> cancelSourceSyntax({
    required BigInt viewId,
    required BigInt syntaxRequestId,
  });
}
