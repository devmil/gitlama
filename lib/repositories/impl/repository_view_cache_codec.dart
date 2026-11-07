import 'dart:convert';
import 'dart:typed_data';

import '../../models/history.dart';
import '../../models/repository_state.dart';
import '../../models/repository_view_cache.dart';
import '../../models/settings.dart';

/// Version of the encoded form. An entry of any other version is discarded;
/// the cache is rebuilt from the repository and needs no migration.
const repositoryViewCacheSchema = 4;
const _format = 'gitlama.repository-view';

Uint8List encodeRepositoryView(RepositoryViewCacheEntry entry) => utf8.encode(
  jsonEncode({
    'format': _format,
    'schema': repositoryViewCacheSchema,
    if (entry.refs case final refs?) 'refs': _refs(refs),
    if (entry.refCounts case final counts?)
      'refCounts': [
        counts.branches,
        counts.remotes,
        counts.tags,
        counts.stashes,
        counts.worktrees,
      ],
    if (entry.status case final status?) 'status': _status(status),
    if (entry.history case final history?) 'history': _history(history),
  }),
);

/// The entry in [bytes], or null when they hold anything else: another
/// schema, a truncated file, or values this version does not know.
RepositoryViewCacheEntry? decodeRepositoryView(List<int> bytes) {
  try {
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    if (document['format'] != _format ||
        document['schema'] != repositoryViewCacheSchema) {
      return null;
    }
    final counts = document['refCounts'] as List<Object?>?;
    final entry = RepositoryViewCacheEntry(
      refs: switch (document['refs']) {
        final Map<String, Object?> value => _readRefs(value),
        null => null,
        _ => throw const FormatException(),
      },
      refCounts: counts == null
          ? null
          : RepositoryRefCounts(
              branches: counts[0]! as int,
              remotes: counts[1]! as int,
              tags: counts[2]! as int,
              stashes: counts[3]! as int,
              worktrees: counts[4]! as int,
            ),
      status: switch (document['status']) {
        final Map<String, Object?> value => _readStatus(value),
        null => null,
        _ => throw const FormatException(),
      },
      history: switch (document['history']) {
        final Map<String, Object?> value => _readHistory(value),
        null => null,
        _ => throw const FormatException(),
      },
    );
    return entry.isEmpty ? null : entry;
  } on Object {
    // Any malformed entry is an absent entry.
    return null;
  }
}

String _bytes(List<int> value) => base64.encode(value);
List<int> _readBytes(Object? value) => base64.decode(value! as String);
String? _optionalBytes(List<int>? value) =>
    value == null ? null : base64.encode(value);
List<int>? _readOptionalBytes(Object? value) =>
    value == null ? null : base64.decode(value as String);

Map<String, Object?> _path(NativePathIdentity value) {
  final units = ByteData(value.units.length * 2);
  for (var index = 0; index < value.units.length; index += 1) {
    units.setUint16(index * 2, value.units[index], Endian.little);
  }
  return {
    'platform': value.platform.name,
    'units': base64.encode(units.buffer.asUint8List()),
  };
}

NativePathIdentity _readPath(Object? value) {
  final map = value! as Map<String, Object?>;
  final bytes = base64.decode(map['units']! as String);
  if (bytes.length.isOdd) throw const FormatException();
  final data = ByteData.sublistView(bytes);
  return NativePathIdentity(
    platform: NativePathPlatform.values.byName(map['platform']! as String),
    units: [
      for (var index = 0; index < bytes.length; index += 2)
        data.getUint16(index, Endian.little),
    ],
  );
}

List<Object?> _reference(RepositoryReference value) => [
  _bytes(value.name),
  value.target,
  value.head,
  value.published,
  _optionalBytes(value.upstream),
  value.ahead,
  value.behind,
  value.upstreamGone,
  _optionalBytes(value.fullName),
];

