import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

class GitLamaSelectOption<T> {
  const GitLamaSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// A searchable form picker. Action and context menus use NativeMenuButton.
class GitLamaSelectionField<T> extends StatefulWidget {
  const GitLamaSelectionField({
    required this.label,
    required this.icon,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    super.key,
    this.helperText,
    this.labelAbove = false,
  });

  final String label;
  final String icon;
  final T? initialValue;
  final List<GitLamaSelectOption<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? helperText;
  final bool labelAbove;

  @override
  State<GitLamaSelectionField<T>> createState() =>
      _GitLamaSelectionFieldState<T>();
}

class _GitLamaSelectionFieldState<T> extends State<GitLamaSelectionField<T>> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  T? _selected;

  String _labelOf(GitLamaSelectOption<T> item) => item.label;

  String _selectedLabel() {
    for (final item in widget.items) {
      if (item.value == _selected) return _labelOf(item);
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
    _controller.text = _selectedLabel();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant GitLamaSelectionField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue ||
        widget.items != oldWidget.items) {
      _selected = widget.initialValue;
      if (!_focus.hasFocus) _controller.text = _selectedLabel();
    }
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _controller.clear();
    } else {
      _controller.text = _selectedLabel();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<GitLamaSelectOption<T>>(
    textEditingController: _controller,
    focusNode: _focus,
    displayStringForOption: _labelOf,
    optionsBuilder: (query) {
      final needle = query.text.toLowerCase();
      return widget.items.where(
        (item) => item.enabled && _labelOf(item).toLowerCase().contains(needle),
      );
    },
    onSelected: (item) {
      _selected = item.value;
      widget.onChanged?.call(item.value);
    },
    fieldViewBuilder: (context, controller, focus, submit) => MeridianTextField(
      controller: controller,
      focusNode: focus,
      label: widget.label,
      icon: widget.icon,
      message: widget.helperText,
      enabled: widget.onChanged != null,
      trailing: MeridianIconButton(
        label: widget.label,
        icon: 'chevron-down',
        size: MeridianControlSize.small,
        onPressed: widget.onChanged == null
            ? null
            : () {
                if (!focus.hasFocus) focus.requestFocus();
                controller.clear();
              },
      ),
      onSubmitted: (_) => submit(),
    ),
    optionsViewBuilder: (context, select, options) {
      final rows = options.toList();
      return Align(
        alignment: Alignment.topLeft,
        child: MeridianSuggestionSurface(
          maxHeight: MeridianLayout.suggestionMaxHeight,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, index) => MeridianSuggestionRow(
              label: _labelOf(rows[index]),
              icon: widget.icon,
              highlighted: AutocompleteHighlightedOption.of(context) == index,
              onTap: () => select(rows[index]),
            ),
          ),
        ),
      );
    },
  );
}
