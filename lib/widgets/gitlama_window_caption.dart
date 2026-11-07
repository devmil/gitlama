import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/l10n.dart';

/// A window button the Flutter-drawn Linux caption can show.
enum GitLamaCaptionButton { minimize, maximize, close }

/// Which caption buttons the desktop asks for, per edge, in display order.
///
/// Parsed from GTK's `gtk-decoration-layout` setting.
@immutable
class GitLamaCaptionLayout {
  const GitLamaCaptionLayout({required this.leading, required this.trailing});

  /// Used until (or when) the platform reports no usable layout: a single
  /// trailing close button, the GTK default.
  static const fallback = GitLamaCaptionLayout(
    leading: [],
    trailing: [GitLamaCaptionButton.close],
  );

  /// Parses a value such as `"menu:minimize,maximize,close"`. Entries
  /// GitLama does not draw (`menu`, `icon`, `appmenu`, `spacer`, unknown
  /// names) are skipped. A missing value yields [fallback]; an empty one
  /// draws no buttons.
  factory GitLamaCaptionLayout.parse(String? layout) {
    if (layout == null) return fallback;
    final names = GitLamaCaptionButton.values.asNameMap();
    final sides = layout.split(':');
    List<GitLamaCaptionButton> buttons(String side) => List.unmodifiable(
      side.split(',').map((name) => names[name.trim()]).nonNulls,
    );
    return GitLamaCaptionLayout(
      leading: buttons(sides.first),
      trailing: sides.length > 1
          ? buttons(sides[1])
          : const <GitLamaCaptionButton>[],
    );
  }

  final List<GitLamaCaptionButton> leading;
  final List<GitLamaCaptionButton> trailing;

  @override
  bool operator ==(Object other) =>
      other is GitLamaCaptionLayout &&
      listEquals(other.leading, leading) &&
      listEquals(other.trailing, trailing);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(leading), Object.hashAll(trailing));
}

/// The `gitlama/window_chrome` vocabulary, mirrored by
/// `linux/runner/window_chrome.cc`.
enum _WindowChromeMethod {
  captionLayout,
  captionLayoutChanged,
  setBackgroundColor,
  beginMove,
  showWindowMenu,
  minimize,
  toggleMaximize,
  close,
}

/// Owns the Linux window-chrome channel of a window's engine and provides
/// the caption layout and window commands to [GitLamaWindowDragArea],
/// [GitLamaWindowControls] and [GitLamaWindowCaptionBand].
///
/// The Linux runner hides the GTK title bar of the main and inspection
/// windows, so a toolbar or caption row doubles as the caption, as it does
/// on macOS. Mount once above the navigator. On other platforms there is no
/// frame and the pieces fall back to native behaviour.
class GitLamaWindowCaptionFrame extends StatefulWidget {
  const GitLamaWindowCaptionFrame({super.key, required this.child});

  static const channel = MethodChannel('gitlama/window_chrome');

  /// Whether the runner draws no title bar and Flutter owns the caption.
  static bool get drawsCaption =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  final Widget child;

  @override
  State<GitLamaWindowCaptionFrame> createState() =>
      _GitLamaWindowCaptionFrameState();
}

class _GitLamaWindowCaptionFrameState extends State<GitLamaWindowCaptionFrame> {
  Color? _background;

  var _layout = GitLamaCaptionLayout.fallback;

