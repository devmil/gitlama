import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../models/reference_name.dart';
import '../../models/operation_center.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../widgets/gitlama_git_glyphs.dart';
import '../../widgets/native_menu.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';
import 'labels.dart';

/// What the repository details overlay shows about a tab: where the
/// repository lives, what it is and what is happening in it.
final class RepositoryDetails {
  const RepositoryDetails({
    required this.name,
    this.group,
    this.host,
    this.hostAlias,
    this.remote = false,
    this.hostDisconnected = false,
    this.path,
    this.kind,
    this.linkedWorktree = false,
    this.headKind,
    this.branch,
    this.headObjectId,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.changed = 0,
    this.conflicts = 0,
    this.inProgress = const [],
    this.operation,
    this.gitVersion,
  });

  /// The details of [tab]; [operations] supplies the work running in it.
  factory RepositoryDetails.of(
    RepositoryTabState tab, {
    required String name,
    String? group,
    String? host,
    String? hostAlias,
    bool remote = false,
    bool hostDisconnected = false,
    OperationCenterSnapshot? operations,
  }) {
    final snapshot = tab.session?.snapshot;
    final identity = snapshot?.identity;
    final status = snapshot?.status;
    final session = tab.session?.identity;
    final running = operations?.entries.where(
      (entry) =>
          entry.state == OperationCenterState.running &&
          session != null &&
          entry.session?.nativeId == session.nativeId &&
          entry.session?.generation == session.generation &&
          entry.session?.backend == session.backend,
    );
    return RepositoryDetails(
      name: name,
      group: group,
      host: host,
      hostAlias: hostAlias,
      remote: remote,
      hostDisconnected: hostDisconnected,
      path: tab.canonicalIdentity ?? tab.requestedIdentity,
      kind: identity?.kind,
      linkedWorktree:
          identity != null && identity.gitDir != identity.commonGitDir,
      headKind: identity?.headKind,
      branch: status == null
          ? _branchOf(identity?.headReference)
          : status.branchName,
      headObjectId: status?.headObjectId ?? identity?.headObjectId,
      upstream: status?.upstream,
      ahead: status?.ahead.toInt() ?? 0,
      behind: status?.behind.toInt() ?? 0,
      changed: status?.totalEntries.toInt() ?? 0,
      conflicts: status?.entries.where((entry) => entry.conflicted).length ?? 0,
      inProgress: [
        for (final operation
            in status?.operations ?? const <RepositoryOperationState>[])
          operation.kind,
      ],
      operation:
          running
              ?.where((entry) => entry.origin == OperationCenterOrigin.user)
              .firstOrNull ??
          running?.firstOrNull,
      gitVersion: identity == null
          ? null
          : '${identity.gitMajor}.${identity.gitMinor}.${identity.gitPatch}',
    );
  }

  /// The tab's name, as the Compass shows it.
  final String name;

  /// The name of the tab group it belongs to, if the group has one.
  final String? group;

  /// Whether the repository is on another computer.
  final bool remote;

  /// The host's name for a [remote] repository, when its profile is known.
  final String? host;

  /// The OpenSSH alias GitLama reaches [host] through.
  final String? hostAlias;
  final bool hostDisconnected;

  /// The worktree root, or the repository directory of a bare repository.
  final NativePathIdentity? path;
  final RepositoryKind? kind;
  final bool linkedWorktree;
  final HeadKind? headKind;
  final List<int>? branch;
  final String? headObjectId;
  final List<int>? upstream;
  final int ahead;
  final int behind;
  final int changed;
  final int conflicts;

  /// Git operations paused in the repository: a merge, rebase and so on.
  final List<RepositoryOperationKind> inProgress;

  /// The work GitLama runs in the repository now.
  final OperationCenterEntry? operation;
  final String? gitVersion;

  static List<int>? _branchOf(List<int>? reference) {
    if (reference == null) return null;
    final name = ReferenceName(reference);
    return name.kind == ReferenceKind.localBranch ? name.short : null;
  }
}

