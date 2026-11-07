import 'dart:convert';

import 'diff.dart';
import 'git_names.dart';

/// What an inspector inspects: one commit, or an ordered pair of commits.
sealed class InspectorTarget {
  const InspectorTarget();

  /// The commit whose files are shown; the newer side of a comparison.
  String get commit;

  /// The base of a comparison; null for a single commit.
  String? get base => null;
}

final class CommitTarget extends InspectorTarget {
  const CommitTarget(this.commit);

  @override
  final String commit;

  @override
  bool operator ==(Object other) =>
      other is CommitTarget && other.commit == commit;

  @override
  int get hashCode => Object.hash(CommitTarget, commit);
}

final class ComparisonTarget extends InspectorTarget {
  const ComparisonTarget({required this.base, required this.commit});

  @override
  final String base;

  @override
  final String commit;

  @override
  bool operator ==(Object other) =>
      other is ComparisonTarget && other.base == base && other.commit == commit;

  @override
  int get hashCode => Object.hash(ComparisonTarget, base, commit);
}

/// Which files the inspector sidebar lists.
enum InspectorScope { changed, all }

/// How the focused file is shown.
enum InspectorLens { diff, contents, blame, history }

/// Why a lens cannot show the focused path.
enum LensUnavailableReason {
  notChanged,
  deleted,
  needsText,
  submodule,
  directory,
}

/// A 1-based, inclusive line range.
final class InspectorLineRange {
  const InspectorLineRange(this.first, this.last);

  final int first;
  final int last;

  @override
  bool operator ==(Object other) =>
      other is InspectorLineRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

enum InspectorNavigationMode { push, replace }

/// One place an inspector can show. Back and Forward move between these.
/// Whether "Browse all files" applies to [location]: a single commit
/// that does not list all its files yet. Comparisons have no single tree.
bool canBrowseAllFiles(InspectorLocation? location) =>
    location != null &&
    location.target is CommitTarget &&
    location.scope != InspectorScope.all;

final class InspectorLocation {
  const InspectorLocation({
    required this.target,
    this.scope = InspectorScope.changed,
    this.path,
    this.directory = false,
    this.lens = InspectorLens.diff,
    this.lines,
    this.historyCommit,
    this.anchor = 0,
  });

  final InspectorTarget target;
  final InspectorScope scope;

  /// The focused file or folder; null shows every change of the target.
  final List<int>? path;

  /// Whether [path] names a folder.
  final bool directory;
  final InspectorLens lens;

  /// Restricts the history lens to these lines.
  final InspectorLineRange? lines;

  /// The selected entry of the history lens.
  final String? historyCommit;

  /// The first visible row of the content, restored on Back and Forward.
  final int anchor;

  InspectorLocation copyWith({
    InspectorTarget? target,
    InspectorScope? scope,
    List<int>? path,
    bool clearPath = false,
    bool? directory,
    InspectorLens? lens,
    InspectorLineRange? lines,
    bool clearLines = false,
    String? historyCommit,
    bool clearHistoryCommit = false,
    int? anchor,
  }) => InspectorLocation(
    target: target ?? this.target,
    scope: scope ?? this.scope,
    path: clearPath ? null : path ?? this.path,
    directory: clearPath ? false : directory ?? this.directory,
    lens: lens ?? this.lens,
    lines: clearLines ? null : lines ?? this.lines,
    historyCommit: clearHistoryCommit
        ? null
        : historyCommit ?? this.historyCommit,
    anchor: anchor ?? this.anchor,
  );

  /// Applies the rules every shown location satisfies: comparisons only list
  /// changed files, a location without focus shows the diff, a line range
  /// and a history selection only exist in the history lens, and a folder is
  /// only shown through its history.
  InspectorLocation normalized() {
    final scope = target is ComparisonTarget
        ? InspectorScope.changed
        : this.scope;
    final path = this.path;
    if (path == null || path.isEmpty) {
      return InspectorLocation(target: target, scope: scope, anchor: anchor);
    }
    final lens = directory ? InspectorLens.history : this.lens;
    final history = lens == InspectorLens.history;
    return InspectorLocation(
      target: target,
      scope: scope,
      path: path,
      directory: directory,
      lens: lens,
      lines: history && !directory ? lines : null,
      historyCommit: history ? historyCommit : null,
      anchor: anchor,
    );
  }

  /// Equality that ignores the scroll anchor.
  bool sameAs(InspectorLocation other) =>
      target == other.target &&
      scope == other.scope &&
      sameBytes(path, other.path) &&
      directory == other.directory &&
      lens == other.lens &&
      lines == other.lines &&
      historyCommit == other.historyCommit;

