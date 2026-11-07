import 'dart:convert';
import 'dart:typed_data';

import 'remote_contract.g.dart';

export 'remote_contract.g.dart';

/// The verified remote account and private helper store a remote workspace
/// belongs to, under the local host profile that reached it.
///
/// It is execution identity: two remote paths are the same workspace only when
/// their authorities are equal. A profile label or alias never substitutes.
final class RemoteAuthority {
  const RemoteAuthority({
    required this.profileId,
    required this.storeId,
    required this.accountUid,
  });

  /// The local profile's UUID.
  final String profileId;

  /// The helper store's 32-hex random identity.
  final String storeId;

  /// The remote effective user ID as a decimal string.
  final String accountUid;

  @override
  bool operator ==(Object other) =>
      other is RemoteAuthority &&
      other.profileId == profileId &&
      other.storeId == storeId &&
      other.accountUid == accountUid;

  @override
  int get hashCode => Object.hash(profileId, storeId, accountUid);
}

/// The identity a helper verified for a profile, recorded after an explicit
/// first attachment or rebind.
final class RemoteVerifiedIdentity {
  const RemoteVerifiedIdentity({
    required this.storeId,
    required this.accountUid,
    required this.accountName,
  });

  final String storeId;
  final String accountUid;

  /// Display data only; never part of the authority.
  final String accountName;

  @override
  bool operator ==(Object other) =>
      other is RemoteVerifiedIdentity &&
      other.storeId == storeId &&
      other.accountUid == accountUid &&
      other.accountName == accountName;

  @override
  int get hashCode => Object.hash(storeId, accountUid, accountName);
}

/// A locally stored connection through an SSH host or user@host destination.
/// Holds no credentials, options or commands.
final class RemoteHostProfile {
  const RemoteHostProfile({
    required this.id,
    required this.label,
    required this.alias,
    this.verified,
    this.writesAllowed = false,
    this.autoInstallHelper = false,
    this.color,
    this.icon,
  });

  /// At most 64 profiles are kept.
  static const capacity = 64;

  /// The canonical lowercase UUID.
  final String id;

  /// At most 128 Unicode scalar values without control characters.
  final String label;

  /// An SSH host or user@host destination; see [isValidRemoteAlias].
  final String alias;
  final RemoteVerifiedIdentity? verified;

  /// Whether the user allowed staging and normal commits for the verified
  /// identity. A rebind or alias change resets it.
  final bool writesAllowed;

  /// Whether GitLama installs its helper on the host without asking when
  /// the host lacks the helper this version needs. A changed alias or
  /// identity withdraws it.
  final bool autoInstallHelper;

  /// The key of an appearance colour the host's tabs show, or null.
  final String? color;

  /// The name of a catalogue icon the host's tabs show, or null.
  final String? icon;

  /// Whether the host's tabs identify it by colour or icon instead of its
  /// name.
  bool get hasMark => color != null || icon != null;

  RemoteAuthority? get authority {
    final identity = verified;
    return identity == null
        ? null
        : RemoteAuthority(
            profileId: id,
            storeId: identity.storeId,
            accountUid: identity.accountUid,
          );
  }

  RemoteHostProfile copyWith({
    String? label,
    String? alias,
    RemoteVerifiedIdentity? verified,
    bool clearVerified = false,
    bool? writesAllowed,
    bool? autoInstallHelper,
    String? Function()? color,
    String? Function()? icon,
  }) => RemoteHostProfile(
    id: id,
    label: label ?? this.label,
    alias: alias ?? this.alias,
    verified: clearVerified ? null : verified ?? this.verified,
    writesAllowed: writesAllowed ?? this.writesAllowed,
    autoInstallHelper: autoInstallHelper ?? this.autoInstallHelper,
    color: color == null ? this.color : color(),
    icon: icon == null ? this.icon : icon(),
  );

  @override
  bool operator ==(Object other) =>
      other is RemoteHostProfile &&
      other.id == id &&
      other.label == label &&
      other.alias == alias &&
      other.verified == verified &&
      other.writesAllowed == writesAllowed &&
      other.autoInstallHelper == autoInstallHelper &&
      other.color == color &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    alias,
    verified,
    writesAllowed,
    autoInstallHelper,
    color,
    icon,
  );
}

final _aliasPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]*(?:@[A-Za-z0-9][A-Za-z0-9._-]*)?$',
);