/// Opens the details overlay: the Compass at [anchor] grows into it, and it
/// shrinks back into the Compass when it closes.
Future<void> showRepositoryDetails({
  required BuildContext context,
  required WidgetBuilder builder,
  Rect? anchor,
}) {
  final reduced = MeridianMotion.reduced(context);
  if (anchor == null || reduced) {
    return showMeridianDialog<void>(
      context: context,
      builder: (context) => _DetailsMotionScope(
        progress: 1,
        anchor: anchor,
        child: builder(context),
      ),
    );
  }
  final spring = SpringSimulation(MeridianSprings.snappy, 0, 1, 0);
  return showMeridianDialog<void>(
    context: context,
    builder: builder,
    transitionDuration: GitLamaMotion.paletteMorph,
    reverseTransitionDuration: MeridianDurations.dialog,
    transitionBuilder: (context, animation, secondary, child) =>
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) => _DetailsMotionScope(
            progress: animation.status == AnimationStatus.reverse
                ? MeridianCurves.exit.transform(animation.value)
                : spring.x(0.3 * animation.value).clamp(0.0, 1.0),
            anchor: anchor,
            child: child,
          ),
        ),
  );
}

class _DetailsMotionScope extends InheritedWidget {
  const _DetailsMotionScope({
    required this.progress,
    required this.anchor,
    required super.child,
  });

  /// 0 is the Compass, 1 the open overlay.
  final double progress;
  final Rect? anchor;

  @override
  bool updateShouldNotify(_DetailsMotionScope oldWidget) =>
      progress != oldWidget.progress || anchor != oldWidget.anchor;
}

/// The overlay the Compass opens. It rebuilds from [read] whenever
/// [changes] fires, so a running operation and the status stay current;
/// it closes when [read] has no repository left to describe.
class RepositoryDetailsPanel extends StatefulWidget {
  const RepositoryDetailsPanel({
    super.key,
    required this.read,
    required this.changes,
    required this.fileBrowserName,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final RepositoryDetails? Function() read;
  final Listenable changes;
  final String fileBrowserName;
  final ValueChanged<NativePathIdentity> onCopyPath;
  final ValueChanged<NativePathIdentity> onOpenFolder;

  @override
  State<RepositoryDetailsPanel> createState() => _RepositoryDetailsPanelState();
}

class _RepositoryDetailsPanelState extends State<RepositoryDetailsPanel> {
  RepositoryDetails? _last;
  var _closing = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.changes,
    builder: (context, _) {
      final details = widget.read();
      if (details == null) {
        _close();
      } else {
        _last = details;
      }
      final shown = details ?? _last;
      if (shown == null) return const SizedBox.shrink();
      final motion = context
          .dependOnInheritedWidgetOfExactType<_DetailsMotionScope>();
      return _DetailsLayout(
        progress: motion?.progress ?? 1,
        anchor: motion?.anchor,
        semanticLabel: context.l10n.repositoryDetailsTitle,
        child: _DetailsContent(
          details: shown,
          fileBrowserName: widget.fileBrowserName,
          onCopyPath: widget.onCopyPath,
          onOpenFolder: (path) {
            Navigator.of(context).maybePop();
            widget.onOpenFolder(path);
          },
        ),
      );
    },
  );

  void _close() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }
}

/// Places the overlay where the Compass is and draws its surface between
/// the Compass's pill and the overlay's own bounds.
class _DetailsLayout extends StatelessWidget {
  const _DetailsLayout({
    required this.progress,
    required this.anchor,
    required this.semanticLabel,
    required this.child,
  });

  final double progress;
  final Rect? anchor;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final screen = constraints.biggest;
      const margin = MeridianSpace.space6;
      final available = math.max(0.0, screen.width - 2 * margin);
      final width = math.min(
        available,
        math.max(GitLamaLayout.repositoryDetailsWidth, anchor?.width ?? 0.0),
      );
      final source =
          anchor ??
          Rect.fromLTWH(
            (screen.width - width) / 2,
            (MeridianSize.toolbar - GitLamaLayout.compassHeight) / 2,
            width,
            GitLamaLayout.compassHeight,
          );
      final left = (source.center.dx - width / 2)
          .clamp(margin, math.max(margin, screen.width - margin - width))
          .toDouble();
      final top = source.top;
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0.0, screen.height - top - margin),
              ),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: semanticLabel,
                child: _MorphSurface(
                  progress: progress,
                  source: source.shift(Offset(-left, -top)),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _MorphSurface extends StatelessWidget {
  const _MorphSurface({
    required this.progress,
    required this.source,
    required this.child,
  });

  final double progress;

  /// The Compass in the surface's coordinates.
  final Rect source;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final shape = _MorphShape(
      progress: progress,
      source: source,
      radius: meridian.radius.lg,
    );
    return CustomPaint(
      painter: _MorphPainter(
        shape: shape,
        color: Color.lerp(
          meridian.colors.pane,
          meridian.colors.raised,
          progress,
        )!,
        shadows:
            BoxShadow.lerpList(
              meridian.shadows.shadowPane,
              meridian.shadows.shadowFloat,
              progress,
            ) ??
            const [],
      ),
      child: ClipPath(
        clipper: shape,
        child: Opacity(
          opacity: ((progress - 0.3) / 0.7).clamp(0.0, 1.0),
          child: MeridianTextScope(child: child),
        ),
      ),
    );
  }
}

