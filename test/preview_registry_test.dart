import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/preview_registry.dart';

void main() {
  final first = RepositorySessionIdentity(nativeId: BigInt.one, generation: 1);
  final second = RepositorySessionIdentity(nativeId: BigInt.two, generation: 1);

  test('forgetting a session drops its tokens in every family', () {
    final registry = PreviewRegistry();
    final stash = registry.sessions();
    final commits = registry.family<({RepositorySessionIdentity session})>(
      (value) => value.session,
    );
    stash[BigInt.one] = first;
    stash[BigInt.two] = second;
    commits[BigInt.from(3)] = (session: first);
    registry.forgetSession(first);
    expect(stash[BigInt.one], isNull);
    expect(stash[BigInt.two], same(second));
    expect(commits[BigInt.from(3)], isNull);
    expect(registry.length, 1);
  });

  test('clearing drops every family and a token admits once', () {
    final registry = PreviewRegistry();
    final families = [for (var i = 0; i < 14; i++) registry.sessions()];
    for (final (index, family) in families.indexed) {
      family[BigInt.from(index)] = first;
    }
    expect(families.first.remove(BigInt.zero), same(first));
    expect(families.first.remove(BigInt.zero), isNull);
    registry.clear();
    expect(registry.length, 0);
  });
}
