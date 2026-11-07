import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/services/inspector/lens_availability.dart';

void main() {
  test('a submodule has no contents or blame, wherever it is listed', () {
    for (final availability in [
      lensAvailabilityFor(
        directory: false,
        changed: true,
        changeKind: CommitFileChangeKind.submodule,
      ),
      lensAvailabilityFor(
        directory: false,
        changed: false,
        treeKind: CommitTreeEntryKind.submodule,
      ),
      lensAvailabilityFor(directory: false, changed: true, mode: 0xE000),
    ]) {
      expect(
        availability[InspectorLens.contents],
        LensUnavailableReason.submodule,
      );
      expect(
        availability[InspectorLens.blame],
        LensUnavailableReason.submodule,
      );
    }
  });

  test('binary files show contents but no blame', () {
    final binary = lensAvailabilityFor(
      directory: false,
      changed: true,
      changeKind: CommitFileChangeKind.binary,
    );
    expect(binary[InspectorLens.contents], isNull);
    expect(binary[InspectorLens.blame], LensUnavailableReason.needsText);
  });

  test('all files can be browsed only for one commit not yet listing them', () {
    const commit = InspectorLocation(target: CommitTarget('c'));
    expect(canBrowseAllFiles(commit), isTrue);
    expect(
      canBrowseAllFiles(commit.copyWith(scope: InspectorScope.all)),
      isFalse,
    );
    expect(
      canBrowseAllFiles(
        const InspectorLocation(
          target: ComparisonTarget(base: 'a', commit: 'c'),
        ),
      ),
      isFalse,
    );
    expect(canBrowseAllFiles(null), isFalse);
  });
}
