import '../../models/inspection.dart';
import '../../models/inspector.dart';

const _symlinkMode = 0xA000;
const _gitlinkMode = 0xE000;
const _modeType = 0xF000;

/// Which lenses can show a focused path, with the reason for each that
/// cannot. A null map value means the lens is available. This is the one
/// rule; the file menus ask it too ([lensAvailabilityFor]).
Map<InspectorLens, LensUnavailableReason?> lensAvailability({
  required bool directory,
  CommitFileChange? change,
  CommitTreeEntryKind? treeKind,
}) => lensAvailabilityFor(
  directory: directory,
  changed: change != null,
  changeKind: change?.kind,
  mode: change?.newMode,
  treeKind: treeKind,
);

/// [lensAvailability] for a path known by its change kind, file mode and
/// tree entry kind. [changed] says whether the path changed in the commit.
Map<InspectorLens, LensUnavailableReason?> lensAvailabilityFor({
  required bool directory,
  required bool changed,
  CommitFileChangeKind? changeKind,
  int? mode,
  CommitTreeEntryKind? treeKind,
}) {
  if (directory) {
    return const {
      InspectorLens.diff: LensUnavailableReason.directory,
      InspectorLens.contents: LensUnavailableReason.directory,
      InspectorLens.blame: LensUnavailableReason.directory,
      InspectorLens.history: null,
    };
  }
  LensUnavailableReason? contents;
  LensUnavailableReason? blame;
  final type = (mode ?? 0) & _modeType;
  final submodule =
      treeKind == CommitTreeEntryKind.submodule ||
      changeKind == CommitFileChangeKind.submodule ||
      (mode != null && type == _gitlinkMode);
  final symlink =
      treeKind == CommitTreeEntryKind.symlink ||
      (mode != null && type == _symlinkMode);
  if (changeKind == CommitFileChangeKind.deleted) {
    contents = LensUnavailableReason.deleted;
    blame = LensUnavailableReason.deleted;
  } else if (submodule) {
    contents = LensUnavailableReason.submodule;
    blame = LensUnavailableReason.submodule;
  } else if (symlink ||
      changeKind == CommitFileChangeKind.binary ||
      changeKind == CommitFileChangeKind.image) {
    blame = LensUnavailableReason.needsText;
  }
  return {
    InspectorLens.diff: changed ? null : LensUnavailableReason.notChanged,
    InspectorLens.contents: contents,
    InspectorLens.blame: blame,
    InspectorLens.history: null,
  };
}

/// [requested] when available, otherwise the first available lens of Diff,
/// Contents and History.
InspectorLens stickyLens(
  InspectorLens requested,
  Map<InspectorLens, LensUnavailableReason?> availability,
) {
  if (availability[requested] == null) return requested;
  for (final lens in const [
    InspectorLens.diff,
    InspectorLens.contents,
    InspectorLens.history,
  ]) {
    if (availability[lens] == null) return lens;
  }
  return InspectorLens.history;
}

/// The path a change is listed under: its new path, or the old one when the
/// file was deleted.
List<int> changeDisplayPath(CommitFileChange change) =>
    change.newPath.isEmpty ? change.oldPath : change.newPath;
