import 'dart:convert';

import 'conflict.dart';
import 'git_names.dart';

/// The index stages describe presence, not the history that caused it. In
/// particular, a rename can leave more than one path in this state.
enum ConflictPresence {
  bothDeleted,
  addedCurrent,
  deletedIncoming,
  addedIncoming,
  deletedCurrent,
  bothAdded,
  bothPresent,
  unknown,
}

enum ConflictContentDifference {
  identical,
  lineEndings,
  finalNewline,
  byteOrderMark,
  whitespace,
  content,
  unavailable,
  missingSide,
}

/// Presentation facts from the already loaded conflict snapshot. No Git reads
/// and no inference that a marker-free working file has been resolved.
final class ConflictDetails {
  ConflictDetails(this.file);

  final ConflictFile file;

  late final presence = switch ((
    file.ancestor.present,
    file.current.present,
    file.incoming.present,
  )) {
    (true, false, false) => ConflictPresence.bothDeleted,
    (false, true, false) => ConflictPresence.addedCurrent,
    (true, true, false) => ConflictPresence.deletedIncoming,
    (false, false, true) => ConflictPresence.addedIncoming,
    (true, false, true) => ConflictPresence.deletedCurrent,
    (false, true, true) => ConflictPresence.bothAdded,
    (true, true, true) => ConflictPresence.bothPresent,
    _ => ConflictPresence.unknown,
  };

  late final contentDifference = _compare();

  late final modeDiffers =
      {
        for (final side in [file.ancestor, file.current, file.incoming])
          if (side.present && side.mode != null) side.mode,
        if (file.resultPresent && file.resultMode != null) file.resultMode,
      }.length >
      1;

  ConflictContentDifference _compare() {
    final current = file.current;
    final incoming = file.incoming;
    if (!current.present || !incoming.present) {
      return ConflictContentDifference.missingSide;
    }
    final left = current.content;
    final right = incoming.content;
    if (left == null || right == null) {
      return ConflictContentDifference.unavailable;
    }
    if (sameBytes(left, right)) return ConflictContentDifference.identical;
    // Binary bytes and unavailable text must never be called equal because a
    // decoder replaced their bytes with the same replacement characters.
    if (file.kind != ConflictFileKind.text) {
      return ConflictContentDifference.content;
    }
    try {
      // Keep BOMs: the default UTF-8 decoder deliberately consumes them.
      String decode(List<int> bytes) =>
          '${_hasBom(bytes) ? '\uFEFF' : ''}${utf8.decode(bytes)}';
      final a = decode(left);
      final b = decode(right);
      String endings(String value) =>
          value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (endings(a) == endings(b)) {
        return ConflictContentDifference.lineEndings;
      }
      String withoutFinalNewline(String value) => value.endsWith('\r\n')
          ? value.substring(0, value.length - 2)
          : value.endsWith('\n') || value.endsWith('\r')
          ? value.substring(0, value.length - 1)
          : value;
      if (withoutFinalNewline(a) == withoutFinalNewline(b)) {
        return ConflictContentDifference.finalNewline;
      }
      String withoutBom(String value) =>
          value.startsWith('\uFEFF') ? value.substring(1) : value;
      if (withoutBom(a) == withoutBom(b)) {
        return ConflictContentDifference.byteOrderMark;
      }
      if (a.replaceAll(RegExp(r'\s'), '') == b.replaceAll(RegExp(r'\s'), '')) {
        return ConflictContentDifference.whitespace;
      }
      return ConflictContentDifference.content;
    } on FormatException {
      return ConflictContentDifference.unavailable;
    }
  }
}

bool _hasBom(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xef &&
    bytes[1] == 0xbb &&
    bytes[2] == 0xbf;
