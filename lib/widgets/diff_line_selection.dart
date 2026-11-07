import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../app/gitlama_layout.dart';
import '../l10n/l10n.dart';
import '../models/diff.dart';

/// The hunks and lines picked in a working diff, by stable row ID.
///
/// A picked hunk is sent as its hunk ID, which takes every change line of
/// the hunk, also lines not loaded yet. Unpicking one line of a picked hunk
/// replaces the hunk ID with its other loaded change lines, so the picked
/// rows are always the ones shown as checked.
final class DiffLineSelection {
  final Set<String> _ids = {};

  /// Row ID -> the hunk it belongs to.
  final Map<String, String> _hunkOf = {};

  /// Hunk ID -> its loaded change lines, in order.
  final Map<String, List<String>> _linesOf = {};

  /// Hunks whose rows are all loaded.
  final Set<String> _complete = {};

  /// The picked hunk and line IDs, in the order they were picked.
  List<String> get rowIds => _ids.toList(growable: false);

  bool get isEmpty => _ids.isEmpty;

  /// Indexes [rows], the loaded rows of a diff of [totalRows] rows.
  void update(List<DiffDisplayRow> rows, int totalRows) {
    _hunkOf.clear();
    _linesOf.clear();
    _complete.clear();
    String? hunk;
    for (final row in rows) {
      switch (row.kind) {
        case DiffRowKind.file:
          if (hunk != null) _complete.add(hunk);
          hunk = null;
        case DiffRowKind.hunk:
          if (hunk != null) _complete.add(hunk);
          hunk = row.stableId;
          _linesOf[hunk] = [];
        default:
          if (hunk == null) break;
          _hunkOf[row.stableId] = hunk;
          if (row.selectable && !row.loading) _linesOf[hunk]!.add(row.stableId);
      }
    }
    if (hunk != null && rows.length >= totalRows) _complete.add(hunk);
  }

  /// Whether the change line [row] is picked, alone or with its hunk.
  bool lineChecked(DiffDisplayRow row) {
    if (_ids.contains(row.stableId)) return true;
    final hunk = _hunkOf[row.stableId];
    return hunk != null && _ids.contains(hunk);
  }

  /// true when all of [hunk] is picked, false when none of it, null for
  /// some of its lines.
  bool? hunkChecked(String hunk) {
    if (_ids.contains(hunk)) return true;
    final lines = _linesOf[hunk] ?? const [];
    final picked = lines.where(_ids.contains).length;
    if (picked == 0) return false;
    return picked == lines.length && _complete.contains(hunk) ? true : null;
  }

  void setHunk(String hunk, bool value) {
    _ids.removeAll(_linesOf[hunk] ?? const []);
    if (value) {
      _ids.add(hunk);
    } else {
      _ids.remove(hunk);
    }
  }

  void setLine(DiffDisplayRow row, bool value) {
    final hunk = _hunkOf[row.stableId];
    if (value) {
      if (hunk == null || !_ids.contains(hunk)) _ids.add(row.stableId);
      return;
    }
    if (hunk != null && _ids.remove(hunk)) {
      _ids.addAll(_linesOf[hunk]!.where((id) => id != row.stableId));
    } else {
      _ids.remove(row.stableId);
    }
  }

  /// Whether every loaded hunk is picked.
  bool get allChecked =>
      _linesOf.isNotEmpty &&
      _linesOf.keys.every((hunk) => hunkChecked(hunk) == true);

  void selectAll() {
    for (final hunk in _linesOf.keys) {
      setHunk(hunk, true);
    }
  }

  void clear() => _ids.clear();

  /// The picked change lines among the loaded rows, and whether a picked
  /// hunk still has rows to load, which makes the count a lower bound.
  ({int count, bool more}) get pickedLines {
    var count = 0;
    var more = false;
    for (final MapEntry(key: hunk, value: lines) in _linesOf.entries) {
      if (_ids.contains(hunk)) {
        count += lines.length;
        more = more || !_complete.contains(hunk);
      } else {
        count += lines.where(_ids.contains).length;
      }
    }
    return (count: count, more: more);
  }
}

/// One row of a diff in which lines are picked: styled like the diff view
/// (code type, line-number gutters, added and removed fills) with a leading
/// checkbox on change lines and on hunk headers.
class DiffLineSelectionRow extends StatelessWidget {
  const DiffLineSelectionRow({
    required this.row,
    required this.checked,
    required this.onChanged,
    super.key,
  });

  final DiffDisplayRow row;

  /// The checkbox state; null on a hunk shows some of its lines picked.
  /// Ignored on rows without a checkbox.
  final bool? checked;