  @override
  bool operator ==(Object other) =>
      other is InspectorLocation && sameAs(other) && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(
    target,
    scope,
    path == null ? null : Object.hashAll(path!),
    directory,
    lens,
    lines,
    historyCommit,
    anchor,
  );

  Map<String, Object?> toJson() => {
    'kind': target is ComparisonTarget ? 'comparison' : 'commit',
    'commit': target.commit,
    'base': ?target.base,
    'scope': scope.name,
    'path': ?path,
    'directory': directory,
    'lens': lens.name,
    if (lines case final lines?) 'lines': [lines.first, lines.last],
    'historyCommit': ?historyCommit,
    'anchor': anchor,
  };

  /// Reads a location written by [toJson]; null for anything invalid.
  static InspectorLocation? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final kind = value['kind'];
    final commit = value['commit'];
    final base = value['base'];
    final scope = InspectorScope.values
        .where((item) => item.name == value['scope'])
        .firstOrNull;
    final lens = InspectorLens.values
        .where((item) => item.name == value['lens'])
        .firstOrNull;
    final directory = value['directory'];
    final anchor = value['anchor'];
    final historyCommit = value['historyCommit'];
    final path = value['path'];
    final lines = value['lines'];
    if (!isObjectId(commit) ||
        (kind != 'commit' && kind != 'comparison') ||
        (kind == 'comparison' && !isObjectId(base)) ||
        (kind == 'commit' && base != null) ||
        scope == null ||
        lens == null ||
        directory is! bool ||
        anchor is! int ||
        anchor < 0 ||
        anchor > maximumLine ||
        (historyCommit != null && !isObjectId(historyCommit))) {
      return null;
    }
    final pathBytes = path == null ? null : validPathBytes(path);
    if (path != null && pathBytes == null) return null;
    if (directory && pathBytes == null) return null;
    InspectorLineRange? range;
    if (lines != null) {
      if (lines is! List ||
          lines.length != 2 ||
          lines.any((line) => line is! int)) {
        return null;
      }
      final first = lines[0] as int;
      final last = lines[1] as int;
      if (first < 1 || first > last || last > maximumLine) return null;
      range = InspectorLineRange(first, last);
    }
    return InspectorLocation(
      target: kind == 'comparison'
          ? ComparisonTarget(base: base as String, commit: commit as String)
          : CommitTarget(commit as String),
      scope: scope,
      path: pathBytes,
      directory: directory,
      lens: lens,
      lines: range,
      historyCommit: historyCommit as String?,
      anchor: anchor,
    );
  }

  static const maximumLine = 10000000;

  static bool isObjectId(Object? value) =>
      value is String && RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value);

  /// Path bytes from untrusted JSON; null unless every item is a byte.
  static List<int>? validPathBytes(Object? value) {
    if (value is! List || value.isEmpty || value.length > 16384) return null;
    if (value.any((byte) => byte is! int || byte < 0 || byte > 255)) {
      return null;
    }
    return List<int>.unmodifiable(value.cast<int>());
  }
}

/// The diff an inspector shows: the target's, or a history entry's.
final class InspectorDiff {
  const InspectorDiff({
    required this.oldObjectId,
    required this.newObjectId,
    required this.diff,
    this.allChangesTooLarge = false,
  });

  /// The comparison base; null diffs [newObjectId] against its first parent.
  final String? oldObjectId;
  final String newObjectId;
  final DiffPage diff;

  /// Every changed file together exceeds the read limit, so [diff] shows
  /// one file at a time.
  final bool allChangesTooLarge;
}

/// Short object id for labels.
String shortObjectId(String value, [int length = 8]) =>
    value.length <= length ? value : value.substring(0, length);

/// The last path segment.
String inspectorFileName(List<int> path) {
  final text = utf8.decode(path, allowMalformed: true);
  final slash = text.lastIndexOf('/');
  return slash < 0 ? text : text.substring(slash + 1);
}

/// The label of a location in menus, window titles and announcements:
/// `hash`, `hash · file` or `hash · file · Lens`.
String inspectorLocationLabel(
  InspectorLocation location, {
  required String Function(InspectorLens) lensName,
}) {
  final target = location.target;
  final commit = switch (target) {
    ComparisonTarget(:final base, :final commit) =>
      '${shortObjectId(base)}→${shortObjectId(commit)}',
    CommitTarget(:final commit) => shortObjectId(commit),
  };
  final path = location.path;
  if (path == null) return commit;
  final name = inspectorFileName(path);
  if (location.lens == InspectorLens.diff) return '$commit · $name';
  return '$commit · $name · ${lensName(location.lens)}';
}
