import 'dart:typed_data';

abstract interface class AvatarRepository {
  Future<Uint8List?> load(String hash, {required bool enabled});
  Future<void> clearCache();
}
