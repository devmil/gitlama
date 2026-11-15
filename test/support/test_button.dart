import 'package:flutter/widgets.dart';

/// A bare tap target for test fixtures that only need something to press
/// (the app itself uses Meridian buttons).
class TestButton extends StatelessWidget {
  const TestButton({required this.onPressed, required this.child, super.key});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onPressed,
    child: child,
  );
}
