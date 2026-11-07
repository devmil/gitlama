import 'activity_repository.dart';
import 'advanced_rebase_repository.dart';
import 'commit_archive_repository.dart';
import 'commit_repository.dart';
import 'conflict_repository.dart';
import 'diff_syntax_repository.dart';
import 'extension_repository.dart';
import 'history_mutation_repository.dart';
import 'history_repository.dart';
import 'inspection_session_repository.dart';
import 'integration_repository.dart';
import 'named_snapshot_repository.dart';
import 'patch_repository.dart';
import 'power_tools_repository.dart';
import 'rebase_repository.dart';
import 'ref_mutation_repository.dart';
import 'session_lifecycle_repository.dart';
import 'stash_repository.dart';
import 'transfer_repository.dart';
import 'working_copy_repository.dart';

export 'activity_repository.dart';
export 'advanced_rebase_repository.dart';
export 'change_source_repository.dart';
export 'commit_archive_repository.dart';
export 'commit_repository.dart';
export 'conflict_repository.dart';
export 'diff_renderer_repository.dart';
export 'diff_syntax_repository.dart';
export 'extension_repository.dart';
export 'history_mutation_repository.dart';
export 'history_repository.dart';
export 'inspection_repository.dart';
export 'inspection_session_repository.dart';
export 'integration_repository.dart';
export 'named_snapshot_repository.dart';
export 'patch_repository.dart';
export 'power_tools_repository.dart';
export 'rebase_repository.dart';
export 'ref_mutation_repository.dart';
export 'session_lifecycle_repository.dart';
export 'stash_repository.dart';
export 'transfer_repository.dart';
export 'working_copy_repository.dart';

/// Everything one repository backend serves for its sessions: their
/// lifecycle and the families of reads and commands every backend offers.
///
/// The families a backend may lack (transfers, stashes, rebases, ...) are
/// separate contracts in their own files. Each family has one owning
/// service, which receives only that family's contract; the composition
/// root hands the same backend object to all of them.
abstract interface class RepositorySessionRepository
    implements
        SessionLifecycleRepository,
        ActivityRepository,
        WorkingCopyRepository,
        CommitRepository,
        RefMutationRepository,
        HistoryRepository,
        InspectionRepository,
        InspectionSessionRepository {}

/// A backend that serves every family: this computer's native sessions and
/// the router in front of local and remote backends. A remote session may
/// still refuse a family its connection does not offer.
abstract interface class CompleteSessionBackend
    implements
        RepositorySessionRepository,
        PatchRepositorySessionRepository,
        CommitArchiveRepositorySessionRepository,
        TransferRepositorySessionRepository,
        StashRepositorySessionRepository,
        HistoryMutationRepositorySessionRepository,
        RebaseRepositorySessionRepository,
        ConflictRepositorySessionRepository,
        AdvancedRebaseRepositorySessionRepository,
        NamedSnapshotRepositorySessionRepository,
        ExtensionRepositorySessionRepository,
        IntegrationRepositorySessionRepository,
        PowerToolsRepositorySessionRepository,
        DiffRendererRepositorySessionRepository,
        DiffSyntaxRepository {}