/// Whether [alias] is a host or `user@host`, at most 128 ASCII characters.
/// Each part starts with a letter or digit and contains letters, digits,
/// `.`, `_` or `-`. URIs, ports, whitespace and options are rejected.
bool isValidRemoteAlias(String alias) =>
    alias.length <= 128 && _aliasPattern.hasMatch(alias);

/// Whether [label] is a valid profile label.
bool isValidRemoteLabel(String label) {
  final runes = label.runes.toList();
  return runes.isNotEmpty &&
      runes.length <= 128 &&
      label.trim().isNotEmpty &&
      runes.every((rune) => rune >= 0x20 && (rune < 0x7f || rune > 0x9f));
}

final _profileIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _storeIdPattern = RegExp(r'^[0-9a-f]{32}$');
final _accountUidPattern = RegExp(r'^(0|[1-9][0-9]{0,9})$');

/// Whether [id] is a canonical lowercase hyphenated UUID.
bool isValidRemoteProfileId(String id) => _profileIdPattern.hasMatch(id);

/// Whether [id] is a helper store identity: 32 lowercase hexadecimal digits.
bool isValidRemoteStoreId(String id) => _storeIdPattern.hasMatch(id);

/// Whether [uid] is a canonical decimal user ID within the unsigned 32-bit
/// range.
bool isValidRemoteAccountUid(String uid) =>
    _accountUidPattern.hasMatch(uid) && int.parse(uid) <= 0xffffffff;

/// Whether [name] is a displayable account name: at most 128 UTF-8 bytes
/// without control characters.
bool isValidRemoteAccountName(String name) =>
    utf8.encode(name).length <= 128 &&
    name.runes.every((rune) => rune >= 0x20 && (rune < 0x7f || rune > 0x9f));

/// The decoded byte bound of a remote path, matching the wire contract.
const remotePathByteCapacity = ContractLimits.pathBytes;

/// Whether [units] are an absolute remote path: 1–16 KiB bytes, starting
/// with `/`, without NUL.
bool isValidRemotePathUnits(List<int> units) =>
    units.isNotEmpty &&
    units.length <= remotePathByteCapacity &&
    units.first == 0x2f &&
    units.every((unit) => unit > 0 && unit <= 0xff);

extension RemoteAuthorityValidation on RemoteAuthority {
  bool get isValid =>
      isValidRemoteProfileId(profileId) &&
      isValidRemoteStoreId(storeId) &&
      isValidRemoteAccountUid(accountUid);

  /// The authority as in-process message data between windows.
  Map<String, String> toMessage() => {
    'profileId': profileId,
    'storeId': storeId,
    'accountUid': accountUid,
  };
}

/// Reads an authority written by [RemoteAuthorityValidation.toMessage];
/// null unless it is a map of three valid fields.
RemoteAuthority? remoteAuthorityFromMessage(Object? value) {
  if (value is! Map) return null;
  final profileId = value['profileId'];
  final storeId = value['storeId'];
  final accountUid = value['accountUid'];
  if (profileId is! String || storeId is! String || accountUid is! String) {
    return null;
  }
  final authority = RemoteAuthority(
    profileId: profileId,
    storeId: storeId,
    accountUid: accountUid,
  );
  return authority.isValid ? authority : null;
}

extension RemoteHostProfileValidation on RemoteHostProfile {
  bool get isValid {
    final identity = verified;
    return isValidRemoteProfileId(id) &&
        isValidRemoteLabel(label) &&
        isValidRemoteAlias(alias) &&
        (identity == null ||
            isValidRemoteStoreId(identity.storeId) &&
                isValidRemoteAccountUid(identity.accountUid) &&
                isValidRemoteAccountName(identity.accountName));
  }
}

/// The connection lifecycle, orthogonal to the repository phase.
enum RemoteConnectionPhase {
  idle,

  /// Copying the bundled helper to the host, before connecting.
  installing,
  connecting,
  handshaking,
  ready,
  disconnecting,
  disconnected,
  failed,
  identityChanged,
  retired,
}

/// Stable, localized remote failure codes. Raw SSH or helper output never
/// becomes user-visible text.
enum RemoteFailureCode {
  /// A remote write was sent but its outcome could not be established. It
  /// stays pending until a lookup resolves it; it is never resent.
  outcomeUnknown,
  sshUnavailable,
  sshUnsupported,
  sshConnectionFailed,
  helperNotInstalled,

  /// This application carries no helper to install; set up the host manually.
  installUnavailable,

