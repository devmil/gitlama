import 'package:file_selector/file_selector.dart';

import '../directory_picker_repository.dart';

final class NativeDirectoryPickerRepository
    implements DirectoryPickerRepository {
  @override
  Future<String?> chooseDirectory({required bool canCreateDirectories}) =>
      getDirectoryPath(canCreateDirectories: canCreateDirectories);

  @override
  Future<String?> choosePatchFile() async => (await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(extensions: ['patch', 'diff']),
    ],
  ))?.path;

  @override
  Future<String?> chooseSaveFile({
    required String suggestedName,
    required String extension,
  }) async => (await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(extensions: [extension]),
    ],
  ))?.path;
}
