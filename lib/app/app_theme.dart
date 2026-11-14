import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'gitlama_icons.dart';
import 'gitlama_tokens.g.dart';

export 'gitlama_tokens.g.dart' show GitLamaGitColors;

/// GitLama's Meridian colours outside a widget tree (tests, previews).
/// Widgets read `context.colors`.
MeridianColors gitlamaColors(Brightness brightness) => MeridianTheme.resolve(
  brand: MeridianBrands.gitlama,
  brightness: brightness,
).colors;

/// Shortcuts to the Meridian theme and GitLama's git colours.
extension GitLamaContext on BuildContext {
  MeridianColors get colors => MeridianTheme.of(this).colors;
  MeridianTextStyles get text => MeridianTheme.of(this).text;

  /// Diff, rename, conflict-side and tag colours that only a Git client
  /// needs. Added, modified and conflicted use Meridian's `success`,
  /// `warning` and `attention`.
  GitLamaGitColors get git =>
      MeridianTheme.of(this).extension<GitLamaGitColors>() ??
      (MeridianTheme.of(this).isDark
          ? GitLamaGitColors.dark
          : GitLamaGitColors.light);

  /// [time]'s time of day in the locale's clock, 24-hour when the platform
  /// asks for it.
  String clock(DateTime time) => MeridianLocalizations.of(this).formatTime(
    time,
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(this),
  );
}

/// The selection fill of the enclosing island, from Meridian's row colours:
/// GitLama uses the soft selection (`accent-soft`, normal inks).
Color meridianSelectionFill(BuildContext context) =>
    MeridianRowColors.resolve(context, selected: true, hovered: false).fill;

/// Text styles of GitLama's git components that are not one of
/// Meridian's ten styles. Colour is applied by the caller.
extension GitLamaTextStyles on MeridianTextStyles {
  /// `.ns-glyph`: the one-letter file status.
  TextStyle get glyph =>
      code.copyWith(fontSize: 10, height: 1, fontWeight: FontWeight.w700);

  /// `.ns-avatar`: initials in a 16px avatar.
  TextStyle get avatarSmall =>
      caption.copyWith(fontSize: 8, height: 1, fontWeight: FontWeight.w700);

  /// `.ns-avatar.lg`: initials in a 28px avatar.
  TextStyle get avatarLarge =>
      caption.copyWith(fontSize: 11, height: 1, fontWeight: FontWeight.w700);

  /// `.ns-palette .q`: the command palette query.
  TextStyle get paletteQuery =>
      body.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w400);

  /// `.ns-compass .branch`.
  TextStyle get compassBranch =>
      body.copyWith(height: 18 / 13, fontWeight: FontWeight.w500);

  /// `.ns-crow .who/.when`: commit row metadata.
  TextStyle get rowMeta => MeridianTextStyles.numeric(
    body.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400),
  );

  /// `.ns-meta b`.
  TextStyle get metaStrong =>
      body.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);

  /// `.ns-hunk-h`: a diff hunk header.
  TextStyle get hunkHeader =>
      body.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400);

  /// `.ns-ref.head`: the checked-out branch chip.
  TextStyle get chipStrong =>
      caption.copyWith(height: 16 / 11, fontWeight: FontWeight.w600);

  /// `.ns-dl .s`: the + and − column of a diff.
  TextStyle get diffSign => code.copyWith(fontWeight: FontWeight.w700);

  /// `.ns-composer .cnt.over`: the subject counter past its limit.
  TextStyle get counterOver => MeridianTextStyles.numeric(
    caption.copyWith(height: 14 / 11, fontWeight: FontWeight.w600),
  );
}

/// The densities GitLama offers: the three desktop ones.
const gitlamaDensities = [
  MeridianDensity.compact,
  MeridianDensity.regular,
  MeridianDensity.comfortable,
];

/// The app theme: Meridian with the GitLama brand, its git colours and
/// icon names and the soft selection (selected rows stay `accent-soft` with
/// the normal inks; the island halo shows focus). Desktop scrollbars stay
/// visible through [gitLamaScrollBehavior].
MeridianTheme buildAppTheme(
  Brightness brightness, {
  MeridianDensity density = MeridianDensity.regular,
}) {
  return MeridianTheme.resolve(
    brand: MeridianBrands.gitlama,
    brightness: brightness,
    density: density,
    icons: const MeridianIconSet(extra: gitlamaIconAliases),
    selection: MeridianSelectionStyle.soft,
    extensions: [
      brightness == Brightness.dark
          ? GitLamaGitColors.dark
          : GitLamaGitColors.light,
    ],
  );
}

/// GitLama's scrolling: Meridian's, with desktop scrollbars always visible.
const gitLamaScrollBehavior = MeridianScrollBehavior(alwaysShowThumb: true);