  /// Toggles the row; null on rows that cannot be picked.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => switch (row.kind) {
    DiffRowKind.hunk => _hunk(context),
    DiffRowKind.file => _file(context),
    DiffRowKind.addition ||
    DiffRowKind.deletion ||
    DiffRowKind.context => _line(context),
    _ => _note(context),
  };

  String get _text => utf8.decode(row.text, allowMalformed: true);

  Widget _checkSlot(BuildContext context, {required String label}) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: MeridianSpace.space4,
      end: MeridianSpace.space2,
    ),
    child: SizedBox(
      width: MeridianLayout.checkboxSize,
      child: onChanged == null
          ? null
          // The checkbox's label is empty (the line's text is the row);
          // its empty label area overflows the slot invisibly.
          : OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              minWidth: 0,
              maxWidth: double.infinity,
              child: MergeSemantics(
                child: Semantics(
                  label: label,
                  child: MeridianCheckbox(
                    value: checked,
                    tristate: true,
                    label: '',
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
    ),
  );

  /// A tap anywhere on the row toggles it, as on a checkbox's label.
  Widget _toggleArea(Widget child) => onChanged == null
      ? child
      : MeridianInteraction(
          canRequestFocus: false,
          cursor: SystemMouseCursors.click,
          onTap: () => onChanged!(checked != true),
          child: child,
        );

  Widget _hunk(BuildContext context) {
    final colors = context.colors;
    final text = _text;
    final match = RegExp(r'^(@@[^@]*@@)(.*)$').firstMatch(text);
    return _toggleArea(
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.paneAlt,
          border: Border.symmetric(horizontal: BorderSide(color: colors.line)),
        ),
        child: SizedBox(
          height: GitLamaLayout.hunkHeaderHeight,
          child: Row(
            children: [
              _checkSlot(
                context,
                label: context.l10n.lineSelectionSection(text),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: MeridianSpace.space3,
                ),
                child: Text(
                  match?.group(1) ?? text,
                  style: context.text.codeSm.copyWith(color: colors.inkMuted),
                ),
              ),
              const SizedBox(width: MeridianSpace.space4),
              Expanded(
                child: Text(
                  match?.group(2)?.trim() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.codeSm.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _file(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.symmetric(
      horizontal: MeridianSpace.space4,
      vertical: MeridianSpace.space3,
    ),
    child: Text(
      _text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.codeSm.copyWith(color: context.colors.ink),
    ),
  );

  Widget _note(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start:
          MeridianSpace.space4 +
          MeridianLayout.checkboxSize +
          MeridianSpace.space2 +
          2 * GitLamaLayout.diffGutterWidth +
          GitLamaLayout.diffSignWidth,
      top: MeridianSpace.space2,
      bottom: MeridianSpace.space2,
    ),
    child: Text(switch (row.kind) {
      DiffRowKind.noNewline => context.l10n.diffNoNewline,
      DiffRowKind.binary => context.l10n.diffBinaryFallback,
      DiffRowKind.image => context.l10n.diffImageFallback,
      DiffRowKind.submodule => context.l10n.diffSubmoduleFallback,
      DiffRowKind.modeOnly => context.l10n.diffModeOnlyFallback(_text),
      DiffRowKind.tooLarge => context.l10n.diffTooLargeFallback,
      _ => _text,
    }, style: context.text.caption.copyWith(color: context.colors.inkMuted)),
  );

  Widget _line(BuildContext context) {
    final colors = context.colors;
    final added = row.kind == DiffRowKind.addition;
    final removed = row.kind == DiffRowKind.deletion;
    final fill = added
        ? colors.successBg
        : removed
        ? context.git.deletedBg
        : colors.pane;
    final gutterStyle = context.text.codeSm.copyWith(color: colors.inkMuted);
    Widget gutter(int? number) => SizedBox(
      width: GitLamaLayout.diffGutterWidth,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: MeridianSpace.space4),
        child: Text(
          number?.toString() ?? '',
          textAlign: TextAlign.end,
          style: gutterStyle,
        ),
      ),
    );
    final text = _text;
    final line = removed ? row.oldLine : row.newLine;
    return _toggleArea(
      ColoredBox(
        color: fill,
        child: SizedBox(
          height: MeridianSize.rowCompact,
          child: Row(
            children: [
              _checkSlot(
                context,
                label: onChanged == null
                    ? ''
                    : added
                    ? context.l10n.lineSelectionAdded(line ?? 0, text)
                    : context.l10n.lineSelectionRemoved(line ?? 0, text),
              ),
              ExcludeSemantics(
                excluding: onChanged != null,
                child: Row(
                  children: [
                    gutter(row.oldLine),
                    gutter(row.newLine),
                    SizedBox(
                      width: GitLamaLayout.diffSignWidth,
                      child: Text(
                        added
                            ? '+'
                            : removed
                            ? '−'
                            : '',
                        textAlign: TextAlign.center,
                        style: context.text.diffSign.copyWith(
                          color: added ? colors.success : context.git.deleted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ExcludeSemantics(
                  excluding: onChanged != null,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: MeridianSpace.space4,
                    ),
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.code.copyWith(color: colors.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
