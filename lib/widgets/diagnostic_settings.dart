import 'package:flutter/widgets.dart';
import 'package:devmil_logging/devmil_logging.dart';
import '../l10n/l10n.dart';
import 'package:meridian_ui/meridian_ui.dart';

class DiagnosticSettings extends StatelessWidget {
  const DiagnosticSettings({super.key});
  @override
  Widget build(BuildContext context) => DiagnosticControls(
    application: 'gitlama',
    version: const String.fromEnvironment(
      'FLUTTER_BUILD_NAME',
      defaultValue: 'unknown',
    ),
    spacing: MeridianSpace.space4,
    previewHeight: MeridianSize.toolbar * 6,
    button: (label, action) => MeridianButton(label: label, onPressed: action),
    labels: DiagnosticLabels(
      title: context.l10n.diagnosticsTitle,
      description: context.l10n.diagnosticsDescription,
      enable: context.l10n.diagnosticsEnable,
      disable: context.l10n.diagnosticsDisable,
      clear: context.l10n.diagnosticsClear,
      preview: context.l10n.diagnosticsPreview,
      cancel: context.l10n.diagnosticsCancel,
      save: context.l10n.diagnosticsSave,
      share: context.l10n.diagnosticsShare,
      failed: context.l10n.diagnosticsFailed,
      saved: context.l10n.diagnosticsSaved,
    ),
  );
}
