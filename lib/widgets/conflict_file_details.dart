import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/gitlama_layout.dart';
import '../l10n/l10n.dart';
import '../models/conflict.dart';
import '../models/conflict_details.dart';

/// Which sides have the file, as a sentence.
String conflictPresenceText(BuildContext context, ConflictPresence presence) {
  final l10n = context.l10n;
  return switch (presence) {
    ConflictPresence.bothDeleted => l10n.conflictPresenceBothDeleted,
    ConflictPresence.addedCurrent => l10n.conflictPresenceAddedCurrent,
    ConflictPresence.deletedIncoming => l10n.conflictPresenceDeletedIncoming,
    ConflictPresence.addedIncoming => l10n.conflictPresenceAddedIncoming,
    ConflictPresence.deletedCurrent => l10n.conflictPresenceDeletedCurrent,
    ConflictPresence.bothAdded => l10n.conflictPresenceBothAdded,
    ConflictPresence.bothPresent => l10n.conflictPresenceBothPresent,
    ConflictPresence.unknown => l10n.conflictPresenceUnknown,
  };
}

/// Explains unmerged index entries even when no visible text hunk exists.
final class ConflictFileDetails extends StatefulWidget {
  const ConflictFileDetails({required this.file, this.markerFree, super.key});

  final ConflictFile file;
  final bool? markerFree;

  @override
  State<ConflictFileDetails> createState() => _ConflictFileDetailsState();
}

final class _ConflictFileDetailsState extends State<ConflictFileDetails> {
  late var _details = ConflictDetails(widget.file);
  final _entries = <ConflictSide, String>{};
  Locale? _locale;
  late ConflictSide _working = _workingEntry();

  ConflictSide _workingEntry() => ConflictSide(
    present: widget.file.resultPresent,
    mode: widget.file.resultMode,
    content: widget.file.result,
    byteCount: widget.file.result?.length ?? 0,
  );

  String _entryText(BuildContext context, ConflictSide side) =>
      _entries.putIfAbsent(
        side,
        () => _entry(
          context,
          side,
          sizeKnown: !identical(side, _working) || side.content != null,
        ),
      );

  @override
  void didUpdateWidget(covariant ConflictFileDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file)) {
      _details = ConflictDetails(widget.file);
      _working = _workingEntry();
      _entries.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (_locale != locale) {
      _locale = locale;
      _entries.clear();
    }
    final l10n = context.l10n;
    final file = widget.file;
    final presence = conflictPresenceText(context, _details.presence);
    final difference = switch (_details.contentDifference) {
      ConflictContentDifference.identical => l10n.conflictContentIdentical,
      ConflictContentDifference.lineEndings => l10n.conflictContentLineEndings,
      ConflictContentDifference.finalNewline =>
        l10n.conflictContentFinalNewline,
      ConflictContentDifference.byteOrderMark => l10n.conflictContentBom,
      ConflictContentDifference.whitespace => l10n.conflictContentWhitespace,
      ConflictContentDifference.content => l10n.conflictContentDifferent,
      ConflictContentDifference.unavailable => l10n.conflictContentUnavailable,
      ConflictContentDifference.missingSide => l10n.conflictContentMissingSide,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: GitLamaLayout.conflictDetailsMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(MeridianSpace.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(presence, style: context.meridian.text.label),
              Text(difference, style: context.meridian.text.caption),
              if (_details.modeDiffers)
                Text(
                  l10n.conflictModesDiffer,
                  style: context.meridian.text.caption,
                ),
              if (file.kind == ConflictFileKind.text &&
                  (widget.markerFree ?? file.markerFree))
                Text(
                  l10n.conflictNoMarkers,
                  style: context.meridian.text.caption,
                ),
              MeridianDisclosure(
                key: ValueKey(('conflict-entry-details', file.path.join(','))),
                title: l10n.conflictEntryDetailsTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MeridianPropertyList(
                      properties: [
                        MeridianProperty(
                          label: l10n.conflictAncestor,
                          value: _entryText(context, file.ancestor),
                        ),
                        MeridianProperty(
                          label: l10n.conflictCurrentEntry,
                          value: _entryText(context, file.current),
                        ),
                        MeridianProperty(
                          label: l10n.conflictIncomingEntry,
                          value: _entryText(context, file.incoming),
                        ),
                        MeridianProperty(
                          label: l10n.conflictWorkingEntry,
                          value: _entryText(context, _working),
                        ),
                      ],
                    ),
                    const SizedBox(height: MeridianSpace.space3),
                    Text(
                      l10n.conflictPathFacts,
                      style: context.meridian.text.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _entry(
  BuildContext context,
  ConflictSide side, {
  required bool sizeKnown,
}) {
  final l10n = context.l10n;
  if (!side.present) return l10n.conflictEntryAbsent;
  final type = switch (side.mode) {
    0x81a4 => l10n.conflictEntryRegular,
    0x81ed => l10n.conflictEntryExecutable,
    0xa000 => l10n.conflictEntrySymlink,
    0xe000 => l10n.conflictEntrySubmodule,
    0x4000 => l10n.conflictEntryDirectory,
    _ => l10n.conflictEntryUnknown,
  };
  final bytes = side.content;
  final facts = l10n.conflictEntryFacts(
    type,
    side.mode?.toRadixString(8).padLeft(6, '0') ?? '—',
    sizeKnown ? side.byteCount.toString() : '—',
  );
  if (bytes == null || bytes.contains(0)) return facts;
  try {
    utf8.decode(bytes);
  } on FormatException {
    return facts;
  }
  // Byte-level facts preserve CRLF and BOM differences which normal text
  // rendering hides. No lossy decoding or reading private file contents here.
  var lf = 0;
  var crlf = 0;
  var cr = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 13) {
      if (i + 1 < bytes.length && bytes[i + 1] == 10) {
        crlf++;
        i++;
      } else {
        cr++;
      }
    } else if (bytes[i] == 10) {
      lf++;
    }
  }
  final kinds = [if (lf > 0) 'LF', if (crlf > 0) 'CRLF', if (cr > 0) 'CR'];
  final endings = kinds.isEmpty
      ? l10n.conflictNoLineBreaks
      : kinds.length == 1
      ? kinds.single
      : l10n.conflictMixedLineBreaks;
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  final finalNewline =
      bytes.isNotEmpty && (bytes.last == 10 || bytes.last == 13);
  return '$facts\n${l10n.conflictFormatFacts(endings, finalNewline ? l10n.conflictFinalNewlinePresent : l10n.conflictFinalNewlineAbsent, bom ? l10n.conflictBomPresent : l10n.conflictBomAbsent)}';
}
