import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/hosting.dart';
import '../services/hosting_connection_service.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

final class HostingReferenceTextField extends StatefulWidget {
  const HostingReferenceTextField({
    required this.controller,
    this.label,
    this.placeholder,
    this.error,
    this.message,
    this.trailing,
    this.trailingWidget,
    required this.hosting,
    required this.references,
    required this.stale,
    this.enabled = true,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.expands = false,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.onSubmitted,
    this.inputFormatters,
    this.spellCheckConfiguration,
    this.style,
    this.height,
    this.programmaticClearSequence = 0,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? placeholder;
  final String? error;
  final String? message;
  final String? trailing;
  final Widget? trailingWidget;
  final HostingConnectionService? hosting;
  final List<HostingRemoteReference> references;
  final bool stale;
  final bool enabled;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final TextStyle? style;
  final double? height;
  final int programmaticClearSequence;

  @override
  State<HostingReferenceTextField> createState() =>
      _HostingReferenceTextFieldState();
}

class _HostingReferenceTextFieldState extends State<HostingReferenceTextField> {
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _ownedFocusNode = FocusNode();
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
  OverlayEntry? _overlay;
  HostingReferenceProjection? _projection;
  TextSelection? _restoreSelection;
  Offset _caretOffset = Offset.zero;
  var _selected = 0;
  var _revision = 0;
  var _request = 0;
  var _applying = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_textChanged);
    _focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant HostingReferenceTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode).removeListener(_focusChanged);
      _focusNode.addListener(_focusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
      _revision += 1;
      _close();
    }
    if (oldWidget.references != widget.references ||
        oldWidget.stale != widget.stale ||
        oldWidget.hosting != widget.hosting) {
      _project();
    }
  }

  void _focusChanged() {
    if (!_focusNode.hasFocus) _close();
  }

  void _textChanged() {
    if (_applying) return;
    _revision += 1;
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      _close();
      return;
    }
    _project();
  }

  Future<void> _project() async {
    final hosting = widget.hosting;
    final value = widget.controller.value;
    if (hosting == null || !_focusNode.hasFocus || !value.selection.isValid) {
      _close();
      return;
    }
    final request = ++_request;
    final revision = _revision;
    try {
      final projection = await hosting.projectReference(
        text: value.text,
        selectionBase: value.selection.baseOffset,
        selectionExtent: value.selection.extentOffset,
        revision: revision,
        references: widget.references,
        stale: widget.stale,
      );
      if (!mounted ||
          request != _request ||
          revision != _revision ||
          !_focusNode.hasFocus) {
        return;
      }
      if (projection == null) {
        _close();
        return;
      }
      _projection = projection;
      _restoreSelection = widget.controller.selection;
      _selected = _selected.clamp(
        0,
        projection.candidates.isEmpty ? 0 : projection.candidates.length - 1,
      );
      _show();
    } on HostingReferenceException {
      if (mounted && request == _request) _close();
    }
  }

  void _show() {
    final overlay = Overlay.of(context);
    final existing = _overlay;
    if (existing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _overlay != existing) return;
        _updateCaretOffset();
        existing.markNeedsBuild();
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _projection == null || _overlay != null) return;
      _updateCaretOffset();
      final entry = OverlayEntry(builder: _buildOverlay);
      _overlay = entry;
      overlay.insert(entry);
    });
  }

  void _updateCaretOffset() {
    final root = _fieldKey.currentContext?.findRenderObject();
    if (root is! RenderBox) return;
    final editable = _findEditable(root);
    if (editable == null) return;
    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    final rect = editable.getLocalRectForCaret(
      TextPosition(offset: selection.extentOffset),
    );
    final global = editable.localToGlobal(rect.bottomLeft);
    final local = root.globalToLocal(global);
    final width = root.size.width.clamp(180.0, 360.0);
    _caretOffset = Offset(
      local.dx.clamp(
        0.0,
        (root.size.width - width).clamp(0.0, double.infinity),
      ),
      local.dy + 4,
    );
  }

  RenderEditable? _findEditable(RenderObject root) {
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findEditable(child);
    });
    return result;
  }

  Widget _buildOverlay(BuildContext context) {
    final projection = _projection;
    if (projection == null) return const SizedBox.shrink();
    final field = _fieldKey.currentContext?.findRenderObject();
    final width = field is RenderBox
        ? field.size.width.clamp(
            GitLamaLayout.referenceSuggestionMinWidth,
            GitLamaLayout.referenceSuggestionMaxWidth,
          )
        : GitLamaLayout.referenceSuggestionMaxWidth;
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      offset: _caretOffset,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: MeridianSuggestionSurface(
            child: projection.candidates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(MeridianSpace.space5),
                    child: Text(context.l10n.hostingReferenceEmpty),
                  )
                : ListView.builder(
                    key: const Key('hosting-reference-results'),
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: projection.candidates.length,
                    itemBuilder: (context, index) {
                      final candidate = projection.candidates[index];
                      return MeridianSuggestionRow(
                        key: ValueKey(
                          'hosting-reference-${candidate.stableId}',
                        ),
                        highlighted: index == _selected,
                        icon: 'cloud',
                        label: candidate.insertion,
                        hint: candidate.stale
                            ? context.l10n.hostingStale
                            : candidate.title,
                        onTap: () => unawaited(_apply(candidate)),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _keyEvent(FocusNode node, KeyEvent event) {
    final projection = _projection;
    if (event is! KeyDownEvent || _overlay == null || projection == null) {
      return KeyEventResult.ignored;
    }
    final count = projection.candidates.length;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      final selection = _restoreSelection;
      _close();
      if (selection != null) {
        final limit = widget.controller.text.length;
        widget.controller.selection = TextSelection(
          baseOffset: selection.baseOffset.clamp(0, limit),
          extentOffset: selection.extentOffset.clamp(0, limit),
        );
      }
      return KeyEventResult.handled;
    }
    if (count == 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_apply(projection.candidates[_selected]));
      return KeyEventResult.handled;
    }
    final delta = switch (key) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.pageDown => 5,
      LogicalKeyboardKey.pageUp => -5,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    _selected = (_selected + delta).clamp(0, count - 1);
    _overlay?.markNeedsBuild();
    return KeyEventResult.handled;
  }

  Future<void> _apply(HostingReferenceCandidate candidate) async {
    final hosting = widget.hosting;
    final projection = _projection;
    if (hosting == null || projection == null) return;
    try {
      final result = await hosting.applyReference(
        text: widget.controller.text,
        currentRevision: _revision,
        projection: projection,
        insertion: candidate.insertion,
      );
      if (!mounted || result.failure != null) {
        _close();
        return;
      }
      _applying = true;
      widget.controller.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.caret),
      );
      _revision += 1;
      _applying = false;
      _close();
      _focusNode.requestFocus();
    } on HostingReferenceException {
      if (mounted) _close();
    } finally {
      _applying = false;
    }
  }

  void _close() {
    _request += 1;
    _projection = null;
    _restoreSelection = null;
    _selected = 0;
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_textChanged);
    _focusNode.removeListener(_focusChanged);
    _ownedFocusNode.dispose();
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _keyEvent,
    child: CompositedTransformTarget(
      link: _link,
      child: MeridianTextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        maxLength: widget.maxLength,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        expands: widget.expands,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        inputFormatters: widget.inputFormatters,
        spellCheckConfiguration: widget.spellCheckConfiguration,
        label: widget.label,
        placeholder: widget.placeholder,
        error: widget.error,
        message: widget.message,
        trailingText: widget.trailing,
        trailing: widget.trailingWidget,
        height: widget.height,
        textStyle: widget.style,
        programmaticClearSequence: widget.programmaticClearSequence,
      ),
    ),
  );
}
