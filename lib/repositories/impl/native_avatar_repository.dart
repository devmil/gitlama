import 'dart:typed_data';

import '../../rust/api.dart' as native;
import '../avatar_repository.dart';

final class NativeAvatarRepository implements AvatarRepository {
  @override
  Future<Uint8List?> load(String hash, {required bool enabled}) async {
    final image = await native.avatarImage(hash: hash, enabled: enabled);
    return image?.bytes;
  }

  @override
  Future<void> clearCache() => native.avatarClearCache();
}
