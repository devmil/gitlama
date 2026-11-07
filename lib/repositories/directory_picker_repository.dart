abstract interface class DirectoryPickerRepository {
  Future<String?> chooseDirectory({required bool canCreateDirectories});

  Future<String?> choosePatchFile();

  /// Asks where to save a new file, suggesting [suggestedName] and offering
  /// files ending in [extension]; null when the person cancels. The system
  /// dialog confirms replacing an existing file.
  Future<String?> chooseSaveFile({
    required String suggestedName,
    required String extension,
  });
}
