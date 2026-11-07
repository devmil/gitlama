import 'dart:math' as math;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reference_name.dart';
import '../models/repository_state.dart';
import '../models/history.dart';
import '../l10n/app_localizations.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';
import '../models/git_names.dart';

List<String> gitBranchNames(RepositoryRefs refs) => [
  for (final branch in refs.branches)
    utf8.decode(branch.name, allowMalformed: true),
  for (final remote in refs.remotes)
    for (final branch in remote.branches)
      '${utf8.decode(remote.name, allowMalformed: true)}/${utf8.decode(branch.name, allowMalformed: true)}',
];

List<String> gitBranchNameSuggestions(RepositoryRefs refs) => [
  for (final branch in refs.branches)
    utf8.decode(branch.name, allowMalformed: true),
  for (final remote in refs.remotes)
    for (final branch in remote.branches)
      utf8.decode(branch.name, allowMalformed: true),
];

List<String> gitReferenceNames(RepositoryRefs refs) => [
  'HEAD',
  ...gitBranchNames(refs),
  for (final tag in refs.tags) utf8.decode(tag.name, allowMalformed: true),
];

class GitReferenceChoice {
  const GitReferenceChoice(
    this.value, {
    this.description = '',
    this.icon = 'branch',
  });
  final String value;
  final String description;
  final String icon;
}

List<GitReferenceChoice> gitReferenceChoices(
  RepositoryRefs refs,
  Iterable<HistoryTopologyRow> commits,
) => [
  const GitReferenceChoice('HEAD', icon: 'locate'),
  for (final branch in refs.branches)
    GitReferenceChoice(
      utf8.decode(branch.name, allowMalformed: true),
      description: branch.target,
    ),
  for (final remote in refs.remotes)
    for (final branch in remote.branches)
      GitReferenceChoice(
        '${utf8.decode(remote.name, allowMalformed: true)}/${utf8.decode(branch.name, allowMalformed: true)}',
        description: branch.target,
        icon: 'cloud',
      ),
  for (final tag in refs.tags)
    GitReferenceChoice(
      utf8.decode(tag.name, allowMalformed: true),
      description: tag.target,
      icon: 'tag',
    ),
  for (final commit in commits)
    if (!commit.isWorktree)
      GitReferenceChoice(
        commit.objectId,
        description: utf8.decode(commit.subject, allowMalformed: true),
        icon: 'git-commit-horizontal',
      ),
];

/// Matches QSpline's branch-name typing assistance. Git remains the validator.
class GitRefNameFormatter extends TextInputFormatter {
  const GitRefNameFormatter();

  static String normalize(String value) => value
      .replaceAll(RegExp(r'[\x00-\x20\x7f~^:?*\[\\]'), '-')
      .replaceAll('@{', '@-')
      .replaceAll('..', '.-');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    return newValue.copyWith(text: normalize(newValue.text));
  }
}

