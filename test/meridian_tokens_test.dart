import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/meridian_finders.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  test('Meridian tokens match the light and dark design contract', () {
    expect(gitlamaColors(Brightness.light).pane, const Color(0xFFFFFFFF));
    expect(gitlamaColors(Brightness.dark).pane, const Color(0xFF122027));
    expect(gitlamaColors(Brightness.light).accent, const Color(0xFF056CB3));
    expect(gitlamaColors(Brightness.dark).accent, const Color(0xFF5BB1FE));
    expect(gitlamaColors(Brightness.light).series, hasLength(8));
    expect(gitlamaColors(Brightness.dark).series, hasLength(8));
    expect(MeridianSize.row, 28);
    expect(gitlamaRadius.lg, 10);
    expect(MeridianSpace.space3, 6);
    expect(gitlamaText.body.fontSize, 13);
  });

  test(
    'application themes use Meridian ground, density and tooltip timing',
    () {
      expect(
        buildAppTheme(Brightness.light).scaffoldBackgroundColor,
        gitlamaColors(Brightness.light).ground,
      );
      expect(
        buildAppTheme(Brightness.dark).scaffoldBackgroundColor,
        gitlamaColors(Brightness.dark).ground,
      );
      expect(gitlamaDensities.map((d) => d.rowExtent).toList(), [24, 28, 32]);
      expect(
        buildAppTheme(Brightness.light).tooltipTheme.waitDuration,
        const Duration(milliseconds: 500),
      );
    },
  );
}
