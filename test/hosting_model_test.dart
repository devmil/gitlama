import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/hosting.dart';

void main() {
  test('branch decorations use exact repository and worst check state', () {
    const binding = HostingBindingResolution(
      state: HostingBindingState.bound,
      connectionId: 'github:test',
      providerRepository: 'team/project',
    );
    final decorations = hostingBranchDecorations(
      binding,
      HostingResources(
        changeRequests: [
          _pull('team/project', 'topic', HostingCheckState.passing),
          _pull('team/project', 'topic', HostingCheckState.failing),
          _pull('alice/fork', 'topic', HostingCheckState.pending),
        ],
      ),
    );

    expect(decorations, {'topic': HostingCheckState.failing});
  });
}

HostingChangeRequest _pull(
  String repository,
  String branch,
  HostingCheckState state,
) => HostingChangeRequest(
  stableId: '$repository:$branch:${state.name}',
  number: 1,
  title: 'Pull request',
  author: 'alice',
  state: HostingChangeRequestState.open,
  draft: false,
  sourceRepository: repository,
  sourceBranch: branch,
  targetRepository: 'team/project',
  targetBranch: 'main',
  headSha: 'abc123',
  webUrl: 'https://example.test/pull/1',
  reviewSummary: HostingReviewSummary.unknown,
  mergeability: HostingMergeability.unknown,
  checks: HostingCheckSummary(state: state),
);
