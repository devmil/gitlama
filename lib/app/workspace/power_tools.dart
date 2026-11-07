import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/l10n.dart';
import '../../models/power_tools.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/gitlama_workflow_header.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';
import '../../widgets/gitlama_list_well.dart';
import '../workspace_shell.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../services/workflows/polled_job.dart';
import '../../widgets/command_preview.dart';
import 'reference_projection.dart';
import 'remote_workspace.dart';
import '../../widgets/status_notification.dart';

enum _PowerToolsSection { search, statistics, bisect }

class PowerToolsPanel extends StatefulWidget {
  const PowerToolsPanel({
    required this.repositories,
    required this.onClose,
    required this.onReveal,
    this.docked = false,
    super.key,
  });

  final RepositorySessionService repositories;
  final VoidCallback onClose;
  final ValueChanged<String> onReveal;
  final bool docked;

  @override
  State<PowerToolsPanel> createState() => _PowerToolsPanelState();
}

class _PowerToolsPanelState extends State<PowerToolsPanel> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _good = TextEditingController();
  final TextEditingController _bad = TextEditingController();

  /// The running content search and statistics; they poll and cancel in
  /// [PolledJob], not here.
  PolledJob<DiffContentSearchResult>? _searchJob;
  PolledJob<RepositoryStatisticsResult>? _statisticsJob;
  DiffContentSearchResult? _search;
  RepositoryStatisticsResult? _statistics;
  BisectState? _bisect;
  bool _bisectBusy = false;
  bool _failed = false;
  bool _caseSensitive = false;
  DiffSearchScope _searchScope = DiffSearchScope.allRefs;
  _PowerToolsSection _section = _PowerToolsSection.search;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBisect());
  }

  @override
  void dispose() {
    unawaited(_searchJob?.stop());
    unawaited(_statisticsJob?.stop());
    _query.dispose();
    _good.dispose();
    _bad.dispose();
    super.dispose();
  }

  Future<void> _loadBisect() async {
    try {
      final value = await widget.repositories.powerTools.bisectState();
      if (mounted) setState(() => _bisect = value);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _startSearch() async {
    final query = _query.text;
    if (query.trim().isEmpty || _searchJob != null) return;
    final powerTools = widget.repositories.powerTools;
    final job = PolledJob<DiffContentSearchResult>(
      start: () => powerTools.startDiffContentSearch(
        query: query,
        caseSensitive: _caseSensitive,
        scope: _searchScope,
      ),
      poll: powerTools.pollDiffContentSearch,
      pending: (result) => result.state == PowerJobState.pending,
      cancel: powerTools.cancelJob,
    );
    setState(() {
      _failed = false;
      _search = null;
      _searchJob = job;
    });
    try {
      final result = await job.run();
      if (!mounted || !identical(_searchJob, job)) return;
      setState(() {
        _searchJob = null;
        if (result != null) {
          _search = result;
          _failed = result.state == PowerJobState.failed;
        }
      });
    } on Object {
      if (mounted && identical(_searchJob, job)) {
        setState(() {
          _searchJob = null;
          _failed = true;
        });
      }
    }
  }

  Future<void> _cancelSearch() async {
    final job = _searchJob;
    if (job == null) return;
    setState(() => _searchJob = null);
    await job.stop();
  }

  Future<void> _loadStatistics() async {
    if (_statisticsJob != null) return;
    final powerTools = widget.repositories.powerTools;
    final job = PolledJob<RepositoryStatisticsResult>(
      start: powerTools.startRepositoryStatistics,
      poll: powerTools.pollRepositoryStatistics,
      pending: (result) => result.state == PowerJobState.pending,
      cancel: powerTools.cancelJob,
    );
    setState(() {
      _statistics = null;
      _failed = false;
      _statisticsJob = job;
    });
    try {
      final result = await job.run();
      if (!mounted || !identical(_statisticsJob, job)) return;
      setState(() {
        _statisticsJob = null;
        if (result != null) {
          _statistics = result;
          _failed = result.state == PowerJobState.failed;
        }
      });
    } on Object {
      if (mounted && identical(_statisticsJob, job)) {
        setState(() {
          _statisticsJob = null;
          _failed = true;
        });
      }
    }
  }

  Future<void> _runBisect(BisectAction action) async {
    if (_bisectBusy) return;
    // Bisect checks out commits: a host must allow history changes.
    final remoteReason = remoteWriteReason(
      context,
      RemoteCapability.history,
      listen: false,
    );
    if (remoteReason != null) {
      StatusNotificationScope.show(context, remoteReason);
      return;
    }
    setState(() {
      _bisectBusy = true;
      _failed = false;
    });
    BisectPreview? preview;
    try {
      preview = await widget.repositories.powerTools.previewBisect(
        action,
        good: action == BisectAction.start ? _good.text.trim() : null,
        bad: action == BisectAction.start ? _bad.text.trim() : null,
      );
      if (!mounted) return;
      final confirmed = await showMeridianConfirm(
        context,
        title: switch (action) {
          BisectAction.start => context.l10n.bisectStartTitle,
          BisectAction.good => context.l10n.bisectGoodTitle,
          BisectAction.bad => context.l10n.bisectBadTitle,
          BisectAction.skip => context.l10n.bisectSkipTitle,
          BisectAction.reset => context.l10n.bisectResetTitle,
        },
        confirmLabel: switch (action) {
          BisectAction.start => context.l10n.powerBisectStart,
          BisectAction.good => context.l10n.bisectConfirmGood,
          BisectAction.bad => context.l10n.bisectConfirmBad,
          BisectAction.skip => context.l10n.powerBisectSkip,
          BisectAction.reset => context.l10n.powerBisectReset,
        },
        cancelLabel: context.l10n.cancel,
        content: GitLamaCommandPreviewContent(
          summary: switch (action) {
            BisectAction.start => context.l10n.bisectStartSummary,
            BisectAction.good => context.l10n.bisectGoodSummary,
            BisectAction.bad => context.l10n.bisectBadSummary,
            BisectAction.skip => context.l10n.bisectSkipSummary,
            BisectAction.reset => context.l10n.bisectResetSummary,
          },
          commandLines: [
            ['git', ...preview.arguments].join(' '),
          ],
        ),
      );
      if (!confirmed) {
        await widget.repositories.powerTools.cancelBisectPreview(preview);
        return;
      }
      final result = await widget.repositories.powerTools.executeBisect(
        preview,
      );
      if (!mounted) return;
      if (result.state == BisectExecutionState.outcomeUncertain) {
        StatusNotificationScope.show(
          context,
          context.l10n.mutationOutcomeUncertain,
          error: true,
        );
      }
      setState(() {
        _bisect = result.bisect;
        _failed =
            result.state != BisectExecutionState.completed &&
            result.state != BisectExecutionState.outcomeUncertain;
      });
    } on RemoteOutcomeUnknownException {
      if (mounted) showRemoteOutcomeUnknown(context);
    } on Object {
      if (preview != null) {
        await widget.repositories.powerTools.cancelBisectPreview(preview);
      }
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _bisectBusy = false);
    }
  }

  Widget _searchSection(BuildContext context) {
    final search = _search;
    final caption = context.text.caption.copyWith(
      color: context.colors.inkMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        MeridianTextField(
          fieldKey: const Key('power-search-query'),
          controller: _query,
          enabled: _searchJob == null,
          label: context.l10n.powerSearchQuery,
          message: context.l10n.powerSearchBound,
          onSubmitted: (_) => unawaited(_startSearch()),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: MeridianSpace.space6,
          children: [
            Expanded(
              child: Wrap(
                spacing: MeridianSpace.space6,
                runSpacing: MeridianSpace.space4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MeridianSegmented<DiffSearchScope>(
                    label: context.l10n.powerSearchScope,
                    segments: [
                      for (final scope in DiffSearchScope.values)
                        MeridianSegment(
                          value: scope,
                          label: switch (scope) {
                            DiffSearchScope.allRefs =>
                              context.l10n.powerSearchAllRefs,
                            DiffSearchScope.currentBranch =>
                              context.l10n.powerSearchCurrentBranch,
                          },
                        ),
                    ],
                    value: _searchScope,
                    onChanged: (scope) {
                      if (_searchJob == null) {
                        setState(() => _searchScope = scope);
                      }
                    },
                  ),
                  MeridianCheckbox(
                    value: _caseSensitive,
                    label: context.l10n.powerSearchCaseSensitive,
                    onChanged: _searchJob == null
                        ? (value) => setState(() => _caseSensitive = value)
                        : null,
                  ),
                ],
              ),
            ),
            _searchJob == null
                ? MeridianButton(
                    key: const Key('power-search-start'),
                    label: context.l10n.powerSearchAction,
                    variant: MeridianButtonVariant.primary,
                    onPressed: _startSearch,
                  )
                : MeridianButton(
                    key: const Key('power-search-cancel'),
                    label: context.l10n.powerSearchCancel,
                    onPressed: _cancelSearch,
                  ),
          ],
        ),
        if (search != null) ...[
          if (search.completeness == SearchCompleteness.commitLimitReached)
            MeridianBanner(
              tone: MeridianBannerTone.info,
              message: context.l10n.powerSearchIncompleteCommits,
            ),
          if (search.completeness == SearchCompleteness.resultLimitReached)
            MeridianBanner(
              tone: MeridianBannerTone.info,
              message: context.l10n.powerSearchIncompleteResults,
            ),
          if (search.matches.isEmpty)
            Text(
              key: const Key('power-search-summary'),
              '${context.l10n.powerSearchFound(0)} · '
              '${context.l10n.powerSearchExamined(search.examinedCommits)}',
              style: caption,
            )
          else
            GitLamaListWell(
              header: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: MeridianSpace.space6,
                  end: MeridianSpace.space3,
                  top: MeridianSpace.space4,
                ),
                child: Text(
                  key: const Key('power-search-summary'),
                  '${context.l10n.powerSearchFound(search.matches.length)} · '
                  '${context.l10n.powerSearchExamined(search.examinedCommits)}',
                  style: caption,
                ),
              ),
              itemCount: search.matches.length,
              itemBuilder: (context, index) {
                final match = search.matches[index];
                return MeridianListRow(
                  leading: const MeridianIcon(
                    'git-commit-horizontal',
                    size: MeridianIconSize.small,
                  ),
                  title: match.summary,
                  meta: _shortCommit(match.commit),
                  onTap: () => widget.onReveal(match.commit),
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _statisticsSection(BuildContext context) {
    final statistics = _statistics;
    if (statistics == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: MeridianButton(
          key: const Key('power-statistics-load'),
          label: context.l10n.powerStatisticsLoad,
          onPressed: _statisticsJob == null ? _loadStatistics : null,
        ),
      );
    }
    final number = NumberFormat.decimalPattern(context.l10n.localeName);
    MeridianProperty fact(String label, int value) => MeridianProperty(
      label: label,
      value: number.format(value),
      selectable: false,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space4,
      children: [
        MeridianPropertyList(
          key: const Key('power-statistics-facts'),
          properties: [
            fact(context.l10n.powerStatisticsCommits, statistics.commitCount),
            fact(
              context.l10n.powerStatisticsBranches,
              statistics.localBranchCount,
            ),
            fact(context.l10n.powerStatisticsTags, statistics.tagCount),
            fact(
              context.l10n.powerStatisticsChangedFiles,
              statistics.changedPathCount,
            ),
          ],
        ),
        if (statistics.incomplete)
          Text(
            context.l10n.powerStatisticsIncomplete,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
      ],
    );
  }

  Widget _bisectSection(BuildContext context) {
    final bisect = _bisect;
    if (bisect == null) return const Center(child: MeridianSpinner());
    if (!bisect.active) {
      final choices =
          ReferenceProjection.of(
            widget.repositories.workspace.activeTab?.session?.snapshot.refs ??
                const RepositoryRefs(),
          ).choices(
            widget.repositories.history.referencePickerCommitsFor(
              widget.repositories.workspace.activeTab?.session?.identity,
            ),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          Text(
            context.l10n.powerBisectHelp,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
          GitReferenceField(
            key: const Key('power-bisect-good'),
            controller: _good,
            label: context.l10n.powerBisectGood,
            names: const [],
            choices: choices,
          ),
          GitReferenceField(
            key: const Key('power-bisect-bad'),
            controller: _bad,
            label: context.l10n.powerBisectBad,
            names: const [],
            choices: choices,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MeridianButton(
              key: const Key('power-bisect-start'),
              label: context.l10n.powerBisectStart,
              variant: MeridianButtonVariant.primary,
              onPressed: _bisectBusy
                  ? null
                  : () => _runBisect(BisectAction.start),
            ),
          ),
        ],
      );
    }
    VoidCallback? run(BisectAction action) =>
        _bisectBusy ? null : () => _runBisect(action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        MeridianPropertyList(
          properties: [
            MeridianProperty(
              label: context.l10n.powerBisectTesting,
              value: switch (bisect.current) {
                final current? => _shortCommit(current),
                null => '—',
              },
              monospace: bisect.current != null,
            ),
            MeridianProperty(
              label: context.l10n.powerBisectProgressLabel,
              value: context.l10n.powerBisectProgress(
                bisect.timeline.length,
                bisect.remainingSteps ?? 0,
              ),
              selectable: false,
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: MeridianSpace.space4,
          children: [
            Text(
              context.l10n.powerBisectQuestion,
              style: context.text.body.copyWith(color: context.colors.ink),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: MeridianSpace.space4,
                    runSpacing: MeridianSpace.space4,
                    children: [
                      MeridianButton(
                        label: context.l10n.powerBisectMarkGood,
                        icon: 'circle-check',
                        onPressed: run(BisectAction.good),
                      ),
                      MeridianButton(
                        label: context.l10n.powerBisectMarkBad,
                        icon: 'bug',
                        onPressed: run(BisectAction.bad),
                      ),
                      MeridianButton(
                        label: context.l10n.powerBisectSkip,
                        variant: MeridianButtonVariant.quiet,
                        onPressed: run(BisectAction.skip),
                      ),
                    ],
                  ),
                ),
                MeridianButton(
                  label: context.l10n.powerBisectReset,
                  variant: MeridianButtonVariant.quiet,
                  onPressed: run(BisectAction.reset),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String title(_PowerToolsSection section) => switch (section) {
      _PowerToolsSection.search => context.l10n.powerSearchTitle,
      _PowerToolsSection.statistics => context.l10n.powerStatisticsTitle,
      _PowerToolsSection.bisect => context.l10n.powerBisectTitle,
    };
    Widget body(_PowerToolsSection section) => switch (section) {
      _PowerToolsSection.search => _searchSection(context),
      _PowerToolsSection.statistics => _statisticsSection(context),
      _PowerToolsSection.bisect => _bisectSection(context),
    };
    final content = SizedBox(
      height: widget.docked
          ? math.min(
              GitLamaLayout.powerToolsDockedMaxHeight,
              MediaQuery.sizeOf(context).height *
                  GitLamaLayout.powerToolsDockedHeightFraction,
            )
          : floatingPanelBodyHeight(
              context,
              GitLamaLayout.powerToolsBodyHeight,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchJob != null || _statisticsJob != null || _bisectBusy)
            const MeridianProgressBar(),
          if (_failed)
            Padding(
              padding: const EdgeInsets.all(MeridianSpace.space5),
              child: MeridianBanner(
                tone: MeridianBannerTone.error,
                message: context.l10n.powerFailed,
              ),
            ),
          if (widget.docked)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MeridianSpace.space5,
                MeridianSpace.space2,
                MeridianSpace.space5,
                MeridianSpace.space2,
              ),
              child: MeridianSegmented<_PowerToolsSection>(
                label: context.l10n.powerToolsTitle,
                expand: true,
                segments: [
                  for (final section in _PowerToolsSection.values)
                    MeridianSegment(value: section, label: title(section)),
                ],
                value: _section,
                onChanged: (section) => setState(() => _section = section),
              ),
            ),
          Expanded(
            child: ListView(
              key: const Key('power-tools-list'),
              padding: EdgeInsets.zero,
              children: [
                if (widget.docked)
                  Padding(
                    padding: const EdgeInsets.all(MeridianSpace.space5),
                    child: body(_section),
                  )
                else
                  for (final section in _PowerToolsSection.values) ...[
                    MeridianSectionHeader(
                      icon: switch (section) {
                        _PowerToolsSection.search => 'text-search',
                        _PowerToolsSection.statistics => 'chart-column',
                        _PowerToolsSection.bisect => 'bug',
                      },
                      title: title(section),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        MeridianSpace.space5,
                        MeridianSpace.space5,
                        MeridianSpace.space5,
                        MeridianSpace.space8,
                      ),
                      child: body(section),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.docked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GitLamaWorkflowHeader(
            title: context.l10n.powerToolsTitle,
            exitLabel: context.l10n.close,
            onExit: widget.onClose,
          ),
          ColoredBox(color: context.colors.paneAlt, child: content),
          const MeridianHairline(),
        ],
      );
    }
    return MeridianPanel(
      title: context.l10n.powerToolsTitle,
      onClose: widget.onClose,
      width: math.min(
        GitLamaLayout.powerToolsPanelWidth,
        MediaQuery.sizeOf(context).width - MeridianSpace.space3 * 2,
      ),
      padding: EdgeInsets.zero,
      child: content,
    );
  }
}

/// A commit ID shortened for reading; anything else unchanged.
String _shortCommit(String commit) =>
    RegExp(r'^[0-9a-f]{40,64}$').hasMatch(commit)
    ? commit.substring(0, 10)
    : commit;
