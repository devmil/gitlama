import 'dart:convert';
import 'dart:typed_data';

import 'app_update.dart';
import 'diff.dart';
import 'integrations.dart';
import 'diff_renderer.dart';
import 'hosting.dart';
import 'remote_workspace.dart';

enum SettingsLoadState {
  absent,
  loaded,
  migrated,
  recoveredCorrupt,
  restoredBackup,
}

enum SettingsFailureCode {
  io,
  locked,
  unreadable,
  invalidDocument,
  unsupportedSchema,
}

enum NativePathPlatform { unix, windows }

final class NativePathIdentity {
  NativePathIdentity({
    required this.platform,
    required List<int> units,
    this.remote,
  }) : units = Uint16List.fromList(units);

  final NativePathPlatform platform;
  final Uint16List units;

  /// The remote workspace authority, or null for a path on this computer.
  /// A remote identity is never a local filesystem path: every local file,
  /// process, picker and cache boundary rejects it.
  final RemoteAuthority? remote;

  bool get isRemote => remote != null;

  /// Whether this identity may be stored: a local identity keeps its previous
  /// rules; a remote one needs a valid authority and an absolute Unix path of
  /// bytes. Mirrors the native settings validation.
  bool get isValidLocation {
    final authority = remote;
    return authority == null ||
        authority.isValid &&
            platform == NativePathPlatform.unix &&
            isValidRemotePathUnits(units);
  }