/// A keyboard-accessible suggestion popup anchored to a desktop form field.
class GitReferenceField extends StatefulWidget {
  const GitReferenceField({
    required this.controller,
    required this.label,
    required this.names,
    this.autofocus = false,
    this.normalize = false,
    this.suggestSegments = false,
    this.suggestions = true,
    this.choices = const [],
    this.onChanged,
    this.helperText,
    this.fieldKey,
    this.onSubmitted,
    this.compact = false,
    this.selectionIcon = 'branch',
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final List<String> names;
  final bool autofocus;
  final bool normalize;
  final bool suggestSegments;
  final bool suggestions;
  final List<GitReferenceChoice> choices;
  final ValueChanged<String>? onChanged;
  final String? helperText;
  final Key? fieldKey;
  final ValueChanged<String>? onSubmitted;
  final bool compact;
  final String selectionIcon;

  @override
  State<GitReferenceField> createState() => _GitReferenceFieldState();
}

class _GitReferenceFieldState extends State<GitReferenceField> {
  final _focus = FocusNode();
  late Map<String, GitReferenceChoice> _choiceByValue = {
    for (final choice in widget.choices) choice.value: choice,
  };

  @override
  void didUpdateWidget(covariant GitReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.choices, oldWidget.choices)) {
      _choiceByValue = {
        for (final choice in widget.choices) choice.value: choice,
      };
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<String> get _names => {
    ...widget.names,
    ...widget.choices.map((choice) => choice.value),
  }.toList();

  GitReferenceChoice _choice(String name) =>
      _choiceByValue[name] ?? GitReferenceChoice(name);

  Future<void> _browse() async {
    final selected = await showMeridianDialog<String>(
      context: context,
      builder: (context) => _ReferencePickerDialog(
        label: widget.label,
        choices: [for (final name in _names) _choice(name)],
      ),
    );
    if (!mounted || selected == null) return;
    widget.controller.value = TextEditingValue(
      text: selected,
      selection: TextSelection.collapsed(offset: selected.length),
    );
    widget.onChanged?.call(selected);
    _focus.requestFocus();
  }

  Iterable<String> _options(TextEditingValue value) {
    if (!widget.suggestions || !value.composing.isCollapsed) return const [];
    if (!widget.suggestSegments) {
      if (_names.contains(value.text)) return const [];
      return _names
          .where(
            (name) => '$name ${_choice(name).description}'
                .toLowerCase()
                .contains(value.text.toLowerCase()),
          )
          .toSet();
    }
    final cursor = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final prefix = value.text.substring(0, cursor);
    if (prefix.isEmpty) return const [];
    final slash = prefix.lastIndexOf('/');
    final parent = prefix.substring(0, slash + 1);
    final partial = prefix.substring(slash + 1).toLowerCase();
    final nextSlash = value.text.indexOf('/', cursor);
    final suffix = nextSlash < 0 ? '' : value.text.substring(nextSlash);
    final options = <String>{};
    for (final original in widget.names) {
      final name = _branchPath(original);
      if (!name.startsWith(parent)) continue;
      final segment = name.substring(parent.length).split('/').first;
      if (segment.toLowerCase().startsWith(partial)) {
        options.add('$parent$segment$suffix');
      }
    }
    // Offering what is already typed would make Enter a no-op pick.
    options.remove(value.text);
    return options.toList()..sort();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    onSelected: widget.onChanged,
    focusNode: _focus,
    optionsBuilder: _options,
    fieldViewBuilder: (context, controller, focus, submit) => MeridianTextField(
      fieldKey: widget.fieldKey,
      controller: controller,
      focusNode: focus,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
      inputFormatters: widget.normalize ? [const GitRefNameFormatter()] : null,
      onSubmitted: (value) {
        final before = controller.text;
        submit();
        final picked = controller.text != before;
        // Enter ends editing and drops focus; picking a suggestion, or a
        // dialog submit that may be rejected, keeps the person in the field.
        if (picked || widget.onSubmitted == null) focus.requestFocus();
        if (widget.onSubmitted case final onSubmitted?) {
          onSubmitted(value);
        } else if (!picked) {
          // Enter that did not pick a suggestion submits the dialog.
          MeridianDialogSubmitScope.maybeOf(context, listen: false)?.call();
        }
      },
      label: widget.compact ? null : widget.label,
      placeholder: widget.compact ? widget.label : null,
      icon: widget.selectionIcon,
      size: widget.compact
          ? MeridianControlSize.small
          : MeridianControlSize.regular,
      width: widget.compact ? MeridianLayout.selectMinWidth : null,
      message: widget.helperText,
      trailing:
          widget.suggestions && !widget.suggestSegments && _names.isNotEmpty
          ? MeridianIconButton(
              label: AppLocalizations.of(context).referencePickerTitle,
              icon: 'chevron-down',
              size: MeridianControlSize.small,
              onPressed: _browse,
            )
          : null,
    ),
    optionsViewBuilder: (context, select, options) {
      final rows = options.toList();
      return Align(
        alignment: Alignment.topLeft,
        child: MeridianSuggestionSurface(
          maxHeight: GitLamaLayout.gitSuggestionMaxHeight,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final highlighted =
                  AutocompleteHighlightedOption.of(context) == index;
              if (highlighted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    Scrollable.ensureVisible(context, alignment: 0.5);
                  }
                });
              }
              final choice = _choice(rows[index]);
              return MeridianSuggestionRow(
                label: rows[index],
                hint: choice.description.isEmpty ? null : choice.description,
                icon: choice.icon,
                highlighted: highlighted,
                onTap: () => select(rows[index]),
              );
            },
          ),
        ),
      );
    },
  );
}

class _ReferencePickerDialog extends StatefulWidget {
  const _ReferencePickerDialog({required this.label, required this.choices});
  final String label;
  final List<GitReferenceChoice> choices;
  @override
  State<_ReferencePickerDialog> createState() => _ReferencePickerDialogState();
}

class _ReferencePickerDialogState extends State<_ReferencePickerDialog> {
  String _query = '';
  int _highlighted = 0;

