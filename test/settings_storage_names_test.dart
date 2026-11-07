import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_update.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';

/// The Rust settings store validates these names independently. Both sides
/// read the same fixture, so a value one side writes is one the other accepts.
void main() {
  final names =
      jsonDecode(
            File(
              'test/fixtures/settings_storage_names.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('hosting names match the names the native store accepts', () {
    expect(
      HostingPreset.values.map((value) => value.storageName),
      names['presets'],
    );
    expect(
      HostingAuthentication.values.map((value) => value.storageName),
      names['authentications'],
    );
  });

  test('appearance names match the names the native store accepts', () {
    expect(StoredAppearanceNames.themes, names['themes']);
    expect(StoredAppearanceNames.densities, names['densities']);
    expect(StoredAppearanceNames.reduceMotion, names['reduceMotion']);
    expect(StoredAppearanceNames.fileLayouts, names['fileLayouts']);
    expect(StoredAppearanceNames.inspectionOpenIn, names['inspectionOpenIn']);
    const defaults = AppearanceSettings();
    expect(names['themes'], contains(defaults.theme));
    expect(names['densities'], contains(defaults.density));
    expect(names['reduceMotion'], contains(defaults.reduceMotion));
    expect(names['fileLayouts'], contains(defaults.changesUnstagedMode));
    expect(names['fileLayouts'], contains(defaults.changesStagedMode));
    expect(names['fileLayouts'], contains(defaults.commitFilesMode));
    expect(names['inspectionOpenIn'], contains(defaults.inspectionOpenIn));
    expect(
      DiffViewLayout.values.map((value) => value.name),
      names['diffLayouts'],
    );
    expect(
      DiffWhitespace.values.map((value) => value.name),
      names['diffWhitespace'],
    );
  });

  test(
    'enum names stored by name match the names the native store accepts',
    () {
      expect(
        ReleaseChannel.values.map((value) => value.name),
        names['releaseChannels'],
      );
      expect(
        IntegrationKind.values.map((value) => value.name),
        names['integrationKinds'],
      );
      expect(
        WorkspacePane.values.map((value) => value.name),
        names['worktreePanes'],
      );
      expect(
        WorkspaceRoute.values.map((value) => value.name),
        names['worktreeRoutes'],
      );
    },
  );
}
