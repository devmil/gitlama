/// The remote reads an inspector window may make through the main window's
/// connection, by wire method name: what the inspector reads of a commit,
/// tree, file history, blame or diff, and its syntax colours. Every other method, and every write,
/// is refused before it reaches the host.
const remoteInspectionReadMethods = <String>{
  'repositorySessionCommitInspection',
  'repositorySessionTree',
  'repositorySessionPathHistory',
  'repositorySessionRangeHistory',
  'repositorySessionBlameLoad',
  'repositorySessionBlamePage',
  'repositorySessionCommitDiffLoad',
  'repositorySessionDiffPage',
  'repositorySessionDiffSearch',
  'repositorySessionDiffHunks',
  'repositorySessionDiffSelectionPatch',
  'repositorySessionCommitFileContent',
  'repositorySessionChangeSource',
  'repositorySessionChangeSourcePage',
  'repositorySessionDiffRendererInput',
  'repositorySessionDiffSyntaxPage',
  'repositorySessionDiffSyntaxCancel',
};

/// The most remote sessions one inspector window holds, and all windows
/// together. A window holds one; the bound only stops a runaway caller.
const remoteInspectionSessionsPerWindow = 4;
const remoteInspectionSessionsTotal = 64;
