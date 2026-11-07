import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/widgets/history_motion.dart';

/// A plain history row for motion tests.
HistoryGraphRow historyRow(
  String objectId, {
  bool lit = true,
  bool current = false,
  HistoryNodeShape shape = HistoryNodeShape.commit,
  List<String> refs = const [],
  bool searchMatch = true,
}) => HistoryGraphRow(
  objectId: objectId,
  lane: 0,
  shape: shape,
  segments: const [
    HistoryGraphSegment(
      fromLane: 0,
      toLane: 0,
      kind: HistorySegmentKind.straight,
      startsAtTop: true,
      endsAtCenter: false,
    ),
  ],
  geometry: const HistoryRowGeometry(
    metadataLeft: 500,
    graphClipRight: 488,
    contentStart: 40,
    contentAvailable: 440,
  ),
  subject: utf8.encode('Subject $objectId'),
  author: utf8.encode('Ada'),
  refs: [for (final ref in refs) utf8.encode(ref)],
  refCount: refs.length,
  lit: lit,
  current: current,
  searchMatch: searchMatch,
);

/// Owns a `HistoryMotion` for a test and disposes it with the tree.
class TestMotionHost extends StatefulWidget {
  const TestMotionHost({required this.onReady, this.childBuilder, super.key});

  final ValueChanged<HistoryMotion> onReady;
  final Widget Function(HistoryMotion motion)? childBuilder;

  @override
  State<TestMotionHost> createState() => _TestMotionHostState();
}

class _TestMotionHostState extends State<TestMotionHost>
    with TickerProviderStateMixin {
  late final HistoryMotion _motion = HistoryMotion(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_motion);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.childBuilder?.call(_motion) ?? const SizedBox();
}
