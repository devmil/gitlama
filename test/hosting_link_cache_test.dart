import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/hosting_link_cache_codec.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/hosting_link_cache.dart';

HostingChangeRequest _pull(int number, HostingChangeRequestState state) =>
    HostingChangeRequest(
      stableId: 'https://forge.example/team/project/pulls/$number',
      number: number,
      title: 'Pull $number',
      author: 'alice',
      state: state,
      draft: number.isEven,
      sourceRepository: 'team/project',
      sourceBranch: 'branch-$number',
      targetRepository: 'team/project',
      targetBranch: 'main',
      headSha: 'abc$number',
      webUrl: 'https://forge.example/team/project/pulls/$number',
      reviewSummary: HostingReviewSummary.approved,
      mergeability: HostingMergeability.mergeable,
      checks: const HostingCheckSummary(state: HostingCheckState.passing),
    );

void main() {
  test('entries round-trip and keep only branches with pull requests', () {
    final decoded = decodeHostingLinks(
      encodeHostingLinks(
        HostingLinkCacheEntry(
          connectionId: 'forgejo:me',
          providerRepository: 'team/project',
          branches: {
            'empty': const [],
            'branch-2': [_pull(2, HostingChangeRequestState.merged)],
          },
          authored: [_pull(3, HostingChangeRequestState.open)],
        ),
      ),
    )!;
    expect(decoded.matches('forgejo:me', 'team/project'), isTrue);
    expect(decoded.branches.keys, ['branch-2']);
    final pull = decoded.branches['branch-2']!.single;
    expect(pull.state, HostingChangeRequestState.merged);
    expect(pull.draft, isTrue);
    expect(pull.checks.state, HostingCheckState.passing);
    expect(pull.reviewSummary, HostingReviewSummary.unknown);
    expect(decoded.authored!.single.number, 3);
  });

  test('another schema and damaged data read as absent', () {
    expect(
      decodeHostingLinks(
        Uint8List.fromList(utf8.encode(jsonEncode({'schema': 99}))),
      ),
      isNull,
    );
    expect(decodeHostingLinks(Uint8List.fromList([0xff, 0x00])), isNull);
  });
}
