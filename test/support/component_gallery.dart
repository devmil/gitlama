// The developer gallery of GitLama's domain components. It lives with the
// tests: production cannot reach it, and its golden tests render it.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:gitlama/l10n/l10n.dart';
import 'package:gitlama/widgets/author_avatar.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';
import 'package:gitlama/widgets/gitlama_repo_tabs.dart';
import 'package:gitlama/widgets/gitlama_ref_chip.dart';
import 'package:gitlama/widgets/history_graph_view.dart';
import 'package:gitlama/widgets/diff_view.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';
import 'package:gitlama/widgets/gitlama_composer.dart';
import 'package:gitlama/widgets/gitlama_timeline_row.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/widgets/gitlama_git_glyphs.dart';

class ComponentGallery extends StatefulWidget {
  const ComponentGallery({super.key});

  @override
  State<ComponentGallery> createState() => _ComponentGalleryState();
}

class _ComponentGalleryState extends State<ComponentGallery> {
  var activations = 0;
  var selectedMenu = '';
  var checked = true;
  var switched = false;
  late final TextEditingController _refController = TextEditingController(
    text: context.l10n.galleryRefValue,
  );
  late final TextEditingController _invalidRefController =
      TextEditingController(text: context.l10n.galleryInvalidRef);

  @override
  void dispose() {
    _refController.dispose();
    _invalidRefController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final menuItems = [
      l10n.galleryHistory,
      l10n.galleryChanges,
      l10n.galleryActivity,
    ];
    final displayedMenu = selectedMenu.isEmpty ? menuItems.first : selectedMenu;
    final activeSegment = displayedMenu == menuItems.last
        ? menuItems.first
        : displayedMenu;
    Widget section(String title, Widget child) => MeridianIsland(
      title: title,
      child: Padding(
        padding: const EdgeInsets.all(MeridianSpace.space6),
        child: child,
      ),
    );
    Widget gap() => const SizedBox(height: MeridianSpace.space5);
    final diffRows = [
      DiffDisplayRow(
        stableId: 'hunk',
        kind: DiffRowKind.hunk,
        text: utf8.encode(l10n.galleryDiffSampleHunk),
      ),
      DiffDisplayRow(
        stableId: 'context',
        kind: DiffRowKind.context,
        text: utf8.encode(l10n.galleryDiffSampleContext),
        oldLine: 169,
        newLine: 169,
      ),
      DiffDisplayRow(
        stableId: 'deleted',
        kind: DiffRowKind.deletion,
        text: utf8.encode(l10n.galleryDiffSampleDeleted),
        oldLine: 170,
        selectable: true,
      ),
      DiffDisplayRow(
        stableId: 'added',
        kind: DiffRowKind.addition,
        text: utf8.encode(l10n.galleryDiffSampleAdded),
        newLine: 170,
        selectable: true,
        intraLine: const [DiffSpan(6, 16)],
      ),
      DiffDisplayRow(
        stableId: 'no-newline',
        kind: DiffRowKind.noNewline,
        text: const [],
      ),
    ];
    return Scaffold(
      backgroundColor: colors.ground,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _Specimen.pageWidth),
            child: Padding(
              padding: const EdgeInsets.all(MeridianSpace.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.galleryTitle, style: context.text.title),
                  gap(),
                  section(
                    l10n.gallerySectionButton,
                    Wrap(
                      spacing: MeridianSpace.space4,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        MeridianButton(
                          label: l10n.galleryCommitToMain,
                          variant: MeridianButtonVariant.primary,
                          shortcut: const ['⌘', '↵'],
                          onPressed: () => setState(() => activations += 1),
                        ),
                        MeridianButton(
                          label: l10n.galleryOpenRepository,
                          icon: 'folder-open',
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryPush,
                          icon: 'push',
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryCopyHash,
                          icon: 'copy',
                          variant: MeridianButtonVariant.quiet,
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryDiscardThreeFiles,
                          variant: MeridianButtonVariant.danger,
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryDiscard,
                          icon: 'undo',
                          variant: MeridianButtonVariant.dangerQuiet,
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryFetching,
                          loading: true,
                          onPressed: null,
                        ),
                        MeridianButton(
                          label: l10n.galleryPull,
                          onPressed: null,
                        ),
                        MeridianButton(
                          label: l10n.galleryCommit,
                          variant: MeridianButtonVariant.primary,
                          onPressed: null,
                        ),
                        MeridianButton(
                          label: l10n.galleryStageHunk,
                          icon: 'stage-all',
                          size: MeridianControlSize.small,
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryShowAllFiles,
                          variant: MeridianButtonVariant.quiet,
                          size: MeridianControlSize.small,
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryUnavailableAction,
                          onPressed: null,
                          disabledReason: l10n.galleryUnavailableReason,
                        ),
                        MeridianButton(
                          label: l10n.galleryLoadingRepository,
                          onPressed: null,
                          loading: true,
                        ),
                        MeridianMenuAnchor(
                          entries: [
                            for (final item in menuItems)
                              MeridianMenuItem(
                                label: item,
                                checked: item == selectedMenu,
                                onSelected: () =>
                                    setState(() => selectedMenu = item),
                              ),
                          ],
                          builder: (context, open) => MeridianIconButton(
                            label: l10n.galleryWorkspaceMenu,
                            icon: 'more',
                            onPressed: open,
                          ),
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionIconButton,
                    Wrap(
                      spacing: MeridianSpace.space4,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        MeridianIconButton(
                          label: l10n.galleryRefresh,
                          icon: 'refresh',
                          onPressed: () => setState(() => activations += 1),
                        ),
                        MeridianIconButton(
                          label: l10n.galleryFilter,
                          icon: 'list-filter-plus',
                          onPressed: () {},
                        ),
                        MeridianIconButton(
                          label: l10n.gallerySideBySide,
                          icon: 'side-by-side',
                          active: true,
                          onPressed: () {},
                        ),
                        MeridianIconButton(
                          label: l10n.galleryUnified,
                          icon: 'unified-diff',
                          active: false,
                          onPressed: () {},
                        ),
                        MeridianIconButton(
                          label: l10n.galleryMore,
                          icon: 'more',
                          onPressed: () {},
                        ),
                        MeridianIconButton(
                          label: l10n.galleryCopy,
                          icon: 'copy',
                          size: MeridianControlSize.small,
                          onPressed: () {},
                        ),
                        MeridianIconButton(
                          label: l10n.galleryStage,
                          icon: 'stage-all',
                          size: MeridianControlSize.small,
                          onPressed: () {},
                        ),
                        MeridianIconButton(
                          label: l10n.galleryDelete,
                          icon: 'trash',
                          size: MeridianControlSize.small,
                          onPressed: null,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionToolbarButton,
                    Wrap(
                      spacing: MeridianSpace.space1,
                      children: [
                        MeridianToolbarButton(
                          label: l10n.galleryFetch,
                          icon: 'fetch',
                          onPressed: () => setState(() => activations += 1),
                        ),
                        MeridianToolbarButton(
                          label: l10n.galleryPull,
                          icon: 'pull',
                          badge: 6,
                          onPressed: () {},
                        ),
                        MeridianToolbarButton(
                          label: l10n.galleryPush,
                          icon: 'push',
                          onPressed: () {},
                        ),
                        MeridianToolbarButton(
                          label: l10n.galleryStash,
                          icon: 'stash',
                          onPressed: () {},
                        ),
                        MeridianToolbarButton(
                          label: l10n.galleryBranch,
                          icon: 'branch',
                          onPressed: () {},
                        ),
                        MeridianToolbarButton(
                          label: l10n.galleryMerge,
                          icon: 'git-merge',
                          onPressed: null,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionCheckbox,
                    Wrap(
                      spacing: MeridianSpace.space7,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        MeridianCheckbox(
                          label: l10n.gallerySignCommit,
                          value: checked,
                          onChanged: (value) => setState(() => checked = value),
                        ),
                        MeridianCheckbox(
                          label: l10n.galleryAmend,
                          value: false,
                          onChanged: (_) {},
                        ),
                        MeridianCheckbox(
                          label: l10n.galleryStageAllMixed,
                          value: null,
                          tristate: true,
                          onChanged: (_) {},
                        ),
                        MeridianCheckbox(
                          label: l10n.galleryBypassHooks,
                          value: false,
                          onChanged: null,
                        ),
                        MeridianSwitch(
                          label: l10n.galleryFetchAutomatically,
                          value: !switched,
                          onChanged: (value) =>
                              setState(() => switched = !value),
                        ),
                        MeridianSwitch(
                          label: l10n.galleryIncludeTags,
                          value: false,
                          onChanged: (_) {},
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionSegmented,
                    Wrap(
                      spacing: MeridianSpace.space4,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        MeridianSegmented<String>(
                          label: l10n.galleryDiffLayout,
                          segments: [
                            for (final item in [
                              l10n.galleryUnified,
                              l10n.gallerySplit,
                            ])
                              MeridianSegment(
                                value: item,
                                label: item,
                                icon: item == l10n.galleryUnified
                                    ? 'unified-diff'
                                    : 'side-by-side',
                              ),
                          ],
                          value: l10n.galleryUnified,
                          onChanged: (_) {},
                        ),
                        MeridianSegmented<String>(
                          label: l10n.galleryFileList,
                          segments: [
                            for (final value in [
                              l10n.galleryList,
                              l10n.galleryTree,
                            ])
                              MeridianSegment(
                                value: value,
                                icon: value == l10n.galleryList
                                    ? 'list-view'
                                    : 'tree-view',
                                tooltip: value,
                              ),
                          ],
                          value: l10n.galleryTree,
                          onChanged: (_) {},
                        ),
                        MeridianSegmented<String>(
                          label: l10n.settingsTheme,
                          segments: [
                            for (final item in [
                              l10n.settingsThemeLight,
                              l10n.settingsThemeDark,
                              l10n.galleryThemeSystem,
                            ])
                              MeridianSegment(value: item, label: item),
                          ],
                          value: l10n.galleryThemeSystem,
                          size: MeridianControlSize.small,
                          onChanged: (_) {},
                        ),
                        MeridianSegmented<String>(
                          label: l10n.galleryWorkspaceMenu,
                          segments: [
                            for (final item
                                in menuItems.take(2).toList(growable: false))
                              MeridianSegment(value: item, label: item),
                          ],
                          value: activeSegment,
                          onChanged: (item) =>
                              setState(() => selectedMenu = item),
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionSelect,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MeridianSelect<String>(
                        value: l10n.settingsDateRelative,
                        values: [
                          l10n.settingsDateRelative,
                          l10n.settingsDateLocal,
                          l10n.settingsDateIso,
                        ],
                        valueLabel: (item) => item,
                        width: _Specimen.selectWidth,
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionTextField,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: MeridianSpace.space4,
                          runSpacing: MeridianSpace.space4,
                          children: [
                            MeridianTextField(
                              showLabel: false,
                              variant: MeridianTextFieldVariant.search,
                              icon: 'inspect',
                              placeholder: l10n.gallerySearchCommits,
                              trailingText: '0/0',
                              width: _Specimen.fieldWidth,
                            ),
                            MeridianTextField(
                              showLabel: false,
                              placeholder: l10n.galleryRefPlaceholder,
                              controller: _refController,
                            ),
                          ],
                        ),
                        const SizedBox(height: MeridianSpace.space4),
                        MeridianTextField(
                          showLabel: false,
                          controller: _invalidRefController,
                          error: l10n.galleryInvalidRefMessage,
                          width: _Specimen.fieldWidth,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionCompass,
                    Center(
                      child: GitLamaCompass(
                        repository: l10n.appTitle,
                        branch: l10n.galleryRefValue,
                        ahead: 2,
                        behind: 1,
                        dirty: 3,
                        onShowDetails: () => setState(() => activations++),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionPalette,
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: GitLamaLayout.paletteWidth,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.raised,
                            borderRadius: BorderRadius.circular(
                              context.meridian.radius.xl,
                            ),
                            boxShadow: context.meridian.shadows.shadowFloat,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              context.meridian.radius.xl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: GitLamaLayout.paletteQueryHeight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: MeridianSpace.space6,
                                    ),
                                    child: Row(
                                      children: [
                                        MeridianIcon(
                                          'command',
                                          color: colors.inkMuted,
                                        ),
                                        const SizedBox(
                                          width: MeridianSpace.space4,
                                        ),
                                        Expanded(
                                          child: Text(
                                            l10n.galleryPaletteQuery,
                                            style: context.text.paletteQuery
                                                .copyWith(color: colors.ink),
                                          ),
                                        ),
                                        const MeridianKbd(keys: ['esc']),
                                      ],
                                    ),
                                  ),
                                ),
                                const MeridianHairline(),
                                MeridianSurfaceScope(
                                  focused: true,
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      MeridianSpace.space2,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          l10n.galleryPaletteCommands
                                              .toUpperCase(),
                                          style: context.text.overline.copyWith(
                                            color: colors.inkMuted,
                                          ),
                                        ),
                                        MeridianListRow(
                                          title:
                                              l10n.galleryPaletteRebaseTarget,
                                          match: l10n.galleryPaletteQuery,
                                          leading: const MeridianIcon(
                                            'arrow-left-right',
                                          ),
                                          selected: true,
                                          trailing: const MeridianKbd(
                                            keys: ['↵'],
                                          ),
                                          onTap: () {},
                                        ),
                                        MeridianListRow(
                                          title: l10n
                                              .galleryPaletteInteractiveRebase,
                                          match: l10n.galleryPaletteQuery,
                                          leading: const MeridianIcon('squash'),
                                          trailing: Text(
                                            l10n.galleryPaletteLastCommits,
                                          ),
                                          onTap: () {},
                                        ),
                                        Text(
                                          l10n.galleryPaletteBranches
                                              .toUpperCase(),
                                          style: context.text.overline.copyWith(
                                            color: colors.inkMuted,
                                          ),
                                        ),
                                        MeridianListRow(
                                          title: l10n.galleryPaletteBranchRef,
                                          match: l10n.galleryPaletteQuery,
                                          leading: const MeridianIcon('branch'),
                                          trailing: Text(
                                            l10n.galleryPaletteOrigin,
                                          ),
                                          onTap: () {},
                                        ),
                                        Text(
                                          l10n.galleryPaletteRecent
                                              .toUpperCase(),
                                          style: context.text.overline.copyWith(
                                            color: colors.inkMuted,
                                          ),
                                        ),
                                        MeridianListRow(
                                          title: l10n.galleryPaletteAbortRebase,
                                          match: l10n.galleryPaletteQuery,
                                          leading: const MeridianIcon('ban'),
                                          trailing: Text(
                                            l10n.galleryPaletteYesterday,
                                          ),
                                          enabled: false,
                                          onTap: () {},
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const MeridianHairline(),
                                ColoredBox(
                                  color: colors.paneAlt,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: MeridianSpace.space6,
                                      vertical: MeridianSpace.space4,
                                    ),
                                    child: Wrap(
                                      spacing: MeridianSpace.space5,
                                      runSpacing: MeridianSpace.space3,
                                      children: [
                                        for (final (keys, label) in [
                                          (['↑', '↓'], l10n.galleryPaletteMove),
                                          (['↵'], l10n.galleryPaletteRun),
                                          (
                                            ['⌘', '↵'],
                                            l10n.galleryPaletteBackground,
                                          ),
                                          (['tab'], l10n.galleryPaletteScope),
                                        ])
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              MeridianKbd(keys: keys),
                                              const SizedBox(
                                                width: MeridianSpace.space3,
                                              ),
                                              Text(
                                                label,
                                                style: context.text.caption
                                                    .copyWith(
                                                      color: colors.inkMuted,
                                                    ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionRepoTabs,
                    SizedBox(
                      height: MeridianLayout.tabStripHeight,
                      child: GitLamaRepoTabs(
                        workspace: WorkspaceState(
                          tabs: [
                            RepositoryTabState(
                              id: 1,
                              generation: 1,
                              label: l10n.appTitle,
                              phase: RepositoryTabPhase.open,
                            ),
                            RepositoryTabState(
                              id: 2,
                              generation: 1,
                              label: l10n.workspaceHistory,
                              phase: RepositoryTabPhase.open,
                            ),
                          ],
                          activeTabId: 1,
                        ),
                        onActivate: (_) => setState(() => activations++),
                        onClose: (_) => setState(() => activations++),
                        onMoveTab: (_, _, _) => setState(() => activations++),
                        onOpenRepository: () => setState(() => activations++),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionSidebarRow,
                    ColoredBox(
                      color: colors.ground,
                      child: SizedBox(
                        width: MeridianSize.sidebar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: MeridianSpace.space2,
                            horizontal: MeridianSpace.space3,
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: MeridianLayout.navSectionHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: MeridianSpace.space4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l10n.workspaceBranches.toUpperCase(),
                                          style: context.text.overline.copyWith(
                                            color: colors.inkMuted,
                                          ),
                                        ),
                                      ),
                                      const MeridianCount(
                                        label: '2',
                                        tone: MeridianCountTone.quiet,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              MeridianSurfaceScope(
                                onGround: true,
                                child: MeridianListRow(
                                  title: 'main',
                                  emphasized: true,
                                  leading: MeridianIcon(
                                    'check',
                                    size: MeridianIconSize.small,
                                    color: colors.accentInk,
                                  ),
                                  onTap: () => setState(() => activations++),
                                ),
                              ),
                              MeridianSurfaceScope(
                                onGround: true,
                                child: MeridianListRow(
                                  title: l10n.workspaceHistory,
                                  leading: const MeridianIcon(
                                    'branch',
                                    size: MeridianIconSize.small,
                                  ),
                                  trailing: const GitLamaSyncBadge(
                                    ahead: 2,
                                    behind: 1,
                                  ),
                                  onTap: () => setState(() => activations++),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionAvatar,
                    Wrap(
                      spacing: MeridianSpace.space5,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        AuthorAvatar(author: l10n.galleryMichaelLamers),
                        AuthorAvatar(author: l10n.galleryGitLamaReleaseBot),
                        AuthorAvatar(author: l10n.galleryAuthorHandle),
                        AuthorAvatar(author: l10n.galleryAdaGit),
                        AuthorAvatar(
                          author: l10n.galleryMichaelLamers,
                          size: MeridianLayout.avatarLarge,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionCommitRow,
                    SizedBox(
                      height: _Specimen.commitRowsHeight,
                      child: HistoryGraphView(
                        itemCount: 3,
                        rowExtent: 28,
                        selectedObjectId: 'gallery-1',
                        checkedOutRef: 'refs/heads/main',
                        onSelected: (_) {},
                        rowAt: (index) => HistoryGraphRow(
                          objectId: 'gallery-$index',
                          lane: index == 2 ? 1 : 0,
                          shape: index == 2
                              ? HistoryNodeShape.merge
                              : HistoryNodeShape.commit,
                          segments: const [
                            HistoryGraphSegment(
                              fromLane: 0,
                              toLane: 0,
                              kind: HistorySegmentKind.straight,
                              startsAtTop: true,
                            ),
                          ],
                          geometry: const HistoryRowGeometry(
                            metadataLeft: 570,
                            graphClipRight: 558,
                            contentStart: 40,
                            contentAvailable: 518,
                          ),
                          subject: utf8.encode(
                            index == 0 ? l10n.galleryFetch : l10n.galleryBranch,
                          ),
                          author: utf8.encode(l10n.galleryMichaelLamers),
                          refs: index == 0
                              ? [utf8.encode('refs/heads/main')]
                              : const [],
                          current: index == 0,
                        ),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionComposer,
                    SizedBox(
                      width: _Specimen.composerWidth,
                      child: GitLamaComposer(
                        subject: MeridianTextField(
                          height: GitLamaLayout.composerSubjectHeight,
                          placeholder: l10n.commitSubject,
                          trailingText: '42/50',
                        ),
                        description: MeridianTextField(
                          placeholder: l10n.commitDescription,
                          minLines: GitLamaLayout.composerDescriptionMinLines,
                          maxLines: GitLamaLayout.composerDescriptionMaxLines,
                        ),
                        footer: Row(
                          children: [
                            MeridianCheckbox(
                              label: l10n.commitAmend,
                              value: false,
                              onChanged: (_) {},
                            ),
                            const Spacer(),
                            MeridianButton(
                              label: l10n.commitAndPush,
                              size: MeridianControlSize.small,
                              onPressed: () {},
                            ),
                            const SizedBox(width: MeridianSpace.space3),
                            MeridianButton(
                              label: l10n.commitAction,
                              variant: MeridianButtonVariant.primary,
                              size: MeridianControlSize.small,
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionDiffHunk,
                    SizedBox(
                      height:
                          GitLamaLayout.hunkHeaderHeight +
                          4 * GitLamaLayout.diffLineHeight,
                      child: DiffView(
                        itemCount: diffRows.length,
                        rowAt: (index) => diffRows[index],
                        loadedRows: diffRows,
                        hunkIndices: const {0},
                        layout: DiffViewLayout.unified,
                        selectedIds: const {'added'},
                        onSelectionChanged: (_) {},
                        hunkActions: (_) => MeridianButton(
                          label: l10n.galleryStageHunk,
                          variant: MeridianButtonVariant.secondary,
                          size: MeridianControlSize.small,
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionFileRow,
                    GitLamaFileRow(
                      status: 'M',
                      path: l10n.galleryDiffSamplePath,
                      added: 8,
                      deleted: 3,
                      onActivate: () {},
                      onStage: () {},
                      onDiscard: () {},
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionGraph,
                    SizedBox(
                      height: _Specimen.graphHeight,
                      child: HistoryGraphView(
                        itemCount: 3,
                        rowExtent: 28,
                        onSelected: (_) {},
                        rowAt: (index) => HistoryGraphRow(
                          objectId: 'graph-$index',
                          lane: index == 1 ? 1 : 0,
                          shape: index == 1
                              ? HistoryNodeShape.merge
                              : HistoryNodeShape.commit,
                          segments: [
                            HistoryGraphSegment(
                              fromLane: index == 1 ? 1 : 0,
                              toLane: 0,
                              kind: HistorySegmentKind.join,
                              startsAtTop: true,
                              endsAtCenter: true,
                            ),
                          ],
                          geometry: const HistoryRowGeometry(
                            metadataLeft: 570,
                            graphClipRight: 558,
                            contentStart: 40,
                            contentAvailable: 518,
                          ),
                        ),
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionRefChip,
                    Wrap(
                      spacing: MeridianSpace.space2,
                      runSpacing: MeridianSpace.space2,
                      children: const [
                        GitLamaRefChip(
                          name: 'main',
                          kind: GitLamaRefKind.head,
                          upstream: 'origin/main',
                        ),
                        GitLamaRefChip(
                          name: 'feature/meridian-migration',
                          kind: GitLamaRefKind.local,
                        ),
                        GitLamaRefChip(
                          name: 'origin/main',
                          kind: GitLamaRefKind.remote,
                        ),
                        GitLamaRefChip(
                          name: 'v1.0.0',
                          kind: GitLamaRefKind.tag,
                        ),
                        GitLamaRefChip(
                          name: 'stash',
                          kind: GitLamaRefKind.stash,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionStatusGlyph,
                    Wrap(
                      spacing: MeridianSpace.space6,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        for (final (status, label) in [
                          ('M', l10n.galleryModified),
                          ('A', l10n.galleryAdded),
                          ('D', l10n.galleryDeleted),
                          ('R', l10n.galleryRenamed),
                          ('C', l10n.galleryCopied),
                          ('U', l10n.galleryConflict),
                          ('?', l10n.galleryUntracked),
                          ('!', l10n.galleryIgnored),
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GitLamaStatusGlyph(status),
                              const SizedBox(width: MeridianSpace.space3),
                              Text(
                                label,
                                style: context.text.caption.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionSyncBadge,
                    const Wrap(
                      spacing: MeridianSpace.space8,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        GitLamaSyncBadge(ahead: 3, behind: 0),
                        GitLamaSyncBadge(ahead: 0, behind: 6),
                        GitLamaSyncBadge(ahead: 2, behind: 14),
                        GitLamaSyncBadge(ahead: 0, behind: 0, showZero: true),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionBanner,
                    Column(
                      children: [
                        MeridianBanner(
                          title: l10n.galleryRebasePaused,
                          message: l10n.galleryRebaseConflicts,
                          tone: MeridianBannerTone.attention,
                          icon: 'git-merge',
                          actions: [
                            MeridianButton(
                              label: l10n.galleryAbort,
                              variant: MeridianButtonVariant.quiet,
                              size: MeridianControlSize.small,
                              onPressed: () {},
                            ),
                            MeridianButton(
                              label: l10n.galleryContinue,
                              variant: MeridianButtonVariant.primary,
                              size: MeridianControlSize.small,
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: MeridianSpace.space4),
                        MeridianBanner(
                          title: l10n.galleryPushRejected,
                          message: l10n.galleryPushRejectedMessage,
                          tone: MeridianBannerTone.warning,
                          actions: [
                            MeridianButton(
                              label: l10n.galleryPullFirst,
                              size: MeridianControlSize.small,
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: MeridianSpace.space4),
                        MeridianBanner(
                          title: l10n.galleryAuthFailed,
                          message: l10n.galleryTokenExpired,
                          tone: MeridianBannerTone.error,
                          actions: [
                            MeridianButton(
                              label: l10n.galleryUpdateCredentials,
                              size: MeridianControlSize.small,
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: MeridianSpace.space4),
                        MeridianBanner(
                          message: l10n.galleryLfsMessage,
                          tone: MeridianBannerTone.info,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionKbd,
                    Wrap(
                      spacing: MeridianSpace.space6,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        const MeridianKbd(keys: ['⌘', 'K']),
                        const MeridianKbd(keys: ['⌘', '⇧', '↵']),
                        const MeridianKbd(keys: ['Ctrl', 'Shift', 'P']),
                        const MeridianKbd(keys: ['esc']),
                        const MeridianCount(label: '12'),
                        const MeridianCount(
                          label: '6',
                          tone: MeridianCountTone.accent,
                        ),
                        MeridianCount(
                          label: l10n.galleryTwoConflicts,
                          tone: MeridianCountTone.attention,
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionLogbook,
                    SizedBox(
                      width: GitLamaLayout.logbookWidth,
                      child: Column(
                        children: [
                          GitLamaTimelineRow(
                            state: GitLamaTimelineState.succeeded,
                            verb: l10n.operationFetch,
                            target: l10n.operationRepositoryApplication,
                            metadata: l10n.operationStateSucceeded,
                            time: const TimeOfDay(
                              hour: 10,
                              minute: 42,
                            ).format(context),
                            first: true,
                            onActivate: () {},
                          ),
                          GitLamaTimelineRow(
                            state: GitLamaTimelineState.failed,
                            verb: l10n.operationPush,
                            target: l10n.operationRepositoryApplication,
                            metadata: l10n.operationStateFailed,
                            time: const TimeOfDay(
                              hour: 10,
                              minute: 43,
                            ).format(context),
                            last: true,
                            onActivate: () {},
                            expanded: Text(
                              l10n.operationsDetailsUnavailable,
                              style: context.text.codeSm,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionDialog,
                    MeridianDialog(
                      title: l10n.galleryRebaseTitle,
                      description: l10n.galleryRebaseDescription,
                      content: Row(
                        children: [
                          Text(l10n.galleryBranch),
                          const SizedBox(width: MeridianSpace.space4),
                          const MeridianIcon('arrow-right'),
                          const SizedBox(width: MeridianSpace.space4),
                          Flexible(
                            child: Text(
                              l10n.galleryRefPlaceholder,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: MeridianSpace.space4),
                          Text(l10n.galleryFourCommits),
                        ],
                      ),
                      aside: MeridianCheckbox(
                        label: l10n.galleryAutostash,
                        value: true,
                        onChanged: (_) {},
                      ),
                      actions: [
                        MeridianButton(
                          label: l10n.cancel,
                          variant: MeridianButtonVariant.quiet,
                          onPressed: () {},
                        ),
                        MeridianButton(
                          label: l10n.galleryRebase,
                          variant: MeridianButtonVariant.primary,
                          shortcut: const ['↵'],
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionIsland,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: MeridianIsland(
                            title: l10n.galleryHistory,
                            actions: [
                              MeridianIconButton(
                                label: l10n.galleryFilter,
                                icon: 'list-filter-plus',
                                size: MeridianControlSize.small,
                                onPressed: () {},
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(
                                MeridianSpace.space5,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    l10n.galleryFocusedIsland,
                                    style: context.text.body.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                  MeridianSurfaceScope(
                                    focused: true,
                                    child: MeridianListRow(
                                      title: l10n.galleryBranchRow,
                                      leading: const MeridianIcon('branch'),
                                      selected: true,
                                      emphasized: true,
                                      onTap: () =>
                                          setState(() => activations += 1),
                                      semanticValue: l10n.galleryCurrent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: MeridianSpace.space3),
                        Expanded(
                          child: MeridianIsland(
                            title: l10n.galleryDetail,
                            child: Padding(
                              padding: const EdgeInsets.all(
                                MeridianSpace.space5,
                              ),
                              child: Text(
                                l10n.galleryUnfocusedIsland,
                                style: context.text.body.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  section(
                    l10n.gallerySectionSettingsRow,
                    MeridianSettingsGroup(
                      children: [
                        MeridianSettingsRow(
                          label: l10n.settingsTheme,
                          children: [
                            MeridianSegmented<String>(
                              label: l10n.settingsTheme,
                              segments: [
                                for (final item in [
                                  l10n.settingsThemeLight,
                                  l10n.settingsThemeDark,
                                  l10n.galleryThemeSystem,
                                ])
                                  MeridianSegment(value: item, label: item),
                              ],
                              value: l10n.galleryThemeSystem,
                              onChanged: (_) {},
                            ),
                          ],
                        ),
                        MeridianSettingsRow(
                          label: l10n.settingsDensity,
                          help: l10n.galleryDensityHelp,
                          children: [
                            MeridianSegmented<String>(
                              label: l10n.settingsDensity,
                              segments: [
                                for (final item in [
                                  l10n.settingsDensityCompact,
                                  l10n.settingsDensityRegular,
                                  l10n.settingsDensityComfortable,
                                ])
                                  MeridianSegment(value: item, label: item),
                              ],
                              value: l10n.settingsDensityRegular,
                              onChanged: (_) {},
                            ),
                          ],
                        ),
                        MeridianSettingsRow(
                          label: l10n.galleryDates,
                          children: [
                            MeridianSelect<String>(
                              value: l10n.settingsDateRelative,
                              values: [
                                l10n.settingsDateRelative,
                                l10n.settingsDateLocal,
                                l10n.settingsDateIso,
                              ],
                              valueLabel: (item) => item,
                              width: MeridianLayout.textFieldMinWidth,
                              onChanged: (_) {},
                            ),
                          ],
                        ),
                        MeridianSettingsRow(
                          label: l10n.galleryRemotes,
                          help: l10n.galleryRemotesHelp,
                          children: [
                            MeridianSwitch(
                              label: l10n.galleryFetchAutomatically,
                              value: true,
                              onChanged: (_) {},
                            ),
                            MeridianSwitch(
                              label: l10n.galleryIncludeTags,
                              value: false,
                              onChanged: (_) {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  gap(),
                  Text(l10n.galleryStatus(activations, displayedMenu)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sizes of the gallery's specimen frames, not of the product UI.
abstract final class _Specimen {
  static const double pageWidth = 960;
  static const double selectWidth = 180;
  static const double fieldWidth = 300;
  static const double commitRowsHeight = 96;
  static const double composerWidth = 410;
  static const double graphHeight = 84;
}
