/// The pages of the settings dialog that edit stored preferences. The
/// dialog owns navigation, page headings and the save failure line; each
/// page gets the values it shows and how to change them.
library;

import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/diff.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/session/working_copy_commands.dart';
import '../../services/settings_service.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'settings_choice.dart';
import 'shortcut_settings_field.dart';
import 'status_acceleration_settings.dart';

/// Theme, density, dates, avatars, where inspection opens and which refs
/// History follows.
Widget appearanceSettingsPage(
  BuildContext context,
  AppearanceSettings appearance,
  ValueChanged<AppearanceSettings> update,
) => MeridianSettingsGroup(
  children: [
    SettingsChoice(
      key: const Key('settings-theme'),
      segmented: true,
      label: context.l10n.settingsTheme,
      value: appearance.theme,
      values: StoredAppearanceNames.themes,
      valueLabel: (value) => switch (value) {
        'light' => context.l10n.settingsThemeLight,
        'dark' => context.l10n.settingsThemeDark,
        _ => context.l10n.settingsFollowSystem,
      },
      onChanged: (value) => update(appearance.copyWith(theme: value)),
    ),
    SettingsChoice(
      key: const Key('settings-density'),
      segmented: true,
      label: context.l10n.settingsDensity,
      value: appearance.density,
      values: StoredAppearanceNames.densities,
      valueLabel: (value) => switch (value) {
        'compact' => context.l10n.settingsDensityCompact,
        'comfortable' => context.l10n.settingsDensityComfortable,
        _ => context.l10n.settingsDensityRegular,
      },
      onChanged: (value) => update(appearance.copyWith(density: value)),
    ),
    SettingsChoice(
      key: const Key('settings-date-format'),
      label: context.l10n.settingsDateFormat,
      value: appearance.dateFormat,
      values: const ['relative', 'local', 'iso'],
      valueLabel: (value) => switch (value) {
        'local' => context.l10n.settingsDateLocal,
        'iso' => context.l10n.settingsDateIso,
        _ => context.l10n.settingsDateRelative,
      },
      onChanged: (value) => update(appearance.copyWith(dateFormat: value)),
    ),
    SettingsChoice(
      key: const Key('settings-avatars'),
      label: context.l10n.settingsAvatars,
      value: appearance.gravatarEnabled ? 'gravatar' : 'initials',
      values: const ['initials', 'gravatar'],
      valueLabel: (value) => value == 'gravatar'
          ? context.l10n.settingsAvatarsGravatar
          : context.l10n.settingsAvatarsInitials,
      onChanged: (value) =>
          update(appearance.copyWith(gravatarEnabled: value == 'gravatar')),
    ),
    Text(
      context.l10n.avatarGravatarHint,
      style: context.text.caption.copyWith(color: context.colors.inkMuted),
    ),
    SettingsChoice(
      key: const Key('settings-inspection-open-in'),
      segmented: true,
      label: context.l10n.settingsInspectionOpenIn,
      value: appearance.inspectionOpenIn,
      values: StoredAppearanceNames.inspectionOpenIn,
      valueLabel: (value) => value == 'window'
          ? context.l10n.settingsInspectionOpenInWindow
          : context.l10n.settingsInspectionOpenInPane,
      onChanged: (value) =>
          update(appearance.copyWith(inspectionOpenIn: value)),
    ),
    Text(
      context.l10n.settingsInspectionOpenInDetail,
      style: context.text.caption.copyWith(color: context.colors.inkMuted),
    ),
    SettingsChoice(
      key: const Key('settings-history-other-refs'),
      segmented: true,
      label: context.l10n.settingsHistoryOtherRefs,
      value: appearance.historyOtherRefs ? 'on' : 'off',
      values: const ['on', 'off'],
      valueLabel: (value) =>
          value == 'on' ? context.l10n.settingsOn : context.l10n.settingsOff,
      onChanged: (value) =>
          update(appearance.copyWith(historyOtherRefs: value == 'on')),
    ),
    Text(
      context.l10n.settingsHistoryOtherRefsDetail,
      style: context.text.caption.copyWith(color: context.colors.inkMuted),
    ),
  ],
);

