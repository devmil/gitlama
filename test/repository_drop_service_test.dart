import 'package:gitlama/widgets/status_notification.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/home_screen.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_drop.dart';
import 'package:gitlama/repositories/repository_drop_repository.dart';
import 'package:gitlama/services/repository_drop_service.dart';
import 'package:gitlama/services/operation_center_service.dart';

import 'support/inert_runtime.dart';
import 'support/fake_recovery_repository.dart';
import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

void main() {
  test(
    'folder drops open ordered tabs and publish only sanitized counts',
    () async {
      final repository = _FakeRepositoryDropRepository();
      final sessions = fakeRepositorySessionService();
      final service = RepositoryDropService(repository, sessions);
      await service.initialize();

      final outcomeFuture = service.outcomes.first;
      final dragFuture = service.dragStates.first;
      repository.emit(const RepositoryDropEvent.entered());
      expect(await dragFuture, isTrue);
      repository.emit(
        const RepositoryDropEvent.dropped(
          directories: ['/work/first', '/work/second'],
          rejectedItems: 2,
        ),
      );
      final outcome = await outcomeFuture;

      expect(sessions.workspace.tabs.map((tab) => tab.label), [
        'first',
        'second',
      ]);
      expect(sessions.workspace.activeTab?.label, 'second');
      expect(outcome.openedRepositories, 2);
      expect(outcome.rejectedItems, 2);
      expect(outcome.failedDirectories, 0);
      expect(service.dragging, isFalse);

      await service.dispose();
      await sessions.dispose();
    },
  );

  test(
    'drop batches remain ordered while an earlier open is pending',
    () async {
      final repository = _FakeRepositoryDropRepository();
      final sessions = fakeRepositorySessionService();
      final service = RepositoryDropService(repository, sessions);
      await service.initialize();

      final outcomes = service.outcomes.take(2).toList();
      repository.emit(
        const RepositoryDropEvent.dropped(
          directories: ['/work/first'],
          rejectedItems: 0,
        ),
      );
      repository.emit(
        const RepositoryDropEvent.dropped(
          directories: ['/work/second'],
          rejectedItems: 0,
        ),
      );
      await outcomes;

      expect(sessions.workspace.tabs.map((tab) => tab.label), [
        'first',
        'second',
      ]);

      await service.dispose();
      await sessions.dispose();
    },
  );

  testWidgets('home screen shows drag affordance and sanitized outcome', (
    tester,
  ) async {
    final sessions = fakeRepositorySessionService();
    final dropController = _FakeRepositoryDropController();
    final settings = fakeSettingsService();
    final operations = OperationCenterService.empty();
    await settings.initialize();
    final runtime = testRuntime(
      repositorySessions: sessions,
      settings: settings,
      recovery: fakeRecoveryService(settings),
      operationCenter: operations,
      repositoryDrops: dropController,
      shutdown: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => StatusNotificationScope(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(Brightness.light),
        home: HomeScreen(runtime: runtime),
      ),
    );
    dropController.setDragging(true);
    await tester.pump();
    expect(find.text('Drop repository folders to open them'), findsOneWidget);

    dropController.publish(
      const RepositoryDropOutcome(
        openedRepositories: 1,
        rejectedItems: 1,
        failedDirectories: 0,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Opened 1 repositories.'), findsOneWidget);
    expect(find.textContaining('/work/repository'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await sessions.dispose();
    await operations.dispose();
    await settings.dispose();
  });
}

final class _FakeRepositoryDropController implements RepositoryDropController {
  final StreamController<bool> _dragStates = StreamController<bool>.broadcast(
    sync: true,
  );
  final StreamController<RepositoryDropOutcome> _outcomes =
      StreamController<RepositoryDropOutcome>.broadcast(sync: true);
  var _dragging = false;

  @override
  Stream<bool> get dragStates => _dragStates.stream;

  @override
  Stream<RepositoryDropOutcome> get outcomes => _outcomes.stream;

  @override
  bool get dragging => _dragging;

  void setDragging(bool value) {
    _dragging = value;
    _dragStates.add(value);
  }

  void publish(RepositoryDropOutcome outcome) => _outcomes.add(outcome);
}

final class _FakeRepositoryDropRepository implements RepositoryDropRepository {
  final StreamController<RepositoryDropEvent> _events =
      StreamController<RepositoryDropEvent>.broadcast(sync: true);

  @override
  Stream<RepositoryDropEvent> get events => _events.stream;

  void emit(RepositoryDropEvent event) => _events.add(event);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() => _events.close();
}
