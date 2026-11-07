import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_update.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_settings_repository.dart';

void main() {
  test('a rejected scoped save restores only its own section', () async {
    final repository = FakeSettingsRepository();
    final settings = SettingsService(repository);
    await settings.initialize();
    repository
      ..saveFailure = StateError('disk full')
      ..saveBarrier = Completer<void>();
    final saving = settings.updateDurable(
      (document) => document.copyWith(releaseChannel: ReleaseChannel.beta),
      restore: (current, previous) => current.copyWith(
        releaseChannel: previous.releaseChannel,
        clearReleaseChannel: previous.releaseChannel == null,
      ),
    );
    // Another part of the application changes its own section meanwhile.
    settings.updateAppearance(
      (appearance) => appearance.copyWith(theme: 'dark'),
    );
    repository.saveBarrier!.complete();
    await expectLater(saving, throwsStateError);
    expect(settings.current.releaseChannel, isNull);
    expect(settings.current.appearance.theme, 'dark');
    repository.saveFailure = null;
    await settings.dispose();
  });
}
