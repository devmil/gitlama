import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/remote_workspace.dart';
import '../../services/remote_workspace_service.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';
import 'remote_workspace.dart';

/// What the chosen remote folder is for.
enum RemoteDirectoryPurpose {
  /// Opening an existing repository.
  open,

  /// Creating a repository in an empty folder or at a path that does not
  /// exist yet.
  initialize,
}

/// Chooses a folder on a connected host. Returns the exact path bytes of
/// the folder to open, or null when canceled. A local folder picker is never
/// used for a host. For [RemoteDirectoryPurpose.initialize] a typed path may
/// name a folder that does not exist yet.
Future<Uint8List?> showRemoteDirectoryPicker(
  BuildContext context, {
  required RemoteWorkspaceService service,
  required RemoteHostProfile profile,
  RemoteDirectoryPurpose purpose = RemoteDirectoryPurpose.open,
}) => showMeridianDialog<Uint8List>(
  context: context,
  builder: (context) => RemoteDirectoryPicker(
    service: service,
    profile: profile,
    purpose: purpose,
  ),
);

/// The outcome of parsing a typed remote path.
enum RemotePathInputError { empty, notAbsolute, invalid }

/// Parses a typed path: an absolute POSIX path as UTF-8, without NUL and
/// within the wire bound. `~` and relative paths are rejected; the host
/// resolves nothing on the user's behalf.
({Uint8List? path, RemotePathInputError? error}) parseRemotePathInput(
  String text,
) {
  if (text.isEmpty) return (path: null, error: RemotePathInputError.empty);
  if (!text.startsWith('/')) {
    return (path: null, error: RemotePathInputError.notAbsolute);
  }
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (text.contains('\u0000') || !isValidRemotePathUnits(bytes)) {
    return (path: null, error: RemotePathInputError.invalid);
  }
  return (path: bytes, error: null);
}

/// Splits a typed absolute [path] into the folder to list and the start of
/// the entry name typed in it. A trailing `/` lists that folder itself.
({Uint8List directory, Uint8List prefix}) splitRemotePathInput(Uint8List path) {
  final slash = path.lastIndexOf(0x2f);
  final directory = slash == 0
      ? Uint8List.fromList(const [0x2f])
      : Uint8List.sublistView(path, 0, slash);
  return (directory: directory, prefix: Uint8List.sublistView(path, slash + 1));
}

/// What a typed path is on the host, as far as the picker could tell.
enum RemoteTypedPathStatus { checking, folder, notFolder, missing }

/// [directory] joined with the entry [name] bytes.
Uint8List remoteChildPath(List<int> directory, List<int> name) =>
    Uint8List.fromList([
      ...directory,
      if (directory.isEmpty || directory.last != 0x2f) 0x2f,
      ...name,
    ]);

class RemoteDirectoryPicker extends StatefulWidget {
  const RemoteDirectoryPicker({
    super.key,
    required this.service,
    required this.profile,
    this.purpose = RemoteDirectoryPurpose.open,
  });

  final RemoteWorkspaceService service;
  final RemoteHostProfile profile;
  final RemoteDirectoryPurpose purpose;

  @override
  State<RemoteDirectoryPicker> createState() => _RemoteDirectoryPickerState();
}

class _RemoteDirectoryPickerState extends State<RemoteDirectoryPicker> {
  final TextEditingController _path = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Only the newest request may change what the picker shows; a late reply
  /// of a superseded request is dropped.
  var _request = 0;
  var _loading = false;
  RemoteDirectoryPage? _page;
  List<RemoteDirectoryEntry> _entries = const [];
  RemoteFailureCode? _failure;
  RemotePathInputError? _pathError;
  var _pathAttempted = false;