RepositoryReference _readReference(Object? value) {
  final fields = value! as List<Object?>;
  if (fields.length != 9) throw const FormatException();
  return RepositoryReference(
    name: _readBytes(fields[0]),
    target: fields[1]! as String,
    head: fields[2]! as bool,
    published: fields[3]! as bool,
    upstream: _readOptionalBytes(fields[4]),
    ahead: fields[5]! as int,
    behind: fields[6]! as int,
    upstreamGone: fields[7]! as bool,
    fullName: _readOptionalBytes(fields[8]),
  );
}

Map<String, Object?> _refs(RepositoryRefs value) => {
  'branches': [for (final item in value.branches) _reference(item)],
  'remotes': [
    for (final remote in value.remotes)
      {
        'name': _bytes(remote.name),
        'displayUrl': _bytes(remote.displayUrl),
        'branches': [for (final item in remote.branches) _reference(item)],
      },
  ],
  'tags': [for (final item in value.tags) _reference(item)],
  'stashes': [
    for (final stash in value.stashes)
      [_bytes(stash.selector), stash.objectId, _bytes(stash.subject)],
  ],
  'truncated': value.truncated,
};

RepositoryRefs _readRefs(Map<String, Object?> value) => RepositoryRefs(
  branches: [
    for (final item in value['branches']! as List<Object?>)
      _readReference(item),
  ],
  remotes: [
    for (final item in value['remotes']! as List<Object?>)
      RepositoryRemote(
        name: _readBytes((item! as Map<String, Object?>)['name']),
        displayUrl: _readBytes((item as Map<String, Object?>)['displayUrl']),
        branches: [
          for (final branch in item['branches']! as List<Object?>)
            _readReference(branch),
        ],
      ),
  ],
  tags: [
    for (final item in value['tags']! as List<Object?>) _readReference(item),
  ],
  stashes: [
    for (final item in value['stashes']! as List<Object?>)
      RepositoryStash(
        selector: _readBytes((item! as List<Object?>)[0]),
        objectId: (item as List<Object?>)[1]! as String,
        subject: _readBytes(item[2]),
      ),
  ],
  truncated: value['truncated']! as bool,
);

Map<String, Object?> _status(RepositoryStatus value) => {
  'workingTree': value.workingTree.name,
  'branchName': _optionalBytes(value.branchName),
  'headObjectId': value.headObjectId,
  'upstream': _optionalBytes(value.upstream),
  'ahead': value.ahead.toString(),
  'behind': value.behind.toString(),
  'entries': [
    for (final entry in value.entries)
      [
        entry.kind.name,
        _path(entry.path),
        entry.source == null ? null : _path(entry.source!),
        entry.index.name,
        entry.worktree.name,
      ],
  ],
  'totalEntries': value.totalEntries.toString(),
  'entriesTruncated': value.entriesTruncated,
  'operations': [
    for (final operation in value.operations)
      [operation.kind.name, operation.current, operation.total],
  ],
};

RepositoryStatus _readStatus(Map<String, Object?> value) => RepositoryStatus(
  workingTree: WorkingTreeState.values.byName(value['workingTree']! as String),
  branchName: _readOptionalBytes(value['branchName']),
  headObjectId: value['headObjectId'] as String?,
  upstream: _readOptionalBytes(value['upstream']),
  ahead: BigInt.parse(value['ahead']! as String),
  behind: BigInt.parse(value['behind']! as String),
  entries: [
    for (final item in value['entries']! as List<Object?>)
      RepositoryStatusEntry(
        kind: StatusEntryKind.values.byName(
          (item! as List<Object?>)[0]! as String,
        ),
        path: _readPath((item as List<Object?>)[1]),
        source: item[2] == null ? null : _readPath(item[2]),
        index: ChangeKind.values.byName(item[3]! as String),
        worktree: ChangeKind.values.byName(item[4]! as String),
      ),
  ],
  totalEntries: BigInt.parse(value['totalEntries']! as String),
  entriesTruncated: value['entriesTruncated']! as bool,
  operations: [
    for (final item in value['operations']! as List<Object?>)
      RepositoryOperationState(
        kind: RepositoryOperationKind.values.byName(
          (item! as List<Object?>)[0]! as String,
        ),
        current: (item as List<Object?>)[1] as int?,
        total: item[2] as int?,
      ),
  ],
);

