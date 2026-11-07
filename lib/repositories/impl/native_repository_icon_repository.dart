import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../models/repository_appearance.dart';
import '../../models/settings.dart';
import '../repository_icon_repository.dart';

/// Larger files are not icons; refusing them keeps a tab strip cheap.
const repositoryIconMaximumBytes = 2 * 1024 * 1024;

const _extensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'svg'];

final class NativeRepositoryIconRepository implements RepositoryIconRepository {
  @override
  Future<NativePathIdentity?> chooseImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [XTypeGroup(extensions: _extensions)],
    );
    return file == null ? null : _identity(file.path);
  }

  @override
  Future<RepositoryIconImage?> loadImage(NativePathIdentity path) async {
    // A remote path is never read as a file on this computer.
    if (path.isRemote) return null;
    try {
      final file = File(_path(path));
      final length = await file.length();
      if (length == 0 || length > repositoryIconMaximumBytes) return null;
      return repositoryIconFromBytes(await file.readAsBytes());
    } on FileSystemException {
      return null;
    }
  }
}

/// Recognises a supported image by its content, not its name.
RepositoryIconImage? repositoryIconFromBytes(Uint8List bytes) {
  bool starts(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var index = 0; index < magic.length; index++) {
      if (bytes[offset + index] != magic[index]) return false;
    }
    return true;
  }

  final raster =
      starts(const [0x89, 0x50, 0x4E, 0x47]) || // PNG
      starts(const [0xFF, 0xD8, 0xFF]) || // JPEG
      starts(ascii.encode('GIF8')) ||
      (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) ||
      starts(ascii.encode('BM')) ||
      starts(const [0x00, 0x00, 0x01, 0x00]); // ICO
  if (raster) {
    return RepositoryIconImage(
      bytes: bytes,
      format: RepositoryIconFormat.raster,
    );
  }
  final head = utf8
      .decode(bytes.take(1024).toList(), allowMalformed: true)
      .trimLeft()
      .toLowerCase();
  if (head.startsWith('<svg') ||
      (head.startsWith('<?xml') && head.contains('<svg'))) {
    return RepositoryIconImage(bytes: bytes, format: RepositoryIconFormat.svg);
  }
  return null;
}

NativePathIdentity _identity(String path) => Platform.isWindows
    ? NativePathIdentity(
        platform: NativePathPlatform.windows,
        units: path.codeUnits,
      )
    : NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: utf8.encode(path),
      );

String _path(NativePathIdentity identity) => switch (identity.platform) {
  NativePathPlatform.unix => utf8.decode(
    identity.units.map((unit) => unit & 0xff).toList(growable: false),
    allowMalformed: true,
  ),
  NativePathPlatform.windows => String.fromCharCodes(identity.units),
};
