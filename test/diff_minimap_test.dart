import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/inspector/commit_diff_pane.dart';

void main() {
  testWidgets('the minimap follows the newest of two shared positions', (
    tester,
  ) async {
    // Selecting another commit mounts its diff view before the previous one
    // unmounts. Both are attached to the pane's controller for that frame.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget list(int rows) => Expanded(
      child: ListView.builder(
        controller: controller,
        itemCount: rows,
        itemExtent: 20,
        itemBuilder: (context, index) => const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: Column(children: [list(100), list(400)])),
              SizedBox(
                width: 12,
                child: DiffMinimap(
                  controller: controller,
                  totalRows: 400,
                  rows: const {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(controller.positions, hasLength(2));
    controller.positions.last.jumpTo(100);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
