import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';
import '../widgets/gitlama_window_caption.dart';
import 'app_theme.dart';
import 'gitlama_layout.dart';

/// The loading and failed-start screen of a window that is bootstrapping:
/// a spinner while it starts, and the failure with Retry.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      GitLamaWindowCaptionBand(child: _content(context));

  Widget _content(BuildContext context) {
    final colors = context.colors;
    if (!failed) {
      // The mark sits exactly at the centre, where the macOS launch cover
      // drew it, with the progress below it.
      return Scaffold(
        backgroundColor: colors.ground,
        body: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Center(
                child: Image.asset(
                  'assets/brand/tile-256.png',
                  width: GitLamaLayout.launchMarkSize,
                  height: GitLamaLayout.launchMarkSize,
                  excludeFromSemantics: true,
                ),
              ),
              PositionedDirectional(
                start: MeridianSpace.space8,
                end: MeridianSpace.space8,
                top:
                    constraints.maxHeight / 2 +
                    GitLamaLayout.launchMarkSize / 2 +
                    MeridianSpace.space7,
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const MeridianSpinner(),
                      const SizedBox(height: MeridianSpace.space4),
                      Text(
                        context.l10n.startupLoading,
                        textAlign: TextAlign.center,
                        style: context.text.body.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(MeridianSpace.space8),
            child: Semantics(
              liveRegion: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: MeridianLayout.dialogWidth,
                ),
                child: MeridianBanner(
                  tone: MeridianBannerTone.error,
                  message: context.l10n.startupFailed,
                  actions: [
                    MeridianButton(
                      label: context.l10n.retry,
                      variant: MeridianButtonVariant.primary,
                      onPressed: onRetry,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