  String? _groupTitle(AppLocalizations l10n, String icon) => switch (icon) {
    'branch' => l10n.workspaceBranches,
    'cloud' => l10n.workspaceRemotes,
    'tag' => l10n.workspaceTags,
    'git-commit-horizontal' => l10n.workspaceHistory,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = widget.choices
        .where(
          (choice) => '${choice.value} ${choice.description}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    final groups = {
      for (final row in rows) ?_groupTitle(l10n, row.icon),
    }.length;
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: widget.label,
      content: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
            () => _highlighted = (_highlighted + 1).clamp(
              0,
              rows.isEmpty ? 0 : rows.length - 1,
            ),
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(
            () => _highlighted = (_highlighted - 1).clamp(
              0,
              rows.isEmpty ? 0 : rows.length - 1,
            ),
          ),
        },
        child: SizedBox(
          // The search field, then up to eight rows and their group titles.
          height: math.min(
            MediaQuery.sizeOf(context).height * 0.5,
            MeridianSize.control +
                MeridianSpace.space5 +
                MediaQuery.textScalerOf(context).scale(
                  rows.length.clamp(1, 8) * context.meridian.density.rowExtent +
                      groups * MeridianLayout.navSectionHeight,
                ),
          ),
          child: Column(
            children: [
              MeridianTextField(
                autofocus: true,
                placeholder: l10n.referencePickerSearch,
                variant: MeridianTextFieldVariant.search,
                clearLabel: l10n.searchClear,
                onChanged: (value) => setState(() {
                  _query = value;
                  _highlighted = 0;
                }),
                onSubmitted: (_) {
                  if (rows.isNotEmpty) {
                    Navigator.pop(context, rows[_highlighted].value);
                  }
                },
              ),
              const SizedBox(height: MeridianSpace.space5),
              Expanded(
                child: rows.isEmpty
                    ? MeridianEmptyState(
                        compact: true,
                        title: l10n.referencePickerEmpty,
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          if (index == _highlighted) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) {
                                Scrollable.ensureVisible(
                                  context,
                                  alignment: 0.5,
                                );
                              }
                            });
                          }
                          final group = _groupTitle(l10n, rows[index].icon);
                          final startsGroup =
                              group != null &&
                              (index == 0 ||
                                  rows[index - 1].icon != rows[index].icon);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (startsGroup) MeridianSuggestionHeader(group),
                              MeridianSuggestionRow(
                                highlighted: index == _highlighted,
                                icon: rows[index].icon,
                                label: rows[index].value,
                                hint: rows[index].description.isEmpty
                                    ? null
                                    : rows[index].description,
                                onTap: () =>
                                    Navigator.pop(context, rows[index].value),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// Restricts workflows that require a branch identity to an existing branch.
class GitBranchSelector extends StatefulWidget {
  const GitBranchSelector({
    required this.branches,
    required this.selected,
    required this.label,
    required this.onChanged,
    super.key,
  });
  final List<RepositoryReference> branches;
  final RepositoryReference? selected;
  final String label;
  final ValueChanged<RepositoryReference?> onChanged;
  @override
  State<GitBranchSelector> createState() => _GitBranchSelectorState();
}

class _GitBranchSelectorState extends State<GitBranchSelector> {
  late final _controller = TextEditingController(
    text: widget.selected == null
        ? ''
        : utf8.decode(widget.selected!.name, allowMalformed: true),
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GitReferenceField(
    controller: _controller,
    label: widget.label,
    names: [
      for (final branch in widget.branches)
        utf8.decode(branch.name, allowMalformed: true),
    ],
    choices: [
      for (final branch in widget.branches)
        GitReferenceChoice(
          utf8.decode(branch.name, allowMalformed: true),
          description: branch.target,
        ),
    ],
    onChanged: (value) => widget.onChanged(
      widget.branches.where((branch) => nameIs(branch.name, value)).firstOrNull,
    ),
  );
}

/// [reference] without `refs/heads/`, or without `refs/remotes/<remote>/`
/// for a remote-tracking branch; anything else unchanged.
String _branchPath(String reference) {
  final name = ReferenceName.parse(reference);
  return switch (name.kind) {
    ReferenceKind.localBranch => name.display,
    ReferenceKind.remoteBranch => switch (name.display.indexOf('/')) {
      final slash when slash >= 0 => name.display.substring(slash + 1),
      _ => name.display,
    },
    _ => reference,
  };
}