  /// The typed start of an entry name; the list shows only matching entries.
  Uint8List? _filter;
  RemoteTypedPathStatus? _typedStatus;
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request += 1;
    _typing?.cancel();
    _path.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Lists [directory], or the user's home without one. A navigation also
  /// shows the listed folder in the path field, so field and list agree.
  Future<void> _load({
    List<int>? directory,
    bool more = false,
    bool navigation = false,
  }) async {
    final request = ++_request;
    final cursor = more ? _page?.cursor : null;
    if (!more) _typing?.cancel();
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await widget.service.listDirectory(
        widget.profile.id,
        directory: more ? _page?.directory : directory,
        cursor: cursor,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _page = page;
        _entries = more ? [..._entries, ...page.entries] : page.entries;
        _loading = false;
        if (navigation) _showInField(page.directory);
      });
      // A newly listed folder starts at its top; more entries keep the place.
      if (!more && _scroll.hasClients) _scroll.jumpTo(0);
    } on RemoteWorkspaceException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _failure = error.code;
        _loading = false;
      });
    } on Object {
      if (!mounted || request != _request) return;
      setState(() {
        _failure = RemoteFailureCode.internal;
        _loading = false;
      });
    }
  }

  /// Puts the listed [directory] into the path field with a trailing `/`,
  /// or clears the field when the path is not text that can be typed.
  void _showInField(List<int> directory) {
    String? text;
    try {
      text = utf8.decode(directory);
    } on FormatException {
      text = null;
    }
    final typed = text == null ? '' : (text.endsWith('/') ? text : '$text/');
    _path.value = TextEditingValue(
      text: typed,
      selection: TextSelection.collapsed(offset: typed.length),
    );
    _pathError = null;
    _pathAttempted = false;
    _filter = null;
    _typedStatus = typed.isEmpty ? null : RemoteTypedPathStatus.folder;
  }

  /// Lists the shown folder again from its start.
  void _restart() => unawaited(_load(directory: _page?.directory));

  void _enter(RemoteDirectoryEntry entry) {
    final page = _page;
    if (page == null) return;
    unawaited(
      _load(
        directory: remoteChildPath(page.directory, entry.name),
        navigation: true,
      ),
    );
  }

  void _typed(String value) {
    _typing?.cancel();
    final parsed = parseRemotePathInput(value);
    setState(() {
      _pathError = parsed.error;
      _typedStatus = parsed.path == null
          ? null
          : RemoteTypedPathStatus.checking;
      if (parsed.path == null) _filter = null;
    });
    final path = parsed.path;
    if (path == null) return;
    _typing = Timer(
      GitLamaMotion.remotePathFollowDelay,
      () => unawaited(_follow(path)),
    );
  }

  /// Lists the folder a typed [path] is in, filtered by its last segment,
  /// and tells whether [path] itself is a folder on the host.
  Future<void> _follow(Uint8List path) async {
    final request = ++_request;
    final (:directory, :prefix) = splitRemotePathInput(path);
    final shown = _page;
    var page = shown;
    var entries = _entries;
    if (shown == null || !_samePath(shown.directory, directory)) {
      setState(() => _loading = true);
      try {
        page = await widget.service.listDirectory(
          widget.profile.id,
          directory: directory,
        );
        entries = page.entries;
      } on RemoteWorkspaceException catch (error) {
        if (!mounted || request != _request) return;
        final absent =
            error.code == RemoteFailureCode.pathNotFound ||
            error.code == RemoteFailureCode.notDirectory;
        setState(() {
          _loading = false;
          _filter = null;
          _typedStatus = absent ? RemoteTypedPathStatus.missing : null;
          if (!absent) _failure = error.code;
        });
        return;
      } on Object {
        if (!mounted || request != _request) return;
        setState(() {
          _loading = false;
          _typedStatus = null;
          _failure = RemoteFailureCode.internal;
        });
        return;
      }
      if (!mounted || request != _request) return;
    }
    final listed = page!;
    var status = prefix.isEmpty ? RemoteTypedPathStatus.folder : null;
    if (status == null) {
      final exact = entries.where((entry) => _samePath(entry.name, prefix));
      status = switch (exact.firstOrNull?.kind) {
        RemoteEntryKind.directory => RemoteTypedPathStatus.folder,
        RemoteEntryKind.file ||
        RemoteEntryKind.other => RemoteTypedPathStatus.notFolder,
        // A link may lead anywhere, and a later page may hold the entry.
        RemoteEntryKind.symlink => null,
        null => listed.cursor == null ? RemoteTypedPathStatus.missing : null,
      };
    }
    setState(() {
      _page = listed;
      _entries = entries;
      _filter = prefix.isEmpty ? null : prefix;
      _loading = status == null;
      _failure = null;
      _typedStatus = status ?? RemoteTypedPathStatus.checking;
    });
    if (!identical(listed, shown) && _scroll.hasClients) _scroll.jumpTo(0);
    if (status != null) return;
    RemoteTypedPathStatus probed;
    try {
      await widget.service.listDirectory(widget.profile.id, directory: path);
      probed = RemoteTypedPathStatus.folder;
    } on RemoteWorkspaceException catch (error) {
      probed = switch (error.code) {
        RemoteFailureCode.notDirectory => RemoteTypedPathStatus.notFolder,
        RemoteFailureCode.pathNotFound => RemoteTypedPathStatus.missing,
        _ => RemoteTypedPathStatus.missing,
      };
    } on Object {
      probed = RemoteTypedPathStatus.missing;
    }
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _typedStatus = probed;
    });
  }

  static bool _samePath(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static bool _startsWith(List<int> name, List<int> prefix) {
    if (name.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index += 1) {
      if (name[index] != prefix[index]) return false;
    }
    return true;
  }

  void _goToTyped() {
    final parsed = parseRemotePathInput(_path.text);
    setState(() {
      _pathAttempted = true;
      _pathError = parsed.error;
    });
    if (parsed.path case final path?) {
      unawaited(_load(directory: path, navigation: true));
    }
  }

  void _open() {
    _typing?.cancel();
    if (_path.text.isNotEmpty) {
      final parsed = parseRemotePathInput(_path.text);
      setState(() {
        _pathAttempted = true;
        _pathError = parsed.error;
      });
      if (parsed.path case final path?) {
        // A trailing separator names the same folder.
        var end = path.length;
        while (end > 1 && path[end - 1] == 0x2f) {
          end -= 1;
        }
        Navigator.pop(context, Uint8List.sublistView(path, 0, end));
      }
      return;
    }
    final page = _page;
    if (page != null) Navigator.pop(context, page.directory);
  }

  String? _pathErrorText(BuildContext context) =>
      !_pathAttempted && _path.text.isEmpty
      ? null
      : switch (_pathError) {
          RemotePathInputError.empty => null,
          RemotePathInputError.notAbsolute =>
            context.l10n.remotePathAbsoluteRequired,
          RemotePathInputError.invalid => context.l10n.remotePathInvalid,
          null => null,
        };

  Widget? _typedStatusMark(BuildContext context) {
    final l10n = context.l10n;
    final status = _pathError == null ? _typedStatus : null;
    if (status == null) return null;
    final initializing = widget.purpose == RemoteDirectoryPurpose.initialize;
    if (status == RemoteTypedPathStatus.checking) {
      return MeridianSpinner(
        key: const ValueKey('remote-directory-path-checking'),
        size: MeridianSize.icon,
        semanticLabel: l10n.remotePathChecking,
        delayed: true,
      );
    }
    final (icon, color, label) = switch (status) {
      RemoteTypedPathStatus.folder => (
        'circle-check',
        context.colors.success,
        l10n.remotePathFolder,
      ),
      RemoteTypedPathStatus.notFolder => (
        'circle-alert',
        context.colors.warning,
        l10n.remotePathNotFolder,
      ),
      _ when initializing => (
        'folder-plus',
        context.colors.success,
        l10n.remoteInitializePathNew,
      ),
      _ => ('circle-x', context.colors.danger, l10n.remotePathMissing),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        liveRegion: true,
        child: MeridianIcon(
          icon,
          key: ValueKey('remote-directory-path-${status.name}'),
          size: MeridianIconSize.small,
          color: color,
        ),
      ),
    );
  }

  String _typedStatusMessage(BuildContext context) {
    final l10n = context.l10n;
    final initializing = widget.purpose == RemoteDirectoryPurpose.initialize;
    return switch (_pathError == null ? _typedStatus : null) {
      RemoteTypedPathStatus.folder => l10n.remotePathFolder,
      RemoteTypedPathStatus.notFolder => l10n.remotePathNotFolder,
      RemoteTypedPathStatus.missing when initializing =>
        l10n.remoteInitializePathNew,
      RemoteTypedPathStatus.missing => l10n.remotePathMissing,
      _ when initializing => l10n.remoteInitializePathHelp,
      _ => l10n.remoteDirectoryPathHelp,
    };
  }

  String _entryIcon(RemoteDirectoryEntry entry) => switch (entry.kind) {
    RemoteEntryKind.directory => entry.repository ? 'folder-git-2' : 'folder',
    RemoteEntryKind.symlink => 'folder-symlink',
    RemoteEntryKind.file || RemoteEntryKind.other => 'file',
  };

  Widget _entry(RemoteDirectoryEntry entry) {
    final l10n = context.l10n;
    final navigable =
        entry.kind == RemoteEntryKind.directory ||
        entry.kind == RemoteEntryKind.symlink;
    final kind = switch (entry.kind) {
      RemoteEntryKind.directory =>
        entry.repository ? l10n.remoteEntryRepository : null,
      RemoteEntryKind.symlink => l10n.remoteEntrySymlink,
      RemoteEntryKind.file => l10n.remoteEntryFile,
      RemoteEntryKind.other => l10n.remoteEntryOther,
    };
    return MeridianListRow(
      leading: MeridianIcon(_entryIcon(entry)),
      title: displayRemotePath(entry.name),
      meta: kind,
      dimmed: !navigable,
      // Navigating while a listing loads supersedes it.
      enabled: navigable,
      semanticLabel: kind == null
          ? displayRemotePath(entry.name)
          : '${displayRemotePath(entry.name)}, $kind',
      onTap: navigable ? () => _enter(entry) : null,
    );
  }

  Widget? _failureBanner(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final l10n = context.l10n;
    final action = switch (failure) {
      RemoteFailureCode.directoryChanged => MeridianButton(
        key: const ValueKey('remote-directory-refresh'),
        label: l10n.remoteDirectoryRefresh,
        size: MeridianControlSize.small,
        onPressed: _restart,
      ),
      RemoteFailureCode.cursorExpired => MeridianButton(
        key: const ValueKey('remote-directory-restart'),
        label: l10n.remoteDirectoryRestart,
        size: MeridianControlSize.small,
        onPressed: _restart,
      ),
      _ => null,
    };
    return MeridianBanner(
      key: const ValueKey('remote-directory-failure'),
      tone: MeridianBannerTone.error,
      message: remoteFailureMessage(
        context,
        failure,
        alias: widget.profile.alias,
      ),
      actions: [?action],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final initializing = widget.purpose == RemoteDirectoryPurpose.initialize;
    final page = _page;
    final failure = _failureBanner(context);
    final current = page == null ? null : displayRemotePath(page.directory);
    final canOpen = !_loading && (page != null || _path.text.isNotEmpty);
    final filter = _filter;
    final shown = filter == null
        ? _entries
        : [
            for (final entry in _entries)
              if (_startsWith(entry.name, filter)) entry,
          ];
    return MeridianDialog(
      width: MeridianLayout.dialogWorkflowWidth,
      title: initializing
          ? l10n.remoteInitializeDirectoryTitle(widget.profile.label)
          : l10n.remoteDirectoryTitle(widget.profile.label),
      onSubmit: canOpen ? _open : null,
      submitDisabled: !canOpen,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MeridianIconButton(
                key: const ValueKey('remote-directory-up'),
                label: l10n.remoteDirectoryUp,
                icon: 'arrow-up',
                onPressed: page?.parent == null
                    ? null
                    : () => unawaited(
                        _load(directory: page!.parent, navigation: true),
                      ),
              ),
              MeridianIconButton(
                key: const ValueKey('remote-directory-home'),
                label: l10n.remoteDirectoryHome,
                icon: 'house',
                onPressed: () => unawaited(_load(navigation: true)),
              ),
              const SizedBox(width: MeridianSpace.space3),
              Expanded(
                child: Semantics(
                  label: l10n.remoteDirectoryCurrent,
                  value: current ?? '',
                  liveRegion: true,
                  excludeSemantics: true,
                  child: Text(
                    current ?? l10n.remoteDirectoryLoading,
                    key: const ValueKey('remote-directory-current'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.code.copyWith(
                      color: context.colors.ink,
                    ),
                  ),
                ),
              ),
              if (_loading) const MeridianSpinner(),
            ],
          ),
          const SizedBox(height: MeridianSpace.space4),
          MeridianTextField(
            fieldKey: const ValueKey('remote-directory-path'),
            controller: _path,
            label: l10n.remoteDirectoryPath,
            placeholder: l10n.remoteDirectoryPathPlaceholder,
            monospace: true,
            autocorrect: false,
            enableSuggestions: false,
            error: _pathErrorText(context),
            message: _typedStatusMessage(context),
            trailing: _typedStatusMark(context),
            onChanged: _typed,
            onSubmitted: (_) => _goToTyped(),
          ),
          if (failure != null) ...[
            const SizedBox(height: MeridianSpace.space4),
            failure,
          ],
          if (page?.truncated ?? false) ...[
            const SizedBox(height: MeridianSpace.space4),
            MeridianBanner(
              key: const ValueKey('remote-directory-truncated'),
              tone: MeridianBannerTone.info,
              message: l10n.remoteDirectoryTruncated,
            ),
          ],
          const SizedBox(height: MeridianSpace.space4),
          SizedBox(
            height: GitLamaLayout.remoteDirectoryListHeight,
            child: page == null
                ? Center(
                    child: _loading
                        ? const MeridianSpinner()
                        : Text(l10n.remoteDirectoryUnavailable),
                  )
                : shown.isEmpty && page.cursor == null
                ? MeridianEmptyState(
                    compact: true,
                    title: filter == null
                        ? l10n.remoteDirectoryEmpty
                        : l10n.remoteDirectoryNoMatch,
                  )
                : FocusTraversalGroup(
                    child: ListView(
                      key: const ValueKey('remote-directory-entries'),
                      controller: _scroll,
                      children: [
                        for (final entry in shown) _entry(entry),
                        if (page.cursor != null)
                          Padding(
                            padding: const EdgeInsets.all(MeridianSpace.space3),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: MeridianButton(
                                key: const ValueKey('remote-directory-more'),
                                label: l10n.remoteDirectoryLoadMore,
                                size: MeridianControlSize.small,
                                onPressed: _loading
                                    ? null
                                    : () => unawaited(_load(more: true)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('remote-directory-go'),
          label: l10n.remoteDirectoryGo,
          onPressed: _path.text.isEmpty ? null : _goToTyped,
        ),
        MeridianButton(
          key: const ValueKey('remote-directory-open'),
          label: initializing
              ? l10n.remoteInitializeHere
              : l10n.remoteDirectoryOpen,
          variant: MeridianButtonVariant.primary,
          onPressed: canOpen ? _open : null,
          disabledReason: canOpen ? null : l10n.remoteDirectoryOpenDisabled,
        ),
      ],
    );
  }
}