  @override
  bool operator ==(Object other) {
    if (other is! NativePathIdentity ||
        platform != other.platform ||
        remote != other.remote) {
      return false;
    }
    if (units.length != other.units.length) {
      return false;
    }
    for (var index = 0; index < units.length; index += 1) {
      if (units[index] != other.units[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(platform, Object.hashAll(units), remote);

  /// The path as text to show or copy. Unix bytes that are not UTF-8
  /// become U+FFFD; a remote path is the path on its host.
  String get displayText => switch (platform) {
    NativePathPlatform.unix => utf8.decode(
      units.map((unit) => unit & 0xff).toList(growable: false),
      allowMalformed: true,
    ),
    NativePathPlatform.windows => String.fromCharCodes(units),
  };

  /// The last segment of [displayText], such as a repository folder's name.
  String get basename {
    final path = displayText;
    return path
        .split(RegExp(r'[/\\]'))
        .lastWhere((segment) => segment.isNotEmpty, orElse: () => path);
  }
}

/// The appearance names the settings document stores. The Rust core accepts
/// exactly these; `test/fixtures/settings_storage_names.json` pins both sides.
abstract final class StoredAppearanceNames {
  static const themes = ['system', 'light', 'dark'];
  static const densities = ['compact', 'regular', 'comfortable'];
  static const reduceMotion = ['followSystem', 'reduce', 'full'];
  static const fileLayouts = ['list', 'tree'];
  static const inspectionOpenIn = ['pane', 'window'];
}

final class AppearanceSettings {
  const AppearanceSettings({
    this.theme = 'system',
    this.density = 'regular',
    this.reduceMotion = 'followSystem',
    this.dateFormat = 'relative',
    this.gravatarEnabled = false,
    this.sidebarWidth = 248,
    this.diffWidth = 420,
    this.changesUnstagedMode = 'list',
    this.changesStagedMode = 'list',
    this.changesSplitRatio = 500,
    this.commitFilesMode = 'tree',
    this.inspectionOpenIn = 'pane',
    this.diffView = const DiffViewPreferences(),
    this.historyOtherRefs = false,
    this.windowX,
    this.windowY,
    this.windowWidth,
    this.windowHeight,
    this.windowMaximized = false,
  });

  final String theme;
  final String density;
  final String reduceMotion;
  final String dateFormat;
  final bool gravatarEnabled;
  final int sidebarWidth;
  final int diffWidth;
  final String changesUnstagedMode;
  final String changesStagedMode;
  final int changesSplitRatio;

  /// `list` or `tree` arrangement of a commit's changed files.
  final String commitFilesMode;

  /// Where Blame, Contents and History open: `pane` or `window`.
  final String inspectionOpenIn;

  /// How every diff view shows diffs.
  final DiffViewPreferences diffView;

  /// Whether History also shows commits that only references outside
  /// branches, remote branches, tags and the stash reach, such as notes or
  /// another tool's checkpoints.
  final bool historyOtherRefs;
  final int? windowX;
  final int? windowY;
  final int? windowWidth;
  final int? windowHeight;
  final bool windowMaximized;

  AppearanceSettings copyWith({
    String? theme,
    String? density,
    String? reduceMotion,
    String? dateFormat,
    bool? gravatarEnabled,
    int? sidebarWidth,
    int? diffWidth,
    String? changesUnstagedMode,
    String? changesStagedMode,
    int? changesSplitRatio,
    String? commitFilesMode,
    String? inspectionOpenIn,
    DiffViewPreferences? diffView,
    bool? historyOtherRefs,
    int? windowX,
    int? windowY,
    int? windowWidth,
    int? windowHeight,
    bool? windowMaximized,
  }) => AppearanceSettings(
    theme: theme ?? this.theme,
    density: density ?? this.density,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    dateFormat: dateFormat ?? this.dateFormat,
    gravatarEnabled: gravatarEnabled ?? this.gravatarEnabled,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    diffWidth: diffWidth ?? this.diffWidth,
    changesUnstagedMode: changesUnstagedMode ?? this.changesUnstagedMode,
    changesStagedMode: changesStagedMode ?? this.changesStagedMode,
    changesSplitRatio: changesSplitRatio ?? this.changesSplitRatio,
    commitFilesMode: commitFilesMode ?? this.commitFilesMode,
    inspectionOpenIn: inspectionOpenIn ?? this.inspectionOpenIn,
    diffView: diffView ?? this.diffView,
    historyOtherRefs: historyOtherRefs ?? this.historyOtherRefs,
    windowX: windowX ?? this.windowX,
    windowY: windowY ?? this.windowY,
    windowWidth: windowWidth ?? this.windowWidth,
    windowHeight: windowHeight ?? this.windowHeight,
    windowMaximized: windowMaximized ?? this.windowMaximized,
  );
}

final class CommitDraft {
  const CommitDraft({this.subject = '', this.description = ''});
  final String subject;
  final String description;

  bool matches(CommitDraft other) =>
      subject == other.subject && description == other.description;
}

final class WorktreeSettings {
  const WorktreeSettings({
    required this.identity,
    this.filter = '',
    this.anchor,
    this.pane = 'changes',
    this.route = 'repository',
    this.changesScrollOffset = 0,
    this.historyScrollOffset = 0,
    this.draft = const CommitDraft(),
    this.branchFilter = const [],
  });

  final NativePathIdentity identity;
  final String filter;
  final String? anchor;
  final String pane;
  final String route;
  final int changesScrollOffset;
  final int historyScrollOffset;
  final CommitDraft draft;

  /// Full reference names the history graph shows; empty shows all.
  final List<String> branchFilter;

  WorktreeSettings copyWith({
    String? filter,
    String? anchor,
    bool clearAnchor = false,
    String? pane,
    String? route,
    int? changesScrollOffset,
    int? historyScrollOffset,
    CommitDraft? draft,
    List<String>? branchFilter,
  }) => WorktreeSettings(
    identity: identity,
    filter: filter ?? this.filter,
    anchor: clearAnchor ? null : anchor ?? this.anchor,
    pane: pane ?? this.pane,
    route: route ?? this.route,
    changesScrollOffset: changesScrollOffset ?? this.changesScrollOffset,
    historyScrollOffset: historyScrollOffset ?? this.historyScrollOffset,
    draft: draft ?? this.draft,
    branchFilter: branchFilter ?? this.branchFilter,
  );
}

final class HostingBindingOverride {
  HostingBindingOverride({
    required this.repository,
    required List<int> remote,
    required this.connectionId,
    required this.providerRepository,
  }) : remote = Uint8List.fromList(remote);

  final NativePathIdentity repository;
  final Uint8List remote;
  final String connectionId;
  final String providerRepository;
}

final class ShortcutOverride {
  const ShortcutOverride({required this.commandId, required this.binding});

  final String commandId;
  final String? binding;
}

/// How a repository's tab identifies it: an [image] file, or an [icon] and
/// [color] from the repository appearance catalogues. An image wins. A
/// [name] replaces the folder's name on the tab.
final class RepositoryAppearance {
  const RepositoryAppearance({
    required this.identity,
    this.icon,
    this.color,
    this.image,
    this.name,
  });

  final NativePathIdentity identity;
  final String? icon;
  final String? color;
  final NativePathIdentity? image;
  final String? name;

  bool get isEmpty =>
      icon == null && color == null && image == null && name == null;

  /// Whether it changes the tab's mark (as opposed to only its name).
  bool get hasMark => icon != null || color != null || image != null;

  /// This appearance with its mark removed; the name stays.
  RepositoryAppearance withoutMark() =>
      RepositoryAppearance(identity: identity, name: name);

  /// This appearance named [name]; `null` restores the folder's name.
  RepositoryAppearance withName(String? name) => RepositoryAppearance(
    identity: identity,
    icon: icon,
    color: color,
    image: image,
    name: name,
  );

  @override
  bool operator ==(Object other) =>
      other is RepositoryAppearance &&
      other.identity == identity &&
      other.icon == icon &&
      other.color == color &&
      other.image == image &&
      other.name == name;

  @override
  int get hashCode => Object.hash(identity, icon, color, image, name);
}

/// Open repository tabs kept together under a [name], a [color] key of an
/// [AppearanceColor] and an optional [icon] from
/// `repositoryAppearanceIcons`, with their repositories in tab order.
final class TabGroupSettings {
  const TabGroupSettings({
    required this.color,
    required this.members,
    this.name = '',
    this.icon,
    this.collapsed = false,
  });

  final String name;
  final String color;
  final String? icon;
  final bool collapsed;
  final List<NativePathIdentity> members;

  @override
  bool operator ==(Object other) =>
      other is TabGroupSettings &&
      other.name == name &&
      other.color == color &&
      other.icon == icon &&
      other.collapsed == collapsed &&
      _sameIdentities(other.members, members);

  @override
  int get hashCode =>
      Object.hash(name, color, icon, collapsed, Object.hashAll(members));
}

bool _sameIdentities(List<NativePathIdentity> a, List<NativePathIdentity> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Fetching the remotes of open repositories in the background.
final class AutoFetchSettings {
  const AutoFetchSettings({this.enabled = true, this.intervalMinutes = 10});

  /// The intervals the settings offer, in minutes.
  static const intervals = [5, 10, 15, 30, 60];

  final bool enabled;
  final int intervalMinutes;

  AutoFetchSettings copyWith({bool? enabled, int? intervalMinutes}) =>
      AutoFetchSettings(
        enabled: enabled ?? this.enabled,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is AutoFetchSettings &&
      other.enabled == enabled &&
      other.intervalMinutes == intervalMinutes;

  @override
  int get hashCode => Object.hash(enabled, intervalMinutes);
}

/// What one repository overrides; a null value follows the application.
final class RepositoryOptions {
  const RepositoryOptions({required this.identity, this.autoFetch});

  final NativePathIdentity identity;
  final bool? autoFetch;
}

final class SettingsDocument {
  const SettingsDocument({
    this.appearance = const AppearanceSettings(),
    this.recentRepositories = const [],
    this.worktrees = const [],
    this.openWorktrees = const [],
    this.activeWorktree,
    this.integrations = const [],
    this.diffRenderer,
    this.hostingConnections = const [],
    this.hostingBindings = const [],
    this.hostingExpandedNodes = const [],
    this.shortcutOverrides = const [],
    this.repositoryAppearances = const [],
    this.releaseChannel,
    this.autoFetch = const AutoFetchSettings(),
    this.repositoryOptions = const [],
    this.tabGroups = const [],
    this.remoteProfiles = const [],
  });

  final AppearanceSettings appearance;
  final List<NativePathIdentity> recentRepositories;
  final List<WorktreeSettings> worktrees;
  final List<NativePathIdentity> openWorktrees;
  final NativePathIdentity? activeWorktree;
  final List<IntegrationDefinition> integrations;
  final DiffRendererDefinition? diffRenderer;
  final List<HostingConnection> hostingConnections;
  final List<HostingBindingOverride> hostingBindings;
  final List<String> hostingExpandedNodes;
  final List<ShortcutOverride> shortcutOverrides;
  final List<RepositoryAppearance> repositoryAppearances;

  /// The update channel the user chose; null follows the installed build.
  final ReleaseChannel? releaseChannel;
  final AutoFetchSettings autoFetch;

  /// Only repositories that override something have an entry.
  final List<RepositoryOptions> repositoryOptions;

  /// The groups of [openWorktrees]' tabs.
  final List<TabGroupSettings> tabGroups;

  /// Remote host profiles, at most [RemoteHostProfile.capacity]. Remote
  /// identities elsewhere may name a deleted profile; they stay recoverable.
  final List<RemoteHostProfile> remoteProfiles;

  /// Whether the remote profiles and every identity's location are valid,
  /// mirroring the native settings validation: workspace keys may be remote,
  /// files the application opens or runs locally may not.
  bool get hasValidRemoteData {
    final workspaceKeys = [
      ...recentRepositories,
      for (final worktree in worktrees) worktree.identity,
      ...openWorktrees,
      ?activeWorktree,
      for (final group in tabGroups) ...group.members,
      for (final appearance in repositoryAppearances) appearance.identity,
      for (final options in repositoryOptions) options.identity,
      for (final binding in hostingBindings) binding.repository,
    ];
    final localFiles = [
      for (final integration in integrations) integration.executable,
      ?diffRenderer?.executable,
      for (final appearance in repositoryAppearances) ?appearance.image,
    ];
    final profileIds = {for (final profile in remoteProfiles) profile.id};
    return workspaceKeys.every((identity) => identity.isValidLocation) &&
        !localFiles.any((identity) => identity.isRemote) &&
        remoteProfiles.length <= RemoteHostProfile.capacity &&
        profileIds.length == remoteProfiles.length &&
        remoteProfiles.every((profile) => profile.isValid);
  }

  /// The override of [repository], or null when it follows the application.
  bool? autoFetchOverride(NativePathIdentity repository) => repositoryOptions
      .where((options) => options.identity == repository)
      .firstOrNull
      ?.autoFetch;

  /// Whether [repository] is fetched in the background.
  bool autoFetches(NativePathIdentity repository) =>
      autoFetchOverride(repository) ?? autoFetch.enabled;

  /// This document with [repository] overriding auto-fetch, or following the
  /// application again when [autoFetch] is null.
  SettingsDocument withAutoFetchOverride(
    NativePathIdentity repository,
    bool? autoFetch,
  ) => copyWith(
    repositoryOptions: [
      for (final options in repositoryOptions)
        if (options.identity != repository) options,
      if (autoFetch != null)
        RepositoryOptions(identity: repository, autoFetch: autoFetch),
    ],
  );

  SettingsDocument copyWith({
    AppearanceSettings? appearance,
    List<NativePathIdentity>? recentRepositories,
    List<WorktreeSettings>? worktrees,
    List<NativePathIdentity>? openWorktrees,
    NativePathIdentity? activeWorktree,
    bool clearActiveWorktree = false,
    List<IntegrationDefinition>? integrations,
    DiffRendererDefinition? diffRenderer,
    bool clearDiffRenderer = false,
    List<HostingConnection>? hostingConnections,
    List<HostingBindingOverride>? hostingBindings,
    List<String>? hostingExpandedNodes,
    List<ShortcutOverride>? shortcutOverrides,
    List<RepositoryAppearance>? repositoryAppearances,
    ReleaseChannel? releaseChannel,
    bool clearReleaseChannel = false,
    AutoFetchSettings? autoFetch,
    List<RepositoryOptions>? repositoryOptions,
    List<TabGroupSettings>? tabGroups,
    List<RemoteHostProfile>? remoteProfiles,
  }) => SettingsDocument(
    appearance: appearance ?? this.appearance,
    recentRepositories: recentRepositories ?? this.recentRepositories,
    worktrees: worktrees ?? this.worktrees,
    openWorktrees: openWorktrees ?? this.openWorktrees,
    activeWorktree: clearActiveWorktree
        ? null
        : activeWorktree ?? this.activeWorktree,
    integrations: integrations ?? this.integrations,
    diffRenderer: clearDiffRenderer ? null : diffRenderer ?? this.diffRenderer,
    hostingConnections: hostingConnections ?? this.hostingConnections,
    hostingBindings: hostingBindings ?? this.hostingBindings,
    hostingExpandedNodes: hostingExpandedNodes ?? this.hostingExpandedNodes,
    shortcutOverrides: shortcutOverrides ?? this.shortcutOverrides,
    repositoryAppearances: repositoryAppearances ?? this.repositoryAppearances,
    releaseChannel: clearReleaseChannel
        ? null
        : releaseChannel ?? this.releaseChannel,
    autoFetch: autoFetch ?? this.autoFetch,
    repositoryOptions: repositoryOptions ?? this.repositoryOptions,
    tabGroups: tabGroups ?? this.tabGroups,
    remoteProfiles: remoteProfiles ?? this.remoteProfiles,
  );
}

final class LoadedSettings {
  const LoadedSettings({required this.state, required this.document});
  final SettingsLoadState state;
  final SettingsDocument document;
}

final class SettingsException implements Exception {
  const SettingsException(this.code, {this.rule});
  final SettingsFailureCode code;

  /// For a rejected document, the stable name of the rule it broke.
  final String? rule;

  @override
  String toString() => 'SettingsException(${code.name})';
}