Map<String, Object?> _history(HistoryPage value) => {
  'totalRows': value.totalRows,
  'laneCount': value.laneCount,
  'currentObjectId': value.currentObjectId,
  'branchFilter': value.branchFilter.references,
  'otherRefs': value.otherRefs,
  'rows': [
    for (final row in value.rows)
      [
        row.objectId,
        row.parents,
        [for (final reference in row.refs) _bytes(reference)],
        row.refCount,
        row.refsTruncated,
        row.lane,
        row.shape,
        _bytes(row.subject),
        _bytes(row.author),
        row.avatarHash,
        row.authorTime,
        row.metadataFailure?.name,
        row.current,
        row.wipChangedFiles,
        row.wipStagedFiles,
      ],
  ],
  'segments': [
    for (final segment in value.segments)
      [
        segment.fromObjectId,
        segment.toObjectId,
        segment.parentOrdinal,
        segment.fromLane,
        segment.toLane,
        segment.kind,
        segment.fromRow,
        segment.toRow,
        segment.lit,
      ],
  ],
};

HistoryPage _readHistory(Map<String, Object?> value) {
  final rows = [
    for (final item in value['rows']! as List<Object?>) _readRow(item),
  ];
  final totalRows = value['totalRows']! as int;
  if (rows.isEmpty || totalRows < rows.length) throw const FormatException();
  return HistoryPage(
    requestId: cachedHistoryRequestId,
    complete: false,
    totalRows: totalRows,
    offset: 0,
    rows: rows,
    segments: [
      for (final item in value['segments']! as List<Object?>)
        HistoryTopologySegment(
          fromObjectId: (item! as List<Object?>)[0]! as String,
          toObjectId: (item as List<Object?>)[1]! as String,
          parentOrdinal: item[2]! as int,
          fromLane: item[3]! as int,
          toLane: item[4]! as int,
          kind: item[5]! as int,
          fromRow: item.length > 6 ? item[6] as int? : null,
          toRow: item.length > 7 ? item[7] as int? : null,
          lit: item.length > 8 ? item[8] as bool? : null,
        ),
    ],
    laneCount: value['laneCount']! as int,
    payloadBytes: 0,
    currentObjectId: value['currentObjectId'] as String?,
    branchFilter: HistoryBranchFilter([
      for (final reference in value['branchFilter']! as List<Object?>)
        reference! as String,
    ]),
    otherRefs: value['otherRefs']! as bool,
  );
}

HistoryTopologyRow _readRow(Object? value) {
  final fields = value! as List<Object?>;
  if (fields.length != 15) throw const FormatException();
  final failure = fields[11] as String?;
  return HistoryTopologyRow(
    objectId: fields[0]! as String,
    parents: [
      for (final parent in fields[1]! as List<Object?>) parent! as String,
    ],
    refs: [for (final item in fields[2]! as List<Object?>) _readBytes(item)],
    refCount: fields[3]! as int,
    refsTruncated: fields[4]! as bool,
    lane: fields[5]! as int,
    shape: fields[6]! as int,
    subject: _readBytes(fields[7]),
    author: _readBytes(fields[8]),
    avatarHash: fields[9]! as String,
    authorTime: fields[10]! as int,
    metadataFailure: failure == null
        ? null
        : HistoryMetadataFailure.values.byName(failure),
    current: fields[12]! as bool,
    wipChangedFiles: fields[13]! as int,
    wipStagedFiles: fields[14]! as int,
  );
}
