import '../models/repository_appearance.dart';
import '../models/settings.dart';

/// The file boundary behind custom repository icons.
abstract interface class RepositoryIconRepository {
  /// Asks for an image file; `null` when the person cancels.
  Future<NativePathIdentity?> chooseImage();

  /// Reads a bounded image; `null` when it is missing, unreadable, too large
  /// or not a supported image.
  Future<RepositoryIconImage?> loadImage(NativePathIdentity path);
}
