import 'dart:typed_data';

import 'package:gitlama/models/repository_appearance.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/repository_icon_repository.dart';

/// The smallest PNG signature the icon repository recognises.
final fakePngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);

final class FakeRepositoryIconRepository implements RepositoryIconRepository {
  FakeRepositoryIconRepository({this.chosen, Map<String, Uint8List>? files})
    : files = files ?? {};

  NativePathIdentity? chosen;
  final Map<String, Uint8List> files;
  final List<String> loads = [];

  static NativePathIdentity path(String value) => NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: value.codeUnits,
  );

  @override
  Future<NativePathIdentity?> chooseImage() async => chosen;

  @override
  Future<RepositoryIconImage?> loadImage(NativePathIdentity path) async {
    final key = String.fromCharCodes(path.units);
    loads.add(key);
    final bytes = files[key];
    return bytes == null
        ? null
        : RepositoryIconImage(
            bytes: bytes,
            format: RepositoryIconFormat.raster,
          );
  }
}
