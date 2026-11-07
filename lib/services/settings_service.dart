import 'dart:async';

import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../models/settings.dart';
import '../models/app_command.dart';
import '../models/app_shortcut.dart';
import '../models/diff_renderer.dart';
import '../models/integrations.dart';
import '../repositories/settings_repository.dart';

final _log = AppLogger('Settings');

/// Owns observable settings and bounded persistence scheduling.
final class SettingsService {
  SettingsService(
    this._repository, {
    this.debounce = const Duration(milliseconds: 250),
    this.maximumFlushDelay = const Duration(seconds: 2),
  });

  final SettingsRepository _repository;
  final Duration debounce;
  final Duration maximumFlushDelay;
  final StreamController<SettingsDocument> _changes =
      StreamController<SettingsDocument>.broadcast(sync: true);
  SettingsDocument _current = const SettingsDocument();
  SettingsLoadState _loadState = SettingsLoadState.absent;
  Timer? _debounceTimer;
  Timer? _maximumTimer;
  Future<void> _saveChain = Future.value();
  var _revision = 0;
  var _savedRevision = 0;
  var _scheduledRevision = 0;
  var _initialized = false;
  var _disposed = false;

  SettingsDocument get current => _current;
  SettingsLoadState get loadState => _loadState;
  Stream<SettingsDocument> get changes => _changes.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    final loaded = await _repository.load();
    _validate(loaded.document);
    _current = loaded.document;
    _loadState = loaded.state;
    _initialized = true;
  }

  void updateView(SettingsDocument document) {
    _ensureActive();
    _publish(document);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(_backgroundFlush()));
    _maximumTimer ??= Timer(
      maximumFlushDelay,
      () => unawaited(_backgroundFlush()),
    );
  }

  /// A scheduled save has no caller to report to; the next save retries.
  Future<void> _backgroundFlush() async {
    try {
      await flush();
    } on Object catch (error) {
      _log.warning('settings_background_save_failed', {
        'failure_code': LogField(switch (error) {
          SettingsException(:final code, :final rule) => [
            code.name,
            ?rule,
          ].join('_'),
          _ => 'unexpected',
        }, LogSensitivity.public),
      });
    }
  }

  /// Applies [change] to the document current at this moment and schedules
  /// a save. Callers change their own section and keep everything else.
  void update(SettingsDocument Function(SettingsDocument current) change) =>
      updateView(change(_current));

  /// Applies [change] and saves at once. When the store rejects the save,
  /// [restore] puts back only the section [change] wrote, taken from the
  /// document before it, into whatever is current then; changes others made
  /// meanwhile stay. The failure is rethrown.
  Future<void> updateDurable(
    SettingsDocument Function(SettingsDocument current) change, {
    required SettingsDocument Function(
      SettingsDocument current,
      SettingsDocument previous,
    )
    restore,
  }) async {
    _ensureActive();
    final previous = _current;
    _publish(change(previous));
    try {
      await flush();
    } on Object {
      if (!_disposed) _publish(restore(_current, previous));
      rethrow;
    }
  }

  /// Changes the appearance; saved in the background.
  void updateAppearance(
    AppearanceSettings Function(AppearanceSettings appearance) change,
  ) => update(
    (document) => document.copyWith(appearance: change(document.appearance)),
  );

  /// Changes the appearance and saves at once; a rejected save restores the
  /// previous appearance only.
  Future<void> saveAppearance(
    AppearanceSettings Function(AppearanceSettings appearance) change,
  ) => updateDurable(
    (document) => document.copyWith(appearance: change(document.appearance)),
    restore: (current, previous) =>
        current.copyWith(appearance: previous.appearance),
  );

  void updateAutoFetch(AutoFetchSettings autoFetch) =>
      update((document) => document.copyWith(autoFetch: autoFetch));

  /// Overrides automatic fetching for [repository]; null follows the global
  /// setting.
  void setRepositoryAutoFetch(NativePathIdentity repository, bool? value) =>
      update((document) => document.withAutoFetchOverride(repository, value));

  /// Binds [command] to [input], or validates and refuses it with an
  /// [AppShortcutException].
  Future<void> setShortcut(
    AppCommandId command,
    String input, {
    required bool macOS,
  }) => _saveShortcuts(
    (overrides) =>
        AppShortcutCatalog.replace(overrides, command, input, macOS: macOS),
  );

  Future<void> resetShortcuts() => _saveShortcuts((_) => const []);

  Future<void> _saveShortcuts(
    List<ShortcutOverride> Function(List<ShortcutOverride> overrides) change,
  ) {
    // Validate before anything is published.
    final overrides = change(_current.shortcutOverrides);
    return updateDurable(
      (document) => document.copyWith(shortcutOverrides: overrides),
      restore: (current, previous) =>
          current.copyWith(shortcutOverrides: previous.shortcutOverrides),
    );
  }

  /// Forgets what is stored for [repository]: its automatic-fetch override
  /// and its workspace state.
  Future<void> resetRepository(NativePathIdentity repository) => updateDurable(
    (document) => document
        .withAutoFetchOverride(repository, null)
        .copyWith(
          worktrees: document.worktrees
              .where((value) => value.identity != repository)
              .toList(growable: false),
        ),
    restore: (current, previous) => current.copyWith(
      repositoryOptions: previous.repositoryOptions,
      worktrees: previous.worktrees,
    ),
  );

  /// Adds [definition] or replaces the one with its ID.
  Future<void> saveIntegration(IntegrationDefinition definition) =>
      _saveIntegrations(
        (integrations) => [
          for (final existing in integrations)
            if (existing.id != definition.id) existing,
          definition,
        ],
      );

  Future<void> removeIntegration(String id) => _saveIntegrations(
    (integrations) =>
        integrations.where((value) => value.id != id).toList(growable: false),
  );

  Future<void> _saveIntegrations(
    List<IntegrationDefinition> Function(List<IntegrationDefinition>) change,
  ) => updateDurable(
    (document) =>
        document.copyWith(integrations: change(document.integrations)),
    restore: (current, previous) =>
        current.copyWith(integrations: previous.integrations),
  );

  /// Saves the diff renderer; null removes it.
  Future<void> saveDiffRenderer(DiffRendererDefinition? definition) =>
      updateDurable(
        (document) => definition == null
            ? document.copyWith(clearDiffRenderer: true)
            : document.copyWith(diffRenderer: definition),
        restore: (current, previous) => previous.diffRenderer == null
            ? current.copyWith(clearDiffRenderer: true)
            : current.copyWith(diffRenderer: previous.diffRenderer),
      );

  Future<void> saveDurable(SettingsDocument document) async {
    _ensureActive();
    _publish(document);
    await flush();
  }

  Future<void> flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _maximumTimer?.cancel();
    _maximumTimer = null;
    if (_scheduledRevision >= _revision) return _saveChain;
    final document = _current;
    final revision = _revision;
    final previous = _saveChain;
    _scheduledRevision = revision;
    _saveChain = () async {
      try {
        await previous;
      } on Object {
        // A later explicit save may recover after a previous failed attempt.
      }
      try {
        await _repository.save(document);
        if (_savedRevision < revision) _savedRevision = revision;
      } on Object {
        if (_scheduledRevision == revision) {
          _scheduledRevision = _savedRevision;
        }
        rethrow;
      }
    }();
    return _saveChain;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await flush();
    } on Object {
      // Shutdown persistence is best effort; explicit durable saves surface errors.
    }
    await _changes.close();
  }

  void _publish(SettingsDocument document) {
    _validate(document);
    _current = document;
    _revision += 1;
    _changes.add(document);
  }

  void _validate(SettingsDocument document) {
    // Invalid remote data is rejected before it is published, so the
    // observable document never holds what persistence would refuse.
    if (!document.hasValidRemoteData) {
      throw const SettingsException(
        SettingsFailureCode.invalidDocument,
        rule: 'publish_remote_data',
      );
    }
    AppShortcutCatalog.resolve(document.shortcutOverrides, macOS: true);
    AppShortcutCatalog.resolve(document.shortcutOverrides, macOS: false);
  }

  void _ensureActive() {
    if (!_initialized || _disposed) {
      throw StateError('settings_service_unavailable');
    }
  }
}