/// How every diff is shown; the diff toolbars change the same values.
Widget diffViewSettingsPage(
  BuildContext context,
  DiffViewPreferences preferences,
  ValueChanged<DiffViewPreferences> update,
) {
  String onOff(String value) =>
      value == 'on' ? context.l10n.settingsOn : context.l10n.settingsOff;
  return MeridianSettingsGroup(
    children: [
      SettingsChoice(
        key: const Key('settings-diff-layout'),
        segmented: true,
        label: context.l10n.settingsDiffLayout,
        value: preferences.layout.name,
        values: [for (final value in DiffViewLayout.values) value.name],
        valueLabel: (value) => switch (DiffViewLayout.values.byName(value)) {
          DiffViewLayout.unified => context.l10n.settingsDiffUnified,
          DiffViewLayout.sideBySide => context.l10n.settingsDiffSideBySide,
        },
        onChanged: (value) => update(
          preferences.copyWith(layout: DiffViewLayout.values.byName(value)),
        ),
      ),
      SettingsChoice(
        key: const Key('settings-diff-wrap'),
        segmented: true,
        label: context.l10n.settingsDiffWrap,
        value: preferences.wrap ? 'wrap' : 'scroll',
        values: const ['wrap', 'scroll'],
        valueLabel: (value) => value == 'wrap'
            ? context.l10n.settingsDiffWrapOn
            : context.l10n.settingsDiffWrapOff,
        onChanged: (value) =>
            update(preferences.copyWith(wrap: value == 'wrap')),
      ),
      SettingsChoice(
        key: const Key('settings-diff-whitespace'),
        label: context.l10n.settingsDiffWhitespace,
        value: preferences.whitespace.name,
        values: [for (final value in DiffWhitespace.values) value.name],
        valueLabel: (value) => switch (DiffWhitespace.values.byName(value)) {
          DiffWhitespace.preserve =>
            context.l10n.settingsDiffWhitespacePreserve,
          DiffWhitespace.ignoreAll =>
            context.l10n.settingsDiffWhitespaceIgnoreAll,
          DiffWhitespace.ignoreAmount =>
            context.l10n.settingsDiffWhitespaceIgnoreAmount,
          DiffWhitespace.ignoreEndOfLine =>
            context.l10n.settingsDiffWhitespaceIgnoreEndOfLine,
        },
        onChanged: (value) => update(
          preferences.copyWith(whitespace: DiffWhitespace.values.byName(value)),
        ),
      ),
      SettingsChoice(
        key: const Key('settings-diff-context'),
        label: context.l10n.diffContextLines,
        value: '${preferences.contextLines}',
        values: [
          for (final lines in {
            ...DiffViewPreferences.contextChoices,
            preferences.contextLines,
          }.toList()..sort())
            '$lines',
        ],
        valueLabel: (value) => context.l10n.diffContextValue(int.parse(value)),
        onChanged: (value) =>
            update(preferences.copyWith(contextLines: int.parse(value))),
      ),
      SettingsChoice(
        key: const Key('settings-diff-indicators'),
        segmented: true,
        label: context.l10n.settingsDiffIndicators,
        value: preferences.showIndicators ? 'on' : 'off',
        values: const ['on', 'off'],
        valueLabel: onOff,
        onChanged: (value) =>
            update(preferences.copyWith(showIndicators: value == 'on')),
      ),
      SettingsChoice(
        key: const Key('settings-diff-minimap'),
        segmented: true,
        label: context.l10n.settingsDiffMinimap,
        value: preferences.showMinimap ? 'on' : 'off',
        values: const ['on', 'off'],
        valueLabel: onOff,
        onChanged: (value) =>
            update(preferences.copyWith(showMinimap: value == 'on')),
      ),
    ],
  );
}

