part of '../workspace_shell.dart';

/// The shell's hosting account view of the active repository: its session,
/// resources, branch decorations and pull-request links.
extension _ShellHosting on _WorkspaceShellState {
  void _updateHostingSession() {
    // Provider requests run on this computer with its accounts. Remote
    // repository identities are metadata keys, never local filesystem paths.
    unawaited(
      _hostingSession.update(_active?.canonicalIdentity, [
        for (final remote
            in _active?.session?.snapshot.refs.remotes ??
                const <RepositoryRemote>[])
          HostingRemote(
            name: remote.name,
            url: utf8.decode(remote.displayUrl, allowMalformed: true),
          ),
      ]),
    );
  }

  /// Pull-request links for the active repository once its hosting binding
  /// has resolved. The checked-out branch is always looked up.
  HostingLinks? _hostingLinks() {
    final session = _hostingSession;
    final hosting = widget.hosting;
    final active = _active;
    final snapshot = active?.session?.snapshot;
    if (snapshot == null ||
        session.repository != active?.canonicalIdentity ||
        session.binding?.state != HostingBindingState.bound) {
      return null;
    }
    final links = HostingLinks(
      session: session,
      refs: snapshot.refs,
      onOpen: (url) => unawaited(hosting.openBrowser(url)),
    );
    links.request(ReferenceProjection.of(snapshot.refs).checkedOutRef);
    return links;
  }

  void _hostingSessionChanged() {
    final session = _hostingSession;
    _hostingResourcesChanged(
      session.binding,
      session.resources,
      session.snapshot?.stale ?? false,
    );
  }

  void _hostingResourcesChanged(
    HostingBindingResolution? binding,
    HostingResources resources,
    bool stale,
  ) {
    if (mounted) {
      _update(() {
        _hostingResourcesRepository = _active?.canonicalIdentity;
        _hostingResources = resources;
        _hostingResourcesStale = stale;
        _hostingBinding = binding;
        _hostingBranchDecorations = hostingBranchDecorations(
          binding,
          resources,
        );
      });
    }
  }
}
