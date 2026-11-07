import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// A labelled choice among stored setting values.
class SettingsChoice extends StatelessWidget {
  const SettingsChoice({
    required this.label,
    required this.value,
    required this.values,
    required this.valueLabel,
    required this.onChanged,
    super.key,
    this.segmented = false,
  });

  final String label;
  final String value;
  final List<String> values;
  final String Function(String value) valueLabel;
  final ValueChanged<String> onChanged;
  final bool segmented;

  @override
  Widget build(BuildContext context) => MeridianSettingsRow(
    label: label,
    children: [
      if (segmented)
        MeridianSegmented<String>(
          label: label,
          segments: [
            for (final value in values)
              MeridianSegment(value: value, label: valueLabel(value)),
          ],
          value: values.contains(value) ? value : values.first,
          onChanged: onChanged,
        )
      else
        MeridianSelect<String>(
          value: values.contains(value) ? value : values.first,
          values: values,
          valueLabel: valueLabel,
          label: label,
          onChanged: onChanged,
        ),
    ],
  );
}

/// One command's shortcut: Meridian's recorder; validation, registration
/// and persistence stay with the settings.
