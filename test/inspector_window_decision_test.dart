import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/inspector/inspector_actions.dart';
import 'package:gitlama/models/inspector.dart';

void main() {
  test('a diff stays in place whatever the setting or modifier', () {
    for (final visible in [true, false]) {
      for (final setting in ['pane', 'window']) {
        for (final invert in [true, false]) {
          expect(
            opensInWindow(
              lens: InspectorLens.diff,
              inspectorVisible: visible,
              setting: setting,
              invert: invert,
            ),
            isFalse,
            reason: 'visible: $visible, setting: $setting, invert: $invert',
          );
        }
      }
    }
  });

  test('other lenses follow the setting, inverted by the modifier', () {
    for (final lens in InspectorLens.values.where(
      (lens) => lens != InspectorLens.diff,
    )) {
      bool opens(String setting, {bool invert = false, bool visible = true}) =>
          opensInWindow(
            lens: lens,
            inspectorVisible: visible,
            setting: setting,
            invert: invert,
          );
      expect(opens('pane'), isFalse, reason: lens.name);
      expect(opens('window'), isTrue, reason: lens.name);
      expect(opens('pane', invert: true), isTrue, reason: lens.name);
      expect(opens('window', invert: true), isFalse, reason: lens.name);
      expect(opens('pane', visible: false), isTrue, reason: lens.name);
    }
  });
}
