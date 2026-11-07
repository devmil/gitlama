import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/repository_session_service.dart';
import '../../services/settings_service.dart';
import '../app_theme.dart';
import '../welcome_screen.dart' show repositoryFailureMessage;
import 'status_bar.dart';
import 'recent_repositories.dart';
import 'remote_workspace.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

class RepositoryChooser extends StatefulWidget {
  const RepositoryChooser({
    required this.tab,
    required this.repositories,
    required this.settings,
    super.key,
  });
  final RepositoryTabState tab;
  final RepositorySessionService repositories;
  final SettingsService settings;

  @override
  State<RepositoryChooser> createState() => _RepositoryChooserState();
}

class _RepositoryChooserState extends State<RepositoryChooser> {
  bool _busy = false;

  /// Why the last open from this chooser failed.
  RepositoryFailureCode? _failure;

  Future<void> _open([NativePathIdentity? recent]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.repositories.openFromChooser(widget.tab.id, recent: recent);
    } on RepositorySessionException catch (error) {
      if (mounted) setState(() => _failure = error.failure.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRemoteRecent(
    RemoteWorkspaceController remote,
    NativePathIdentity identity,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await remote.openRecent(
        context,
        identity,
        open: () async {
          await widget.repositories.openFromChooser(
            widget.tab.id,
            recent: identity,
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRemote(RemoteWorkspaceController remote) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await remote.openRemoteRepository(
        context,
        open: (identity) async {
          await widget.repositories.openFromChooser(
            widget.tab.id,
            recent: identity,
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final remote = RemoteWorkspaceScope.maybeOf(context);
    final recents = visibleRecents(
      widget.settings.current.recentRepositories,
      remote,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: GitLamaLayout.contentMaxWidth,
        ),
        child: ListView(
          key: const ValueKey('repository-chooser'),
          padding: const EdgeInsets.all(MeridianSpace.space9),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Image.asset(
                'assets/brand/tile-256.png',
                key: const ValueKey('repository-chooser-mark'),
                width: MeridianSize.control * 4,
                height: MeridianSize.control * 4,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(height: MeridianSpace.space2),
            Text(context.l10n.brandMaker, style: context.text.caption),
            const SizedBox(height: MeridianSpace.space6),
            Text(
              l10n.brandWelcome,
              style: context.text.title.copyWith(color: context.colors.ink),
            ),
            const SizedBox(height: MeridianSpace.space8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MeridianButton(
                key: const ValueKey('repository-chooser-browse'),
                label: l10n.openRepository,
                icon: 'folder-open',
                variant: MeridianButtonVariant.primary,
                onPressed: _busy ? null : () => _open(),
              ),
            ),
            if (remote != null && remote.enabled) ...[
              const SizedBox(height: MeridianSpace.space4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: MeridianButton(
                  key: const ValueKey('repository-chooser-remote'),
                  label: l10n.openRemoteRepository,
                  icon: 'server',
                  onPressed: _busy
                      ? null
                      : () => unawaited(_openRemote(remote)),
                ),
              ),
            ],
            if (_failure ?? widget.tab.failure?.code case final failure?) ...[
              const SizedBox(height: MeridianSpace.space6),
              MeridianBanner(
                tone: MeridianBannerTone.error,
                message: repositoryFailureMessage(context, failure),
              ),
            ],
            const SizedBox(height: MeridianSpace.space9),
            Text(
              l10n.recentRepositories,
              style: context.text.bodyStrong.copyWith(
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: MeridianSpace.space4),
            if (recents.isEmpty)
              Text(l10n.noRecentRepositories)
            else
              RecentRepositoryList(
                recents: recents,
                searchText: (identity) => identity.isRemote && remote != null
                    ? '${remoteRecentName(identity)} '
                          '${remoteRecentSubtitle(context, remote, identity)}'
                    : displayNativePath(identity),
                onSubmit: _busy
                    ? null
                    : (identity) => identity.isRemote && remote != null
                          ? unawaited(_openRemoteRecent(remote, identity))
                          : unawaited(_open(identity)),
                rowBuilder: (context, identity, query) =>
                    identity.isRemote && remote != null
                    ? MeridianListRow(
                        leading: const MeridianIcon('server'),
                        title: remoteRecentName(identity),
                        subtitle: remoteRecentSubtitle(
                          context,
                          remote,
                          identity,
                        ),
                        match: query,
                        onTap: _busy
                            ? null
                            : () => unawaited(
                                _openRemoteRecent(remote, identity),
                              ),
                      )
                    : MeridianListRow(
                        leading: const MeridianIcon('folder-history'),
                        title: displayNativePath(identity),
                        match: query,
                        onTap: _busy ? null : () => _open(identity),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a repository tab's context menu does.
