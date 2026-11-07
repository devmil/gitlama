import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/repository_appearance.dart';
import '../../models/settings.dart';
import '../../services/repository_appearance_service.dart';
import '../../widgets/appearance_color_row.dart';
import '../../widgets/repository_icon.dart';
import '../app_theme.dart';

/// Lets a person pick the icon and colour, or an image file, that marks a
/// repository's tab.
Future<void> showRepositoryIconDialog(
  BuildContext context, {
  required RepositoryAppearanceService appearances,
  required NativePathIdentity identity,
  required String repositoryName,
}) => showMeridianDialog<void>(
  context: context,
  builder: (context) => RepositoryIconDialog(
    appearances: appearances,
    identity: identity,
    repositoryName: repositoryName,
  ),
);

class RepositoryIconDialog extends StatefulWidget {
  const RepositoryIconDialog({
    required this.appearances,
    required this.identity,
    required this.repositoryName,
    super.key,
  });

  final RepositoryAppearanceService appearances;
  final NativePathIdentity identity;
  final String repositoryName;

  @override
  State<RepositoryIconDialog> createState() => _RepositoryIconDialogState();
}

class _RepositoryIconDialogState extends State<RepositoryIconDialog> {
  late RepositoryAppearance _draft =
      widget.appearances.appearanceFor(widget.identity) ??
      RepositoryAppearance(identity: widget.identity);
  StreamSubscription<void>? _changes;
  var _busy = false;
  var _saveFailed = false;

  @override
  void initState() {
    super.initState();
    // Image reads finish later; show them when they do.
    _changes = widget.appearances.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  void _update({
    String? icon,
    bool clearIcon = false,
    String? color,
    bool clearColor = false,
    NativePathIdentity? image,
    bool clearImage = false,
  }) => setState(() {
    _saveFailed = false;
    _draft = RepositoryAppearance(
      identity: widget.identity,
      icon: clearIcon ? null : icon ?? _draft.icon,
      color: clearColor ? null : color ?? _draft.color,
      image: clearImage ? null : image ?? _draft.image,
      name: _draft.name,
    );
  });

  Future<void> _chooseImage() async {
    setState(() => _busy = true);
    try {
      final image = await widget.appearances.chooseImage();
      if (mounted && image != null) _update(image: image);
    } on Object {
      // A picker that cannot open leaves the draft as it was.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final image = _draft.image;
    if (image != null && widget.appearances.imageFailed(image)) return;
    setState(() => _busy = true);
    try {
      await widget.appearances.save(_draft);
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final image = _draft.image;
    final loaded = image == null ? null : widget.appearances.imageAt(image);
    final imageFailed = image != null && widget.appearances.imageFailed(image);
    final color = AppearanceColor.byKey(_draft.color);
    final tint = color == null
        ? colors.inkMuted
        : repositoryAppearanceColor(context, color);
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: l10n.repositoryIconTitle,
      description: l10n.repositoryIconDescription,
      onSubmit: () => unawaited(_save()),
      submitDisabled: _busy || imageFailed,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            key: const ValueKey('repository-icon-preview'),
            children: [
              if (RepositoryIcon.shows(_draft)) ...[
                RepositoryIcon(appearance: _draft, image: loaded),
                const SizedBox(width: MeridianSpace.space3),
              ],
              Flexible(
                child: Text(
                  widget.repositoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space6),
          AppearanceHeading(l10n.repositoryIconSymbol),
          Wrap(
            spacing: MeridianSpace.space2,
            runSpacing: MeridianSpace.space2,
            children: [
              MeridianIconButton(
                key: const ValueKey('repository-icon-none'),
                label: l10n.repositoryIconNone,
                icon: 'ban',
                size: MeridianControlSize.small,
                active: _draft.icon == null,
                onPressed: _busy ? null : () => _update(clearIcon: true),
              ),
              for (final icon in repositoryAppearanceIcons)
                MeridianIconButton(
                  key: ValueKey('repository-icon-$icon'),
                  label: repositoryIconLabel(context, icon),
                  icon: icon,
                  size: MeridianControlSize.small,
                  color: tint,
                  active: _draft.icon == icon,
                  onPressed: _busy ? null : () => _update(icon: icon),
                ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space6),
          AppearanceHeading(l10n.repositoryIconColor),
          AppearanceColorRow(
            value: color,
            noneLabel: l10n.repositoryColorNone,
            onChanged: _busy
                ? null
                : (value) => value == null
                      ? _update(clearColor: true)
                      : _update(color: value.key),
          ),
          const SizedBox(height: MeridianSpace.space6),
          AppearanceHeading(l10n.repositoryIconImage),
          Wrap(
            spacing: MeridianSpace.space3,
            runSpacing: MeridianSpace.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MeridianButton(
                key: const ValueKey('repository-icon-choose-image'),
                label: l10n.repositoryIconChooseImage,
                icon: 'image-plus',
                size: MeridianControlSize.small,
                onPressed: _busy ? null : () => unawaited(_chooseImage()),
              ),
              if (image != null)
                MeridianButton(
                  key: const ValueKey('repository-icon-remove-image'),
                  label: l10n.repositoryIconRemoveImage,
                  variant: MeridianButtonVariant.quiet,
                  size: MeridianControlSize.small,
                  onPressed: _busy ? null : () => _update(clearImage: true),
                ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space3),
          Text(
            imageFailed
                ? l10n.repositoryIconImageUnreadable
                : _saveFailed
                ? l10n.repositoryIconSaveFailed
                : l10n.repositoryIconImageHint,
            style: context.text.caption.copyWith(
              color: imageFailed || _saveFailed
                  ? colors.danger
                  : colors.inkMuted,
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
          key: const ValueKey('repository-icon-save'),
          label: l10n.repositoryIconSave,
          variant: MeridianButtonVariant.primary,
          onPressed: _busy || imageFailed ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}

String repositoryIconLabel(BuildContext context, String icon) {
  final l10n = context.l10n;
  return switch (icon) {
    'folder-git-2' => l10n.repositoryIconNameRepository,
    'code-xml' => l10n.repositoryIconNameCode,
    'square-terminal' => l10n.repositoryIconNameTerminal,
    'box' => l10n.repositoryIconNamePackage,
    'blocks' => l10n.repositoryIconNameComponents,
    'puzzle' => l10n.repositoryIconNamePlugin,
    'layers' => l10n.repositoryIconNameLayers,
    'book-open' => l10n.repositoryIconNameDocumentation,
    'palette' => l10n.repositoryIconNameDesign,
    'image' => l10n.repositoryIconNameMedia,
    'smartphone' => l10n.repositoryIconNameMobile,
    'monitor' => l10n.repositoryIconNameDesktop,
    'server' => l10n.repositoryIconNameServer,
    'cloud' => l10n.repositoryIconNameCloud,
    'zap' => l10n.repositoryIconNameLightning,
    'star' => l10n.repositoryIconNameStar,
    'flag' => l10n.repositoryIconNameFlag,
    'bug' => l10n.repositoryIconNameBug,
    'wand-sparkles' => l10n.repositoryIconNameMagic,
    'graduation-cap' => l10n.repositoryIconNameLearning,
    'shield-check' => l10n.repositoryIconNameSecurity,
    'chart-line' => l10n.repositoryIconNameAnalytics,
    'house' => l10n.repositoryIconNameHome,
    'users' => l10n.repositoryIconNameTeam,
    _ => l10n.repositoryIconSymbol,
  };
}
