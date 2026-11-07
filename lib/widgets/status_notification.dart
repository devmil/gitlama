import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../models/operation_failure.dart';
import '../models/app_update.dart';
import '../models/host_platform.dart';
import '../services/operation_center_service.dart';
import 'operation_failure_dialog.dart';
import 'package:meridian_ui/meridian_ui.dart';

typedef _StatusMessage = ({
  String text,
  bool error,
  OperationFailureDetails details,
});

/// UI feedback shared across the navigator, including dialogs: messages in
/// the status bar, and a dialog for each failed action the user started.
class StatusNotificationScope extends StatefulWidget {
  const StatusNotificationScope({
    required this.child,
    this.operations,
    this.release,
    this.loadActivity,
    super.key,
  });

  final Widget child;
  final OperationCenterService? operations;
  final InstalledRelease? release;

  /// Lets the failure dialog show the output of the Git command that failed.
  final ActivityRecordLoader? loadActivity;

  static void show(
    BuildContext context,
    String message, {
    bool error = false,
    OperationFailureDetails details = const OperationFailureDetails(),
  }) {
    final scope = context
        .getInheritedWidgetOfExactType<_StatusNotificationData>();
    assert(scope != null, 'StatusNotificationScope must wrap the navigator.');
    scope?.onShow(context, (text: message, error: error, details: details));
  }

  static String supportReport(
    BuildContext context,
    OperationFailureDetails details,
  ) {
    final scope = context
        .getInheritedWidgetOfExactType<_StatusNotificationData>();
    return details.report(
      release: scope?.release,
      platform: switch (defaultTargetPlatform) {
        TargetPlatform.macOS => HostPlatform.macOS,
        TargetPlatform.windows => HostPlatform.windows,
        TargetPlatform.linux => HostPlatform.linux,
        _ => HostPlatform.other,
      },
    );
  }

  @override
  State<StatusNotificationScope> createState() =>
      _StatusNotificationScopeState();
}

/// Copies [text] and confirms it with [message] in the status bar, as
/// clicking a commit hash in the history does.
/// Copies a file or folder [path] as the menus show it and says so. Every
/// Copy path action uses this.
Future<void> copyPathWithNotification(BuildContext context, String path) =>
    copyWithStatusNotification(context, path, context.l10n.filePathCopied);

Future<void> copyWithStatusNotification(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) StatusNotificationScope.show(context, message);
}

class _StatusNotificationScopeState extends State<StatusNotificationScope> {
  final _message = ValueNotifier<_StatusMessage?>(null);
  Timer? _expiry;

  /// The failure the open dialog shows; null while none is open.
  ValueNotifier<OperationFailure>? _failure;

  void _show(BuildContext context, _StatusMessage message) {
    _expiry?.cancel();
    _message.value = message;
    if (message.error) {
      widget.operations?.recordUserFailure(message.text, message.details);
      _showFailure(context, (message: message.text, details: message.details));
    }
    _expiry = Timer(const Duration(seconds: 8), () => _message.value = null);
  }

  /// One dialog at a time: a failure while it is open replaces its content.
  void _showFailure(BuildContext context, OperationFailure failure) {
    final open = _failure;
    if (open != null) {
      open.value = failure;
      return;
    }
    // The root navigator outlives the context of the action that failed,
    // such as a dialog that has just closed.
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return;
    final current = ValueNotifier(failure);
    _failure = current;
    showMeridianDialog<void>(
      context: navigator.context,
      builder: (context) => OperationFailureDialog(
        failure: current,
        loadActivity: widget.loadActivity,
      ),
    ).whenComplete(() {
      if (identical(_failure, current)) _failure = null;
      current.dispose();
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StatusNotificationData(
    notifier: _message,
    onShow: _show,
    release: widget.release,
    child: widget.child,
  );
}

class _StatusNotificationData
    extends InheritedNotifier<ValueNotifier<_StatusMessage?>> {
  const _StatusNotificationData({
    required super.notifier,
    required this.onShow,
    required this.release,
    required super.child,
  });

  final void Function(BuildContext, _StatusMessage) onShow;
  final InstalledRelease? release;
}

/// Uses an existing bounded status-bar slot; messages never change its size.
class StatusNotificationText extends StatelessWidget {
  const StatusNotificationText({this.fallback = '', super.key});

  final String fallback;

  @override
  Widget build(BuildContext context) {
    final message = context
        .dependOnInheritedWidgetOfExactType<_StatusNotificationData>()
        ?.notifier
        ?.value;
    final label = message?.text ?? fallback;
    final colors = context.colors;
    return Semantics(
      liveRegion: message != null,
      child: Tooltip(
        message: label,
        child: MeridianSwap(
          swapKey: label,
          style: MeridianSwapStyle.rise,
          rise: MeridianSpace.space1,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.caption.copyWith(
              color: message?.error == true ? colors.danger : colors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports a remote write whose outcome is unknown. It waits for review under
/// Remote changes and is never retried here. [message] names what changed
/// when the caller knows it.
void showRemoteOutcomeUnknown(BuildContext context, {String? message}) =>
    StatusNotificationScope.show(
      context,
      message ?? context.l10n.remoteOutcomeUnknownChange,
      error: true,
    );
