import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/settings.dart';

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _repository = NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: '/tmp/repo'.codeUnits,
);

String _lens(InspectorLens lens) => switch (lens) {
  InspectorLens.diff => 'Diff',
  InspectorLens.contents => 'Contents',
  InspectorLens.blame => 'Blame',
  InspectorLens.history => 'History',
};

void main() {
  group('normalization', () {
    test('comparisons only list changed files', () {
      final location = const InspectorLocation(
        target: ComparisonTarget(base: _a, commit: _b),
        scope: InspectorScope.all,
      ).normalized();
      expect(location.scope, InspectorScope.changed);
    });

    test('no focus shows the diff without range or history entry', () {
      final location = const InspectorLocation(
        target: CommitTarget(_a),
        scope: InspectorScope.all,
        lens: InspectorLens.blame,
        lines: InspectorLineRange(1, 2),
        historyCommit: _b,
        anchor: 7,
      ).normalized();
      expect(location.lens, InspectorLens.diff);
      expect(location.lines, isNull);
      expect(location.historyCommit, isNull);
      expect(location.scope, InspectorScope.all);
      expect(location.anchor, 7);
    });

    test('a line range and history entry only exist in the history lens', () {
      final location = InspectorLocation(
        target: const CommitTarget(_a),
        path: 'f'.codeUnits,
        lens: InspectorLens.blame,
        lines: const InspectorLineRange(1, 2),
        historyCommit: _b,
      ).normalized();
      expect(location.lines, isNull);
      expect(location.historyCommit, isNull);
      final history = InspectorLocation(
        target: const CommitTarget(_a),
        path: 'f'.codeUnits,
        lens: InspectorLens.history,
        lines: const InspectorLineRange(1, 2),
        historyCommit: _b,
      ).normalized();
      expect(history.lines, const InspectorLineRange(1, 2));
      expect(history.historyCommit, _b);
    });

    test('a folder is shown through its history without line range', () {
      final location = InspectorLocation(
        target: const CommitTarget(_a),
        path: 'lib'.codeUnits,
        directory: true,
        lines: const InspectorLineRange(1, 2),
      ).normalized();
      expect(location.lens, InspectorLens.history);
      expect(location.lines, isNull);
    });
  });

  test('sameAs ignores the anchor and equality does not', () {
    final first = InspectorLocation(
      target: const CommitTarget(_a),
      path: 'f'.codeUnits,
      anchor: 1,
    );
    final second = InspectorLocation(
      target: const CommitTarget(_a),
      path: List.of('f'.codeUnits),
      anchor: 2,
    );
    expect(first.sameAs(second), isTrue);
    expect(first == second, isFalse);
    expect(first == first.copyWith(anchor: 1), isTrue);
    expect(first.hashCode, first.copyWith().hashCode);
    expect(first.sameAs(first.copyWith(lens: InspectorLens.blame)), isFalse);
    expect(
      first.sameAs(first.copyWith(target: const CommitTarget(_b))),
      isFalse,
    );
  });

  test('copyWith clears path, lines and history entries explicitly', () {
    final location = InspectorLocation(
      target: const CommitTarget(_a),
      path: 'f'.codeUnits,
      directory: true,
      lines: const InspectorLineRange(1, 2),
      historyCommit: _b,
    );
    final cleared = location.copyWith(
      clearPath: true,
      clearLines: true,
      clearHistoryCommit: true,
    );
    expect(cleared.path, isNull);
    expect(cleared.directory, isFalse);
    expect(cleared.lines, isNull);
    expect(cleared.historyCommit, isNull);
  });

  test('labels name the commit, file and lens', () {
    const commit = InspectorLocation(target: CommitTarget(_a));
    expect(inspectorLocationLabel(commit, lensName: _lens), 'aaaaaaaa');
    final file = commit.copyWith(path: 'lib/pubspec.lock'.codeUnits);
    expect(
      inspectorLocationLabel(file, lensName: _lens),
      'aaaaaaaa · pubspec.lock',
    );
    for (final lens in [
      InspectorLens.contents,
      InspectorLens.blame,
      InspectorLens.history,
    ]) {
      expect(
        inspectorLocationLabel(file.copyWith(lens: lens), lensName: _lens),
        'aaaaaaaa · pubspec.lock · ${_lens(lens)}',
      );
    }
    expect(
      inspectorLocationLabel(
        const InspectorLocation(
          target: ComparisonTarget(base: _a, commit: _b),
        ),
        lensName: _lens,
      ),
      'aaaaaaaa→bbbbbbbb',
    );
  });

  group('window requests', () {
    test('schema 2 round-trips every field', () {
      final location = InspectorLocation(
        target: const CommitTarget(_a),
        scope: InspectorScope.all,
        path: [0xff, 0x2f, 0x61],
        lens: InspectorLens.history,
        lines: const InspectorLineRange(3, 9),
        historyCommit: _b,
        anchor: 12,
      );
      final request = InspectionWindowRequest(
        repository: _repository,
        location: location,
      );
      final decoded = InspectionWindowRequest.decode(request.encode())!;
      expect(decoded.location, location);
      expect(decoded.repository.units, _repository.units);
      expect(decoded.repository.platform, _repository.platform);
      final comparison = InspectionWindowRequest(
        repository: _repository,
        location: const InspectorLocation(
          target: ComparisonTarget(base: _a, commit: _b),
        ),
      );
      expect(
        InspectionWindowRequest.decode(comparison.encode())!.location,
        comparison.location,
      );
      final folder = InspectionWindowRequest(
        repository: _repository,
        location: InspectorLocation(
          target: const CommitTarget(_a),
          path: 'lib'.codeUnits,
          directory: true,
          lens: InspectorLens.history,
        ),
      );
      expect(
        InspectionWindowRequest.decode(folder.encode())!.location,
        folder.location,
      );
    });

    String schemaOne(String kind, {List<int>? path}) => jsonEncode({
      'schema': 1,
      'kind': kind,
      'platform': 'unix',
      'units': _repository.units,
      'commit': _a,
      'path': path,
    });

    test('schema 1 blame requests open the blame lens', () {
      final request = InspectionWindowRequest.decode(
        schemaOne('blame', path: 'src/f'.codeUnits),
      )!;
      expect(
        request.location,
        InspectorLocation(
          target: const CommitTarget(_a),
          path: 'src/f'.codeUnits,
          lens: InspectorLens.blame,
        ),
      );
    });

    test('schema 1 tree requests open all files', () {
      final root = InspectionWindowRequest.decode(schemaOne('tree'))!;
      expect(
        root.location,
        const InspectorLocation(
          target: CommitTarget(_a),
          scope: InspectorScope.all,
        ),
      );
      final folder = InspectionWindowRequest.decode(
        schemaOne('tree', path: 'lib'.codeUnits),
      )!;
      expect(
        folder.location,
        InspectorLocation(
          target: const CommitTarget(_a),
          scope: InspectorScope.all,
          path: 'lib'.codeUnits,
          directory: true,
          lens: InspectorLens.history,
        ),
      );
    });

    Map<String, Object?> valid() => {
      'schema': 2,
      'platform': 'unix',
      'units': _repository.units,
      'location': {
        'kind': 'commit',
        'commit': _a,
        'scope': 'changed',
        'path': 'f'.codeUnits,
        'directory': false,
        'lens': 'history',
        'lines': [1, 2],
        'historyCommit': _b,
        'anchor': 0,
      },
    };

    test('a valid schema 2 request decodes', () {
      expect(InspectionWindowRequest.decode(jsonEncode(valid())), isNotNull);
    });

    final rejections = <String, void Function(Map<String, Object?>)>{
      'unknown schema': (data) => data['schema'] = 4,
      'empty units': (data) => data['units'] = <int>[],
      'unit out of range': (data) => data['units'] = [70000],
      'unknown platform': (data) => data['platform'] = 'beos',
      'non-hex commit': (data) => (data['location']! as Map)['commit'] = 'HEAD',
      'non-hex base': (data) {
        final location = data['location']! as Map;
        location['kind'] = 'comparison';
        location['base'] = 'main';
      },
      'base on a commit': (data) => (data['location']! as Map)['base'] = _b,
      'unknown kind': (data) => (data['location']! as Map)['kind'] = 'stash',
      'unknown scope': (data) => (data['location']! as Map)['scope'] = 'staged',
      'unknown lens': (data) => (data['location']! as Map)['lens'] = 'tree',
      'byte out of range': (data) => (data['location']! as Map)['path'] = [256],
      'empty path': (data) => (data['location']! as Map)['path'] = <int>[],
      'reversed lines': (data) => (data['location']! as Map)['lines'] = [5, 2],
      'line zero': (data) => (data['location']! as Map)['lines'] = [0, 2],
      'three lines': (data) => (data['location']! as Map)['lines'] = [1, 2, 3],
      'negative anchor': (data) => (data['location']! as Map)['anchor'] = -1,
      'non-hex history entry': (data) =>
          (data['location']! as Map)['historyCommit'] = 'x',
      'folder without path': (data) {
        final location = data['location']! as Map;
        location.remove('path');
        location['directory'] = true;
      },
      'missing location': (data) => data.remove('location'),
    };
    for (final entry in rejections.entries) {
      test('rejects ${entry.key}', () {
        final data = valid();
        entry.value(data);
        expect(InspectionWindowRequest.decode(jsonEncode(data)), isNull);
      });
    }

    test('rejects oversized payloads', () {
      expect(InspectionWindowRequest.decode('x' * 65537), isNull);
      expect(InspectionWindowRequest.decode(''), isNull);
    });
  });
}
