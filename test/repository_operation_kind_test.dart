import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/repository_state.dart';

void main() {
  test('rebase, cherry-pick and revert can skip a step, as in Git', () {
    expect(RepositoryOperationKind.values.where((kind) => kind.canSkip), [
      RepositoryOperationKind.rebase,
      RepositoryOperationKind.cherryPick,
      RepositoryOperationKind.revert,
    ]);
  });
}