  @override
  void initState() {
    super.initState();
    if (!GitLamaWindowCaptionFrame.drawsCaption) return;
    GitLamaWindowCaptionFrame.channel.setMethodCallHandler(_handleCall);
    unawaited(_loadLayout());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!GitLamaWindowCaptionFrame.drawsCaption) return;
    final background = context.meridian.colors.ground;
    if (_background == background) return;
    _background = background;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _background == background) {
        _invoke(_WindowChromeMethod.setBackgroundColor, background.toARGB32());
      }
    });
  }

  @override
  void dispose() {
    if (GitLamaWindowCaptionFrame.drawsCaption) {
      GitLamaWindowCaptionFrame.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _loadLayout() async {
    try {
      _applyLayout(
        await GitLamaWindowCaptionFrame.channel.invokeMethod<String>(
          _WindowChromeMethod.captionLayout.name,
        ),
      );
    } on MissingPluginException {
      // No native window chrome (tests, embedders): keep the fallback.
    } on PlatformException {
      // Keep the fallback; the caption still moves and closes the window.
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == _WindowChromeMethod.captionLayoutChanged.name) {
      _applyLayout(call.arguments is String ? call.arguments as String : null);
    }
    return null;
  }

  void _applyLayout(String? value) {
    final layout = GitLamaCaptionLayout.parse(value);
    if (!mounted || layout == _layout) return;
    setState(() => _layout = layout);
  }

  void _invoke(_WindowChromeMethod method, [Object? arguments]) {
    unawaited(
      GitLamaWindowCaptionFrame.channel
          .invokeMethod<Object?>(method.name, arguments)
          .catchError(
            (Object _) => null,
            test: (error) =>
                error is MissingPluginException || error is PlatformException,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!GitLamaWindowCaptionFrame.drawsCaption) return widget.child;
    return _CaptionScope(
      layout: _layout,
      onCommand: _invoke,
      child: widget.child,
    );
  }
}

class _CaptionScope extends InheritedWidget {
  const _CaptionScope({
    required this.layout,
    required this.onCommand,
    required super.child,
  });

  final GitLamaCaptionLayout layout;

  /// Stable for the frame's lifetime (a torn-off state method).
  final ValueChanged<_WindowChromeMethod> onCommand;

  static _CaptionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CaptionScope>();

  @override
  bool updateShouldNotify(_CaptionScope oldWidget) =>
      layout != oldWidget.layout;
}

/// Turns the empty background of [child] into window caption: dragging
/// moves the window and double-clicking toggles maximize. On Linux a
/// secondary click opens the window-manager menu and controls inside [child]
/// keep their own gestures. Without a Flutter-drawn caption this is
/// window_manager's [DragToMoveArea].
class GitLamaWindowDragArea extends StatelessWidget {
  const GitLamaWindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _CaptionScope.maybeOf(context);
    if (scope == null) return DragToMoveArea(child: child);
    final onCommand = scope.onCommand;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('window-drag-area'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onCommand(_WindowChromeMethod.beginMove),
            onDoubleTap: () => onCommand(_WindowChromeMethod.toggleMaximize),
            onSecondaryTapDown: (_) =>
                onCommand(_WindowChromeMethod.showWindowMenu),
          ),
        ),
        child,
      ],
    );
  }
}

/// The window buttons the desktop configured, for the trailing end of the
/// top toolbar row. Buttons a layout puts on the start edge are shown here
/// too, since the leading corner holds the toolbar actions (as it holds the
/// traffic lights on macOS). Renders nothing without a Flutter-drawn caption.
class GitLamaWindowControls extends StatelessWidget {
  const GitLamaWindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = _CaptionScope.maybeOf(context);
    final buttons = [...?scope?.layout.leading, ...?scope?.layout.trailing];
    if (scope == null || buttons.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('window-controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const GitLamaWindowDragArea(
          child: SizedBox(
            width: MeridianSpace.space4,
            height: MeridianSize.toolbar,
          ),
        ),
        _Buttons(buttons: buttons, onCommand: scope.onCommand),
      ],
    );
  }
}

/// A caption strip over the top edge of a screen without a toolbar row (the
/// startup screen): a drag area with the window buttons at their edges.
/// Returns [child] unchanged without a Flutter-drawn caption.
class GitLamaWindowCaptionBand extends StatelessWidget {
  const GitLamaWindowCaptionBand({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _CaptionScope.maybeOf(context);
    if (scope == null) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          key: const ValueKey('window-caption-band'),
          top: 0,
          left: 0,
          right: 0,
          height: MeridianSize.toolbar,
          child: GitLamaWindowDragArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MeridianSpace.space5,
              ),
              child: Row(
                children: [
                  _Buttons(
                    buttons: scope.layout.leading,
                    onCommand: scope.onCommand,
                  ),
                  const Spacer(),
                  _Buttons(
                    buttons: scope.layout.trailing,
                    onCommand: scope.onCommand,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.buttons, required this.onCommand});

  final List<GitLamaCaptionButton> buttons;
  final ValueChanged<_WindowChromeMethod> onCommand;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final button in buttons)
          switch (button) {
            GitLamaCaptionButton.minimize => MeridianIconButton(
              key: const ValueKey('window-caption-minimize'),
              label: l10n.windowMinimize,
              icon: MeridianIcons.minus,
              onGround: true,
              canRequestFocus: false,
              onPressed: () => onCommand(_WindowChromeMethod.minimize),
            ),
            GitLamaCaptionButton.maximize => MeridianIconButton(
              key: const ValueKey('window-caption-maximize'),
              label: l10n.windowMaximize,
              icon: MeridianIcons.square,
              onGround: true,
              canRequestFocus: false,
              onPressed: () => onCommand(_WindowChromeMethod.toggleMaximize),
            ),
            GitLamaCaptionButton.close => MeridianIconButton(
              key: const ValueKey('window-caption-close'),
              label: l10n.windowClose,
              icon: MeridianIcons.x,
              onGround: true,
              canRequestFocus: false,
              onPressed: () => onCommand(_WindowChromeMethod.close),
            ),
          },
      ],
    );
  }
}