/// The outline between the Compass's pill and the overlay's rounded
/// rectangle.
class _MorphShape extends CustomClipper<Path> {
  const _MorphShape({
    required this.progress,
    required this.source,
    required this.radius,
  });

  final double progress;
  final Rect source;
  final double radius;

  Path outline(Size size) {
    final rect = Rect.lerp(source, Offset.zero & size, progress)!;
    final corner = source.height / 2 * (1 - progress) + radius * progress;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(corner)));
  }

  @override
  Path getClip(Size size) => outline(size);

  @override
  bool shouldReclip(_MorphShape oldClipper) =>
      progress != oldClipper.progress ||
      source != oldClipper.source ||
      radius != oldClipper.radius;
}

class _MorphPainter extends CustomPainter {
  const _MorphPainter({
    required this.shape,
    required this.color,
    required this.shadows,
  });

  final _MorphShape shape;
  final Color color;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = shape.outline(size);
    for (final shadow in shadows) {
      canvas.drawPath(outline.shift(shadow.offset), shadow.toPaint());
    }
    canvas.drawPath(outline, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      shape.shouldReclip(oldDelegate.shape) ||
      color != oldDelegate.color ||
      !listEquals(shadows, oldDelegate.shadows);
}

/// How the repository is doing, from worst to best: the tone of the
/// overlay's header and of its tile.
enum _Health { unknown, conflicted, paused, busy, changed, clean }

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({
    required this.details,
    required this.fileBrowserName,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final RepositoryDetails details;
  final String fileBrowserName;
  final ValueChanged<NativePathIdentity> onCopyPath;
  final ValueChanged<NativePathIdentity> onOpenFolder;

  bool get _hasWorktree => details.kind != RepositoryKind.bare;

  _Health get _health => switch (details) {
    RepositoryDetails(conflicts: > 0) => _Health.conflicted,
    RepositoryDetails(inProgress: [_, ...]) => _Health.paused,
    RepositoryDetails(operation: _?) => _Health.busy,
    RepositoryDetails(gitVersion: null) => _Health.unknown,
    RepositoryDetails(changed: > 0) when _hasWorktree => _Health.changed,
    _ => _Health.clean,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final path = details.path;
    // A host GitLama cannot reach colours the overlay as a warning, whatever
    // its last known state.
    final (wash, ink) = details.hostDisconnected
        ? _toneOf(colors, _Health.paused)
        : _toneOf(colors, _health);
    return SingleChildScrollView(
      child: Column(
        key: const ValueKey('repository-details'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: MeridianMotion.reduced(context)
                ? Duration.zero
                : MeridianDurations.emphasized,
            curve: MeridianCurves.standard,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [wash, wash, meridianClear(wash)],
                stops: const [0, 0.4, 1],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              MeridianSpace.space6,
              MeridianSpace.space6,
              MeridianSpace.space6,
              MeridianSpace.space7,
            ),
            child: _header(context, wash, ink),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MeridianSpace.space6,
              0,
              MeridianSpace.space6,
              MeridianSpace.space6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (path != null) ...[
                  _PathWell(path: path, onCopy: () => onCopyPath(path)),
                  const SizedBox(height: MeridianSpace.space5),
                ],
                _stats(context),
                if (details.inProgress.isNotEmpty) ...[
                  const SizedBox(height: MeridianSpace.space5),
                  MeridianBanner(
                    tone: MeridianBannerTone.warning,
                    icon: 'git-merge',
                    title: l10n.repositoryDetailsInProgress,
                    message: [
                      for (final kind in details.inProgress)
                        repositoryOperationLabel(context, kind),
                    ].join(' · '),
                  ),
                ],
                const SizedBox(height: MeridianSpace.space5),
                _activity(context),
                const SizedBox(height: MeridianSpace.space5),
                const MeridianHairline(),
                const SizedBox(height: MeridianSpace.space5),
                _footer(context, path),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The wash behind the header and the ink of the header tile.
  static (Color, Color) _toneOf(MeridianColors colors, _Health health) =>
      switch (health) {
        _Health.conflicted => (colors.dangerBg, colors.danger),
        _Health.paused || _Health.changed => (colors.warningBg, colors.warning),
        _Health.busy => (colors.accentSoft, colors.accentInk),
        _Health.clean => (colors.successBg, colors.success),
        _Health.unknown => (colors.paneAlt, colors.inkMuted),
      };

  /// The one-line verdict under the repository's name.
  String? _headline(AppLocalizations l10n) => switch (_health) {
    _Health.conflicted => l10n.repositoryDetailsHealthConflicted,
    _Health.paused => l10n.repositoryDetailsHealthPaused,
    _Health.busy => l10n.repositoryDetailsHealthBusy,
    _Health.changed => l10n.repositoryDetailsHealthChanged,
    _Health.clean when !_hasWorktree => l10n.repositoryDetailsBare,
    _Health.clean => l10n.repositoryDetailsHealthClean,
    _Health.unknown => null,
  };

  static MeridianStatusTone _statusOf(_Health health) => switch (health) {
    _Health.conflicted => MeridianStatusTone.danger,
    _Health.paused || _Health.changed => MeridianStatusTone.warning,
    _Health.busy => MeridianStatusTone.accent,
    _Health.clean => MeridianStatusTone.success,
    _Health.unknown => MeridianStatusTone.neutral,
  };

  Widget _header(BuildContext context, Color wash, Color ink) {
    final l10n = context.l10n;
    final colors = context.colors;
    final headline = _headline(l10n);
    final location = switch ((
      details.remote,
      details.host,
      details.hostAlias,
    )) {
      (false, _, _) => l10n.repositoryDetailsThisComputer,
      (true, final host?, final alias?) when alias != host =>
        l10n.repositoryDetailsHostWithAlias(host, alias),
      (true, final host?, _) => host,
      (true, null, _) => l10n.remoteHostUnknown,
    };
    final kind = switch (details.kind) {
      null => null,
      // The headline already says it is bare.
      RepositoryKind.bare => (null, 'archive'),
      _ when details.linkedWorktree => (
        l10n.repositoryDetailsLinkedWorktree,
        'folder-symlink',
      ),
      _ => (l10n.repositoryDetailsWorktree, 'folder-closed'),
    };
    final radius = context.meridian.radius.lg;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension:
              GitLamaLayout.repositoryDetailsTileSize + MeridianSpace.space3,
          child: Stack(
            children: [
              Container(
                width: GitLamaLayout.repositoryDetailsTileSize,
                height: GitLamaLayout.repositoryDetailsTileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colors.raised, wash],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: ink),
                  boxShadow: context.meridian.shadows.shadowPane,
                ),
                child: MeridianIcon(
                  kind?.$2 ?? 'folder-closed',
                  extent: GitLamaLayout.repositoryDetailsTileIconSize,
                  color: ink,
                ),
              ),
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(MeridianSpace.space2),
                  decoration: BoxDecoration(
                    color: colors.raised,
                    shape: BoxShape.circle,
                  ),
                  child: MeridianStatusDot(
                    tone: details.hostDisconnected
                        ? MeridianStatusTone.warning
                        : _statusOf(_health),
                    halo: true,
                    live: _health == _Health.busy,
                    semanticLabel: headline,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: MeridianSpace.space5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                details.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.title.copyWith(color: colors.ink),
              ),
              if (headline != null)
                Text(
                  headline,
                  key: const ValueKey('repository-details-headline'),
                  style: context.text.label.copyWith(color: ink),
                ),
              const SizedBox(height: MeridianSpace.space4),
              Wrap(
                spacing: MeridianSpace.space3,
                runSpacing: MeridianSpace.space3,
                children: [
                  _labelled(
                    l10n.repositoryDetailsLocation,
                    MeridianChip(
                      key: const ValueKey('repository-details-location'),
                      label: details.hostDisconnected
                          ? '$location · ${l10n.repositoryDetailsDisconnected}'
                          : location,
                      icon: switch ((
                        details.remote,
                        details.hostDisconnected,
                      )) {
                        (true, true) => 'wifi-off',
                        (true, false) => 'server',
                        (false, _) => 'monitor',
                      },
                      tone: details.hostDisconnected
                          ? MeridianChipTone.warning
                          : MeridianChipTone.neutral,
                      maxWidth: GitLamaLayout.repositoryDetailsWidth,
                    ),
                  ),
                  if (kind?.$1 case final label?)
                    _labelled(
                      l10n.repositoryDetailsKind,
                      MeridianChip(
                        label: label,
                        maxWidth: GitLamaLayout.repositoryDetailsWidth,
                      ),
                    ),
                  if (details.group case final group?)
                    _labelled(
                      l10n.repositoryDetailsGroup,
                      MeridianChip(
                        label: group,
                        icon: 'layers',
                        tone: MeridianChipTone.accent,
                        maxWidth: GitLamaLayout.repositoryDetailsWidth,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Branch, upstream and changes side by side, stacked when narrow.
  Widget _stats(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final branch = details.branch;
    final headObjectId = details.headObjectId;
    final upstream = details.upstream;
    final shortId = headObjectId?.substring(
      0,
      math.min(8, headObjectId.length),
    );
    final tiles = <Widget>[
      if (branch != null || shortId != null)
        _StatTile(
          label: l10n.repositoryDetailsBranch,
          icon: 'git-branch',
          tint: colors.accentInk,
          value: branch != null
              ? utf8.decode(branch, allowMalformed: true)
              : l10n.compassDetachedAt(shortId!),
          detail: details.headKind == HeadKind.unborn
              ? _caption(context, l10n.repositoryDetailsUnborn)
              : branch != null && shortId != null
              ? Text(
                  shortId,
                  style: context.text.codeSm.copyWith(color: colors.inkMuted),
                )
              : null,
        ),
      if (_hasWorktree && branch != null)
        _StatTile(
          label: l10n.repositoryDetailsUpstream,
          icon: upstream == null ? 'unlink' : 'git-compare-arrows',
          tint: upstream == null ? colors.inkFaint : colors.accentInk,
          value: upstream == null
              ? l10n.repositoryDetailsNoUpstream
              : utf8.decode(upstream, allowMalformed: true),
          muted: upstream == null,
          detail: upstream == null
              ? null
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GitLamaSyncBadge(
                    ahead: details.ahead,
                    behind: details.behind,
                    showZero: true,
                  ),
                ),
        ),
      if (_hasWorktree && details.gitVersion != null)
        _StatTile(
          key: const ValueKey('repository-details-changes'),
          label: l10n.repositoryDetailsChanges,
          icon: details.conflicts > 0
              ? 'triangle-alert'
              : details.changed > 0
              ? 'file-diff'
              : 'circle-check',
          tint: details.conflicts > 0
              ? colors.danger
              : details.changed > 0
              ? colors.warning
              : colors.success,
          value: details.changed > 0
              ? l10n.compassChangedFiles(details.changed)
              : l10n.repositoryDetailsClean,
          detail: details.conflicts > 0
              ? Text(
                  l10n.compassConflicts(details.conflicts),
                  style: context.text.caption.copyWith(color: colors.danger),
                )
              : null,
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = MeridianSpace.space4 * (tiles.length - 1);
        final side =
            (constraints.maxWidth - gaps) / tiles.length >=
            GitLamaLayout.repositoryDetailsStatMinWidth;
        if (!side) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, tile) in tiles.indexed) ...[
                if (index > 0) const SizedBox(height: MeridianSpace.space4),
                tile,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, tile) in tiles.indexed) ...[
              if (index > 0) const SizedBox(width: MeridianSpace.space4),
              Expanded(child: tile),
            ],
          ],
        );
      },
    );
  }

  Widget _activity(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final operation = details.operation;
    final progress = operation?.progress;
    final label = operation == null
        ? l10n.repositoryDetailsIdle
        : switch (operationProgressLabel(context, progress)) {
            final detail? => l10n.operationRunningDetail(
              operationActionLabel(context, operation.action),
              detail,
            ),
            null => '${operationActionLabel(context, operation.action)}…',
          };
    return Semantics(
      container: true,
      label: l10n.repositoryDetailsRunning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              MeridianStatusDot(
                tone: operation == null
                    ? MeridianStatusTone.neutral
                    : MeridianStatusTone.accent,
                live: operation != null,
              ),
              const SizedBox(width: MeridianSpace.space4),
              Text(
                l10n.repositoryDetailsRunning,
                style: context.text.caption.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(width: MeridianSpace.space4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.body.copyWith(
                    color: operation == null ? colors.inkMuted : colors.ink,
                  ),
                ),
              ),
            ],
          ),
          if (operation != null) ...[
            const SizedBox(height: MeridianSpace.space3),
            MeridianProgressBar(
              value: progress?.total == null || progress!.total == BigInt.zero
                  ? null
                  : progress.completed.toDouble() / progress.total!.toDouble(),
              persistent: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, NativePathIdentity? path) {
    final l10n = context.l10n;
    final colors = context.colors;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: MeridianSpace.space4,
      runSpacing: MeridianSpace.space3,
      children: [
        if (details.gitVersion case final version?)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MeridianIcon(
                'terminal',
                size: MeridianIconSize.small,
                color: colors.inkFaint,
              ),
              const SizedBox(width: MeridianSpace.space3),
              Text(
                l10n.repositoryDetailsGit,
                style: context.text.caption.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(width: MeridianSpace.space3),
              Text(
                version,
                style: context.text.codeSm.copyWith(color: colors.inkMuted),
              ),
            ],
          )
        else
          const SizedBox.shrink(),
        if (path != null && !details.remote)
          MeridianButton(
            key: const ValueKey('repository-details-open-folder'),
            label: l10n.openInFileBrowser(fileBrowserName),
            icon: 'folder-open',
            variant: MeridianButtonVariant.quiet,
            onPressed: () => onOpenFolder(path),
          ),
      ],
    );
  }

  /// [chip] with what it shows as its tooltip and accessible name.
  static Widget _labelled(String label, Widget chip) => Tooltip(
    message: label,
    child: Semantics(label: label, child: chip),
  );

  static Widget _caption(BuildContext context, String text) => Text(
    text,
    style: context.text.caption.copyWith(color: context.colors.inkMuted),
  );
}

/// The repository's path in a code well, with its copy action.
class _PathWell extends StatelessWidget {
  const _PathWell({required this.path, required this.onCopy});

  final NativePathIdentity path;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        MeridianSpace.space5,
        MeridianSpace.space3,
        MeridianSpace.space3,
        MeridianSpace.space3,
      ),
      decoration: BoxDecoration(
        color: colors.paneAlt,
        borderRadius: BorderRadius.circular(context.meridian.radius.md),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          MeridianIcon(
            'folder',
            size: MeridianIconSize.small,
            color: colors.inkMuted,
          ),
          const SizedBox(width: MeridianSpace.space4),
          Expanded(
            child: Semantics(
              label: l10n.repositoryDetailsPath,
              child: SelectableText(
                contextMenuBuilder: nativeTextContextMenuBuilder,
                key: const ValueKey('repository-details-path'),
                path.displayText,
                style: context.text.codeSm.copyWith(color: colors.ink),
              ),
            ),
          ),
          const SizedBox(width: MeridianSpace.space3),
          MeridianIconButton(
            key: const ValueKey('repository-details-copy-path'),
            label: l10n.repositoryCopyPath,
            tooltip: l10n.repositoryCopyPath,
            icon: 'copy',
            size: MeridianControlSize.small,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

/// One fact about the repository: an icon and caption over its value.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.icon,
    required this.tint,
    required this.value,
    this.detail,
    this.muted = false,
  });

  final String label;
  final String icon;
  final Color tint;
  final String value;
  final Widget? detail;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detail = this.detail;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: GitLamaLayout.repositoryDetailsStatMinHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.pane,
          borderRadius: BorderRadius.circular(context.meridian.radius.lg),
          border: Border.all(color: colors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MeridianSpace.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  MeridianIcon(icon, size: MeridianIconSize.small, color: tint),
                  const SizedBox(width: MeridianSpace.space3),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.caption.copyWith(
                        color: colors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MeridianSpace.space3),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: muted
                    ? context.text.body.copyWith(color: colors.inkMuted)
                    : context.text.heading.copyWith(color: colors.ink),
              ),
              if (detail != null) ...[
                const SizedBox(height: MeridianSpace.space2),
                detail,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