  /// The host's helper directory could not be created or is a symbolic link.
  installDirectory,

  /// Writing the helper on the host failed, for example on a full disk.
  installWrite,

  /// The bytes that arrived on the host differ from the bundled helper.
  installDigest,

  /// The installed helper cannot run there, for example in a noexec home.
  installExecute,

  /// The installation ended without a recognizable result.
  installFailed,
  unsupportedPlatform,
  bootstrapFailed,
  handshakeTimeout,
  protocolMismatch,
  buildMismatch,
  gitMissing,
  gitUnsupported,
  storeUnavailable,
  identityChanged,
  identityMismatch,
  protocolViolation,
  disconnected,
  timedOut,
  canceled,
  capacity,
  unsupported,
  pathInvalid,
  pathNotFound,
  permissionDenied,
  notDirectory,
  directoryChanged,
  cursorExpired,
  writeNotPermitted,
  previewExpired,
  preconditionFailed,
  operationIdConflict,
  receiptCapacity,
  internal,
}

final class RemoteWorkspaceException implements Exception {
  const RemoteWorkspaceException(this.code, {this.hostTarget});
  final RemoteFailureCode code;

  /// The helper the host needs, when the launch reported a missing helper.
  final RemoteHelperTarget? hostTarget;

  @override
  String toString() => 'RemoteWorkspaceException(${code.name})';
}

/// Why a live host connection grants no writes.
enum RemoteWriteBlock {
  /// "Allow changes on this host" is off.
  notAllowed,

  /// Changes were allowed after this connection started.
  reconnect,

  /// The record of remote changes on this computer cannot be read.
  ledgerUnavailable,
}

/// What a helper reported in its hello, after validation.
final class RemoteHelperInfo {
  const RemoteHelperInfo({
    required this.buildId,
    required this.incarnation,
    required this.storeId,
    required this.accountUid,
    required this.accountName,
    required this.gitVersion,
    required this.capabilities,
  });

  final String buildId;
  final String incarnation;
  final String storeId;
  final String accountUid;
  final String accountName;
  final String? gitVersion;

  /// The negotiated intersection.
  final Set<RemoteCapability> capabilities;
}

/// One profile's connection as the user sees it.
final class RemoteConnectionState {
  const RemoteConnectionState({
    required this.profileId,
    required this.phase,
    this.failure,
    this.helper,
  });

  final String profileId;
  final RemoteConnectionPhase phase;
  final RemoteFailureCode? failure;
  final RemoteHelperInfo? helper;

  bool get ready => phase == RemoteConnectionPhase.ready;
}

