import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:meridian_ui/meridian_ui.dart';
import '../app/app_theme.dart';

/// Presentation shell for the Changes composer. Draft and commit state stay in
/// the owning workflow widget.
class GitLamaComposer extends StatelessWidget {
  const GitLamaComposer({
    required this.subject,
    required this.description,
    required this.footer,
    this.failure,
    this.failureVisible = true,
    this.fill = false,
    this.descriptionMinHeight = 0,
    super.key,
  });

  final Widget subject;
  final Widget description;
  final Widget footer;
  final Widget? failure;
  final bool failureVisible;

  /// The composer was given a height: [description] takes whatever the
  /// other parts leave, but never less than [descriptionMinHeight]; below
  /// that the composer scrolls. The description must then fill a tight
  /// height (an expanding field).
  final bool fill;
  final double descriptionMinHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = [
      if (failure case final failure?) ...[
        failure,
        MeridianReveal(
          visible: failureVisible,
          child: const SizedBox(height: MeridianSpace.space4),
        ),
      ],
      subject,
      const SizedBox(height: MeridianSpace.space4),
      description,
      const SizedBox(height: MeridianSpace.space4),
      footer,
    ];
    const padding = EdgeInsets.all(MeridianSpace.space5);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.paneAlt,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      // Padding sits inside the scroll view so focus rings drawn outside the
      // fields are not clipped at the scroll viewport edge.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: padding,
          child: fill && constraints.hasBoundedHeight
              ? _FillColumn(
                  fillIndex: children.indexOf(description),
                  height: constraints.maxHeight - padding.vertical,
                  fillMinHeight: descriptionMinHeight,
                  children: children,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
        ),
      ),
    );
  }
}

/// A full-width column whose child at [fillIndex] takes the [height] the
/// others leave, at least [fillMinHeight].
class _FillColumn extends MultiChildRenderObjectWidget {
  const _FillColumn({
    required this.fillIndex,
    required this.height,
    required this.fillMinHeight,
    required super.children,
  });

  final int fillIndex;
  final double height;
  final double fillMinHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillColumn(
    fillIndex: fillIndex,
    height: height,
    fillMinHeight: fillMinHeight,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFillColumn renderObject,
  ) {
    renderObject
      ..fillIndex = fillIndex
      ..height = height
      ..fillMinHeight = fillMinHeight;
  }
}

class _FillColumnParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFillColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillColumnParentData> {
  _RenderFillColumn({
    required this._fillIndex,
    required this._height,
    required this._fillMinHeight,
  });

  int _fillIndex;
  set fillIndex(int value) {
    if (value == _fillIndex) return;
    _fillIndex = value;
    markNeedsLayout();
  }

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  double _fillMinHeight;
  set fillMinHeight(double value) {
    if (value == _fillMinHeight) return;
    _fillMinHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillColumnParentData) {
      child.parentData = _FillColumnParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = childAfter(child);
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    RenderBox? filler;
    var others = 0.0;
    for (final (index, child) in _children.indexed) {
      if (index == _fillIndex) {
        filler = child;
        continue;
      }
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      others += child.size.height;
    }
    filler?.layout(
      BoxConstraints.tightFor(
        width: width,
        height: math.max(_fillMinHeight, _height - others),
      ),
      parentUsesSize: true,
    );
    var y = 0.0;
    for (final child in _children) {
      (child.parentData! as _FillColumnParentData).offset = Offset(0, y);
      y += child.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(
    0,
    (width, child) => math.max(width, child.getMinIntrinsicWidth(height)),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _children.fold(
    0,
    (width, child) => math.max(width, child.getMaxIntrinsicWidth(height)),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  double _intrinsicHeight(double width) {
    var others = 0.0;
    for (final (index, child) in _children.indexed) {
      if (index != _fillIndex) others += child.getMaxIntrinsicHeight(width);
    }
    return others + math.max(_fillMinHeight, _height - others);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
