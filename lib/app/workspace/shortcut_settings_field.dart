import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/app_shortcut.dart';
import '../app_shortcut_activator.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

/// One command's shortcut: Meridian's recorder; validation, registration
/// and persistence stay with the settings.
class ShortcutSettingsField extends StatefulWidget {
  const ShortcutSettingsField({
    required this.label,
    required this.value,
    required this.fieldKey,
    required this.onRecorded,
    required this.onClear,
    super.key,
  });

  final String label;

  /// The canonical binding in effect, empty when unbound.
  final String value;
  final Key fieldKey;

  /// The recorded binding, or null for a key no shortcut can use.
  final ValueChanged<String?> onRecorded;
  final VoidCallback onClear;

  @override
  State<ShortcutSettingsField> createState() => _ShortcutSettingsFieldState();
}

class _ShortcutSettingsFieldState extends State<ShortcutSettingsField> {
  bool _recording = false;

  List<String> get _keys {
    if (widget.value.isEmpty) return const [];
    try {
      return platformShortcutKeys(AppShortcut.parse(widget.value));
    } on AppShortcutException {
      return [widget.value];
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(widget.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: MeridianSpace.space5),
      MeridianShortcutField(
        key: widget.fieldKey,
        width: GitLamaLayout.shortcutFieldWidth,
        showLabel: false,
        label: widget.label,
        emptyLabel: context.l10n.settingsShortcutUnbound,
        recordingLabel: context.l10n.settingsShortcutRecording,
        preparingLabel: context.l10n.settingsShortcutRecording,
        clearLabel: context.l10n.settingsShortcutClear,
        keys: _keys,
        recording: _recording,
        onRecordRequested: () => setState(() => _recording = true),
        onCancelRecording: () => setState(() => _recording = false),
        onRecorded: (stroke) {
          setState(() => _recording = false);
          widget.onRecorded(
            shortcutBinding(
              stroke.logicalKey,
              control: stroke.control,
              meta: stroke.meta,
              alt: stroke.alt,
              shift: stroke.shift,
            ),
          );
        },
        onClear: widget.onClear,
      ),
    ],
  );
}