/// A remote write recorded locally before its first byte was sent.
final class RemotePendingOperation {
  const RemotePendingOperation({
    required this.operationId,
    required this.epoch,
    required this.digest,
    required this.family,
    required this.authority,
    required this.binding,
    required this.pending,
    this.outcome,
    this.resultObjectId,
    required this.summary,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// 32 lowercase hex digits, fresh for every user execution.
  final String operationId;
  final String epoch;
  final String digest;
  final RemoteOperationFamily family;
  final RemoteAuthority authority;
  final String binding;

  /// Whether the outcome is still unresolved.
  final bool pending;
  final RemoteOperationOutcome? outcome;
  final String? resultObjectId;

  /// A short description such as the commit subject; at most 256 characters.
  final String summary;
  final int createdAtMs;
  final int updatedAtMs;

  RemotePendingOperation resolved(
    RemoteOperationOutcome outcome, {
    String? resultObjectId,
    required int atMs,
  }) => RemotePendingOperation(
    operationId: operationId,
    epoch: epoch,
    digest: digest,
    family: family,
    authority: authority,
    binding: binding,
    pending: false,
    outcome: outcome,
    resultObjectId: resultObjectId ?? this.resultObjectId,
    summary: summary,
    createdAtMs: createdAtMs,
    updatedAtMs: atMs,
  );

  RemotePendingOperation stillPending({
    RemoteOperationOutcome? outcome,
    required int atMs,
  }) => RemotePendingOperation(
    operationId: operationId,
    epoch: epoch,
    digest: digest,
    family: family,
    authority: authority,
    binding: binding,
    pending: true,
    outcome: outcome,
    resultObjectId: resultObjectId,
    summary: summary,
    createdAtMs: createdAtMs,
    updatedAtMs: atMs,
  );
}

/// A host platform a remote helper is built for.
enum RemoteHelperTarget {
  linuxX86_64(
    directory: 'linux-x86_64',
    triple: 'x86_64-unknown-linux-gnu',
    host: 'Linux/x86_64',
  ),

  /// 64-bit Arm Linux, such as 64-bit Raspberry Pi OS.
  linuxArm64(
    directory: 'linux-arm64',
    triple: 'aarch64-unknown-linux-gnu',
    host: 'Linux/aarch64',
  ),
  macosArm64(
    directory: 'macos-arm64',
    triple: 'aarch64-apple-darwin',
    host: 'Darwin/arm64',
  ),
  macosX86_64(
    directory: 'macos-x86_64',
    triple: 'x86_64-apple-darwin',
    host: 'Darwin/x86_64',
  );

  const RemoteHelperTarget({
    required this.directory,
    required this.triple,
    required this.host,
  });

  /// The bundle directory that carries this helper.
  final String directory;

  /// The Rust target the helper is compiled for.
  final String triple;

  /// `uname -s` and `uname -m` of a host that runs it.
  final String host;

  static RemoteHelperTarget? forTriple(Object? triple) =>
      values.where((target) => target.triple == triple).firstOrNull;
}

/// A helper that ships with this application, for one host platform.
final class RemoteHelperArtifact {
  const RemoteHelperArtifact({
    required this.buildId,
    required this.target,
    required this.sha256,
    required this.bytes,
  });

  final RemoteHelperTarget target;

  /// The helper ID, its compatibility version; it equals the application's
  /// own.
  final String buildId;

  /// The SHA-256 of [bytes] as 64 lowercase hex digits.
  final String sha256;
  final List<int> bytes;

  /// Where the installation places it on a host, relative to the home.
  String get installPath =>
      '~/.local/lib/gitlama/remote/$buildId/gitlama-remote-helper';
}

/// An entry of a remote directory listing.
enum RemoteEntryKind { directory, file, symlink, other }

final class RemoteDirectoryEntry {
  const RemoteDirectoryEntry({
    required this.name,
    required this.kind,
    required this.repository,
  });

  /// The exact native name bytes.
  final Uint8List name;
  final RemoteEntryKind kind;

  /// A cheap `.git` presence hint, not a full discovery.
  final bool repository;
}

final class RemoteDirectoryPage {
  const RemoteDirectoryPage({
    required this.directory,
    required this.parent,
    required this.entries,
    required this.cursor,
    required this.truncated,
  });

  /// The canonical absolute directory bytes.
  final Uint8List directory;
  final Uint8List? parent;
  final List<RemoteDirectoryEntry> entries;

  /// Continues this listing; null on the last page.
  final String? cursor;

  /// Whether the bounded scan stopped before the directory's end.
  final bool truncated;
}

/// Renders native path bytes for display: valid UTF-8 as text, other bytes
/// as `\xNN` escapes. Never parsed back into a path.
String displayRemotePath(List<int> bytes) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < bytes.length) {
    final byte = bytes[index];
    final length = byte < 0x80
        ? 1
        : byte >= 0xc2 && byte <= 0xdf
        ? 2
        : byte >= 0xe0 && byte <= 0xef
        ? 3
        : byte >= 0xf0 && byte <= 0xf4
        ? 4
        : 0;
    if (length == 0 || index + length > bytes.length) {
      buffer.write('\\x${byte.toRadixString(16).padLeft(2, '0')}');
      index += 1;
      continue;
    }
    var valid = true;
    var codePoint = length == 1 ? byte : byte & (0xff >> (length + 1));
    for (var offset = 1; offset < length; offset += 1) {
      final next = bytes[index + offset];
      if (next & 0xc0 != 0x80) {
        valid = false;
        break;
      }
      codePoint = (codePoint << 6) | (next & 0x3f);
    }
    final minimum = [0, 0, 0x80, 0x800, 0x10000][length];
    if (!valid ||
        codePoint < minimum ||
        codePoint > 0x10ffff ||
        (codePoint >= 0xd800 && codePoint <= 0xdfff) ||
        codePoint < 0x20 ||
        codePoint == 0x7f) {
      buffer.write('\\x${byte.toRadixString(16).padLeft(2, '0')}');
      index += 1;
      continue;
    }
    if (codePoint == 0x5c) {
      buffer.write(r'\\');
    } else {
      buffer.writeCharCode(codePoint);
    }
    index += length;
  }
  return buffer.toString();
}
