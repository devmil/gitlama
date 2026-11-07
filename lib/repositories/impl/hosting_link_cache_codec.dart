import 'dart:convert';
import 'dart:typed_data';

import '../../models/hosting.dart';
import '../../models/hosting_link_cache.dart';

const _schema = 1;

Uint8List encodeHostingLinks(HostingLinkCacheEntry entry) {
  final branches = entry.branches.entries
      .where((branch) => branch.value.isNotEmpty)
      .toList();
  final kept = branches.skip(
    branches.length > hostingLinkCacheBranchLimit
        ? branches.length - hostingLinkCacheBranchLimit
        : 0,
  );
  return utf8.encode(
    jsonEncode({
      'schema': _schema,
      'connection': entry.connectionId,
      'repository': entry.providerRepository,
      'branches': [
        for (final MapEntry(key: branch, value: pulls) in kept)
          {'branch': branch, 'pulls': pulls.map(_encodePull).toList()},
      ],
      'authored': entry.authored?.map(_encodePull).toList(),
    }),
  );
}

/// The entry in [bytes], or null for another schema or damaged data.
HostingLinkCacheEntry? decodeHostingLinks(Uint8List bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    if (value['schema'] != _schema) return null;
    final authored = value['authored'] as List<Object?>?;
    return HostingLinkCacheEntry(
      connectionId: value['connection']! as String,
      providerRepository: value['repository']! as String,
      branches: {
        for (final branch in value['branches']! as List<Object?>)
          (branch! as Map<String, Object?>)['branch']!
              as String: List.unmodifiable(
            ((branch as Map<String, Object?>)['pulls']! as List<Object?>).map(
              _decodePull,
            ),
          ),
      },
      authored: authored == null
          ? null
          : List.unmodifiable(authored.map(_decodePull)),
    );
  } on Object {
    return null;
  }
}

Map<String, Object?> _encodePull(HostingChangeRequest pull) => {
  'id': pull.stableId,
  'number': pull.number,
  'title': pull.title,
  'author': pull.author,
  'state': pull.state.name,
  'draft': pull.draft,
  'sourceRepository': pull.sourceRepository,
  'sourceBranch': pull.sourceBranch,
  'targetRepository': pull.targetRepository,
  'targetBranch': pull.targetBranch,
  'head': pull.headSha,
  'url': pull.webUrl,
  'checks': pull.checks.state.name,
};

HostingChangeRequest _decodePull(Object? value) {
  final pull = value! as Map<String, Object?>;
  return HostingChangeRequest(
    stableId: pull['id']! as String,
    number: pull['number']! as int,
    title: pull['title']! as String,
    author: pull['author']! as String,
    state: HostingChangeRequestState.values.byName(pull['state']! as String),
    draft: pull['draft']! as bool,
    sourceRepository: pull['sourceRepository']! as String,
    sourceBranch: pull['sourceBranch']! as String,
    targetRepository: pull['targetRepository']! as String,
    targetBranch: pull['targetBranch']! as String,
    headSha: pull['head']! as String,
    webUrl: pull['url']! as String,
    // Reviews, mergeability and individual checks are not kept: they are
    // only shown fresh.
    reviewSummary: HostingReviewSummary.unknown,
    mergeability: HostingMergeability.unknown,
    checks: HostingCheckSummary(
      state: HostingCheckState.values.byName(pull['checks']! as String),
    ),
  );
}
