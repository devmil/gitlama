import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// Tells a row whether its focus came from the keyboard, and rebuilds it when
/// the last input switches between keyboard and pointer.
///
/// Actions a row reveals on hover also show for keyboard focus. Focus taken by
/// a click must not keep them open once the pointer leaves, and a click
/// elsewhere hides what keyboard focus was showing.
mixin KeyboardRevealState<T extends StatefulWidget> on State<T> {
  bool get keyboardInput => MeridianInputModality.keyboard;

  @override
  void initState() {
    super.initState();
    MeridianInputModality.retain();
    MeridianInputModality.changes.addListener(_inputChanged);
  }

  @override
  void dispose() {
    MeridianInputModality.changes.removeListener(_inputChanged);
    MeridianInputModality.release();
    super.dispose();
  }

  void _inputChanged() {
    if (mounted) setState(() {});
  }
}
