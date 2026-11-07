import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../app_theme.dart';
import '../../models/settings.dart';

/// Whether every word of [query] occurs in [text], ignoring case. An empty
/// query matches everything.
bool recentRepositoryMatches(String query, String text) {
  final haystack = text.toLowerCase();
  return query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .every(haystack.contains);
}

/// The recent repositories under a filter field: rows whose name or
/// location contains every typed word. Enter opens the first one shown.
class RecentRepositoryList extends StatefulWidget {
  const RecentRepositoryList({
    required this.recents,
    required this.searchText,
    required this.rowBuilder,
    this.onSubmit,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<NativePathIdentity> recents;

  /// What the filter searches for [identity]: the text its row shows.
  final String Function(NativePathIdentity identity) searchText;

  /// The row of [identity]; [query] is what to highlight.
  final Widget Function(
    BuildContext context,
    NativePathIdentity identity,
    String query,
  )
  rowBuilder;

  /// Opens a recent repository; null while none can be opened.
  final ValueChanged<NativePathIdentity>? onSubmit;

  /// Around the filter field and the empty-filter message.
  final EdgeInsetsGeometry padding;

  @override
  State<RecentRepositoryList> createState() => _RecentRepositoryListState();
}

class _RecentRepositoryListState extends State<RecentRepositoryList> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.text.trim();
    final shown = [
      for (final identity in widget.recents)
        if (recentRepositoryMatches(query, widget.searchText(identity)))
          identity,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: widget.padding,
          child: MeridianTextField(
            fieldKey: const ValueKey('recent-repositories-filter'),
            controller: _query,
            variant: MeridianTextFieldVariant.search,
            label: l10n.recentRepositoriesFilter,
            showLabel: false,
            placeholder: l10n.recentRepositoriesFilter,
            clearLabel: l10n.searchClear,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              final first = shown.firstOrNull;
              if (first != null) widget.onSubmit?.call(first);
            },
          ),
        ),
        const SizedBox(height: MeridianSpace.space3),
        if (shown.isEmpty)
          Padding(
            padding: widget.padding,
            child: Text(
              l10n.recentRepositoriesNoMatch,
              style: context.text.body.copyWith(
                color: MeridianTheme.of(context).colors.inkMuted,
              ),
            ),
          ),
        for (final identity in shown)
          widget.rowBuilder(context, identity, query),
      ],
    );
  }
}
