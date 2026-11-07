import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../services/avatar_service.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'status_notification.dart';

class AvatarScope extends InheritedWidget {
  const AvatarScope({required this.service, required super.child, super.key});

  final AvatarService? service;

  static AvatarService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AvatarScope>()?.service;

  @override
  bool updateShouldNotify(AvatarScope oldWidget) =>
      service != oldWidget.service;
}

/// A compact author identity with a local fallback and an opt-in prompt.
class AuthorAvatar extends StatefulWidget {
  const AuthorAvatar({
    required this.author,
    this.avatarHash = '',
    this.size = MeridianLayout.avatarSmall,
    super.key,
  });

  final String author;
  final String avatarHash;
  final double size;

  @override
  State<AuthorAvatar> createState() => _AuthorAvatarState();
}

class _AuthorAvatarState extends State<AuthorAvatar> {
  Future<Uint8List?>? _image;
  AvatarService? _service;
  String? _hash;
  bool? _wasEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = AvatarScope.maybeOf(context);
    if (service != _service || widget.avatarHash != _hash) {
      _service = service;
      _hash = widget.avatarHash;
      _image = service?.imageFor(widget.avatarHash);
    }
  }

  @override
  void didUpdateWidget(AuthorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarHash != widget.avatarHash) {
      _hash = widget.avatarHash;
      _image = _service?.imageFor(widget.avatarHash);
    }
  }

  Future<void> _offerGravatar() async {
    final service = _service;
    if (service == null || service.enabled) return;
    final enable = await showMeridianDialog<bool>(
      context: context,
      builder: (context) => GravatarOfferDialog(canEnable: service.canEnable),
    );
    if (enable == true) {
      try {
        await service.setEnabled(true);
        if (mounted) setState(() {});
      } on Object {
        if (!mounted) return;
        StatusNotificationScope.show(
          context,
          context.l10n.settingsSaveFailed,
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final enabled = service?.enabled ?? false;
    if (_wasEnabled != enabled) {
      _wasEnabled = enabled;
      _image = enabled ? service?.imageFor(widget.avatarHash) : null;
    }
    final name = widget.author.split('<').first.trim();
    final size = widget.size <= MeridianLayout.avatarSmall
        ? MeridianAvatarSize.small
        : MeridianAvatarSize.large;
    final pressable = service != null && !enabled;
    return FutureBuilder<Uint8List?>(
      future: enabled ? _image : null,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return MeridianAvatar(
          name: name,
          size: size,
          image: bytes == null ? null : MemoryImage(bytes),
          onPressed: pressable ? () => unawaited(_offerGravatar()) : null,
          tooltip: pressable ? context.l10n.avatarGravatarTooltip : null,
        );
      },
    );
  }
}

/// Offers to show author images from Gravatar and says what that sends.
/// Without [canEnable] it only explains.
class GravatarOfferDialog extends StatelessWidget {
  const GravatarOfferDialog({required this.canEnable, super.key});

  final bool canEnable;

  @override
  Widget build(BuildContext context) => MeridianDialog(
    width: MeridianLayout.dialogConfirmWidth,
    title: context.l10n.avatarGravatarTitle,
    description: context.l10n.avatarGravatarHint,
    onSubmit: canEnable ? () => Navigator.pop(context, true) : null,
    actions: [
      MeridianButton(
        variant: MeridianButtonVariant.quiet,
        onPressed: () => Navigator.pop(context),
        label: canEnable
            ? context.l10n.avatarGravatarNotNow
            : context.l10n.close,
      ),
      if (canEnable)
        MeridianButton(
          variant: MeridianButtonVariant.primary,
          onPressed: () => Navigator.pop(context, true),
          label: context.l10n.avatarEnableGravatar,
        ),
    ],
  );
}
