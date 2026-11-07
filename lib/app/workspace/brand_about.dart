import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../l10n/l10n.dart';
import '../../widgets/native_menu.dart';
import '../../models/app_update.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';

/// GitLama's About: the mark, the name, the version and the maker,
/// centred like a title page, then the Lama family with GitLama picked out.
Future<void> showBrandAbout(
  BuildContext context, {
  InstalledRelease? installed,
}) => showMeridianDialog<void>(
  context: context,
  builder: (context) => MeridianDialog(
    key: const ValueKey('brand-about'),
    width: MeridianLayout.dialogConfirmWidth,
    onClose: () => Navigator.pop(context),
    scrollable: true,
    content: BrandAboutContent(installed: installed),
  ),
);

class BrandAboutContent extends StatelessWidget {
  const BrandAboutContent({this.installed, super.key});

  final InstalledRelease? installed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final muted = context.text.body.copyWith(color: colors.inkMuted);
    final family = l10n.lamaFamilyNames
        .split('·')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);
    return Semantics(
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.aboutApp,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: MeridianSpace.space5),
          Center(
            child: Image.asset(
              'assets/brand/tile-256.png',
              width: GitLamaLayout.aboutMarkSize,
              height: GitLamaLayout.aboutMarkSize,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: MeridianSpace.space7),
          Semantics(
            header: true,
            child: Text(
              l10n.appTitle,
              textAlign: TextAlign.center,
              style: context.text.display.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(height: MeridianSpace.space3),
          Text(l10n.brandMaker, textAlign: TextAlign.center, style: muted),
          if (installed case final release?) ...[
            const SizedBox(height: MeridianSpace.space4),
            Center(
              child: SelectableText(
                contextMenuBuilder: nativeTextContextMenuBuilder,
                l10n.aboutVersion(release.version, '${release.build}'),
                key: const ValueKey('brand-about-version'),
                textAlign: TextAlign.center,
                style: context.text.caption.copyWith(color: colors.inkMuted),
              ),
            ),
          ],
          const SizedBox(height: MeridianSpace.space9),
          const MeridianHairline(),
          const SizedBox(height: MeridianSpace.space7),
          Text(
            l10n.lamaFamily,
            textAlign: TextAlign.center,
            style: context.text.overline.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: MeridianSpace.space5),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: MeridianSpace.space3,
            runSpacing: MeridianSpace.space3,
            children: [
              for (final name in family)
                MeridianChip(
                  label: name,
                  tone: name == l10n.appTitle
                      ? MeridianChipTone.accent
                      : MeridianChipTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space3),
        ],
      ),
    );
  }
}