/// Automatic fetching, here and per repository, and the repository reset.
Widget gitSettingsPage(
  BuildContext context, {
  required SettingsService settings,
  required WorkingCopyCommands workingCopy,
  required AutoFetchSettings autoFetch,
  required RepositoryTabState? repository,
  required ValueChanged<AutoFetchSettings> updateAutoFetch,
  required void Function(NativePathIdentity repository, bool? value)
  updateRepositoryAutoFetch,
  required VoidCallback onResetRepository,
  required FocusNode resetFocus,
}) => MeridianSettingsGroup(
  children: [
    SettingsChoice(
      key: const Key('settings-auto-fetch'),
      segmented: true,
      label: context.l10n.settingsAutoFetch,
      value: autoFetch.enabled ? 'on' : 'off',
      values: const ['on', 'off'],
      valueLabel: (value) =>
          value == 'on' ? context.l10n.settingsOn : context.l10n.settingsOff,
      onChanged: (value) =>
          updateAutoFetch(autoFetch.copyWith(enabled: value == 'on')),
    ),
    SettingsChoice(
      key: const Key('settings-auto-fetch-interval'),
      label: context.l10n.settingsAutoFetchInterval,
      value: '${autoFetch.intervalMinutes}',
      values: [
        for (final minutes in {
          ...AutoFetchSettings.intervals,
          autoFetch.intervalMinutes,
        }.toList()..sort())
          '$minutes',
      ],
      valueLabel: (value) =>
          context.l10n.settingsAutoFetchMinutes(int.parse(value)),
      onChanged: (value) => updateAutoFetch(
        autoFetch.copyWith(intervalMinutes: int.parse(value)),
      ),
    ),
    Text(
      context.l10n.settingsAutoFetchHint,
      style: context.text.caption.copyWith(color: context.colors.inkMuted),
    ),
    if (repository case final repository?) ...[
      Text(context.l10n.settingsActiveRepository(repository.label)),
      if (repository.canonicalIdentity case final identity?)
        SettingsChoice(
          key: const Key('settings-repository-auto-fetch'),
          label: context.l10n.settingsRepositoryAutoFetch,
          value: switch (settings.current.autoFetchOverride(identity)) {
            true => 'on',
            false => 'off',
            null => 'default',
          },
          values: const ['default', 'on', 'off'],
          valueLabel: (value) => switch (value) {
            'on' => context.l10n.settingsOn,
            'off' => context.l10n.settingsOff,
            _ => context.l10n.settingsFollowApplication,
          },
          onChanged: (value) =>
              updateRepositoryAutoFetch(identity, switch (value) {
                'on' => true,
                'off' => false,
                _ => null,
              }),
        ),
      const SizedBox(height: MeridianSpace.space5),
      MeridianButton(
        key: const Key('settings-reset-repository'),
        focusNode: resetFocus,
        variant: MeridianButtonVariant.secondary,
        onPressed: repository.canonicalIdentity == null
            ? null
            : onResetRepository,
        label: context.l10n.settingsResetRepositoryAction,
      ),
      if (repository.session?.identity case final identity?) ...[
        const SizedBox(height: MeridianSpace.space5),
        StatusAccelerationSettings(
          key: ValueKey((
            'status-acceleration',
            identity.nativeId,
            identity.generation,
          )),
          workingCopy: workingCopy,
          identity: identity,
        ),
      ],
    ] else
      Text(context.l10n.settingsNoActiveRepository),
  ],
);

/// Every command's shortcut, editable, and a reset to the defaults.
Widget shortcutSettingsPage(
  BuildContext context, {
  required Map<AppCommandId, String?> shortcutLabels,
  required VoidCallback onReset,
  required void Function(AppCommandId command, String binding) updateShortcut,
  required VoidCallback onInvalid,
}) => MeridianSettingsGroup(
  children: [
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: MeridianButton(
        key: const Key('settings-shortcuts-reset'),
        variant: MeridianButtonVariant.secondary,
        onPressed: onReset,
        label: context.l10n.settingsShortcutReset,
      ),
    ),
    for (final command in AppCommandRegistry.commands)
      ShortcutSettingsField(
        key: ValueKey(
          'settings-shortcut-${command.id.name}-${shortcutLabels[command.id]}',
        ),
        label: commandLabel(context, command.id),
        value: shortcutLabels[command.id] ?? '',
        fieldKey: Key('settings-shortcut-${command.id.name}'),
        onRecorded: (binding) =>
            binding == null ? onInvalid() : updateShortcut(command.id, binding),
        onClear: () => updateShortcut(command.id, ''),
      ),
  ],
);

/// Motion.
Widget accessibilitySettingsPage(
  BuildContext context,
  AppearanceSettings appearance,
  ValueChanged<AppearanceSettings> update,
) => MeridianSettingsGroup(
  children: [
    SettingsChoice(
      key: const Key('settings-reduce-motion'),
      label: context.l10n.settingsMotion,
      value: appearance.reduceMotion,
      values: StoredAppearanceNames.reduceMotion,
      valueLabel: (value) => switch (value) {
        'reduce' => context.l10n.settingsMotionReduce,
        'full' => context.l10n.settingsMotionFull,
        _ => context.l10n.settingsFollowSystem,
      },
      onChanged: (value) => update(appearance.copyWith(reduceMotion: value)),
    ),
  ],
);
