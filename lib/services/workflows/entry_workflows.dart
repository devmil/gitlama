import 'dart:async';

import '../../models/cli_forwarding.dart';
import '../../models/clone_attempt.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../cli_forwarding_service.dart';
import '../repository_session_service.dart';

/// What opening, cloning and creating repositories asks of the window.
abstract interface class EntryInteraction {
  bool get active;

  /// Asks for the URL or path to clone; null cancels.
  Future<String?> chooseCloneSource();

  /// Asks where a new repository goes (this computer or a host's profile)
  /// and whether it is bare; null cancels.
  Future<({String? profileId, bool bare})?> chooseInitialize({
    required bool initiallyBare,
  });

  /// Creates a repository on the host of [profileId]; the remote workflows
  /// ask their own questions.
  Future<RepositorySessionState?> initializeOnHost(
    String profileId, {
    required bool bare,
  });

  /// Asks for the credentials of a clone; null cancels.
  Future<({String? username, String secret})?> cloneCredentials();

  /// Asks whether to trust [challenge]'s host key.
  Future<bool> trustHostKey(HostKeyChallenge challenge);
}

/// What the welcome screen and the workspace notice show while opening.
final class EntryState {
  const EntryState({this.busy = false, this.failure, this.cloneFailure});

  /// An open, clone or creation runs; the entry actions wait.
  final bool busy;

  /// Why the last open or creation failed.
  final RepositoryFailureCode? failure;

  /// Why the last clone failed.
  final CloneFailureCode? cloneFailure;
}

/// Opening, cloning and creating repositories, with credential and host-key
/// retries, and the one owner of what the window says failed. It attaches
/// the window to forwarded command-line commands for its lifetime and hands
/// on the fetch and pull requests as one-shot events.
final class EntryWorkflowService {
  EntryWorkflowService(this._repositories, this._cli) {
    _sessionStates = _repositories.states.listen((state) {
      _set(
        failure: state.snapshot.failure?.code ?? state.transportFailure?.code,
        clearFailure: true,
      );
    });
    _cloneStates = _repositories.cloneStates.listen((state) {
      _set(cloneFailure: state.failure?.code, clearCloneFailure: true);
    });
    _cliCommands = _cli.commands.listen((command) {
      if (!_disposed) _forwarded.add(command);
    });
    _cli.attach();
  }

  final RepositorySessionService _repositories;
  final CliForwardingController _cli;
  late final StreamSubscription<RepositorySessionState> _sessionStates;
  late final StreamSubscription<CloneAttemptSnapshot> _cloneStates;
  late final StreamSubscription<CliForwardedCommand> _cliCommands;
  final StreamController<EntryState> _states =
      StreamController<EntryState>.broadcast(sync: true);
  final StreamController<CliForwardedCommand> _forwarded =
      StreamController<CliForwardedCommand>.broadcast(sync: true);
  var _state = const EntryState();
  var _disposed = false;

  EntryState get current => _state;
  Stream<EntryState> get states => _states.stream;

  /// Fetch and pull commands forwarded from the command line, each once.
  Stream<CliForwardedCommand> get forwardedCommands => _forwarded.stream;

  void _set({
    bool? busy,
    RepositoryFailureCode? failure,
    bool clearFailure = false,
    CloneFailureCode? cloneFailure,
    bool clearCloneFailure = false,
  }) {
    _state = EntryState(
      busy: busy ?? _state.busy,
      failure: clearFailure ? failure : failure ?? _state.failure,
      cloneFailure: clearCloneFailure
          ? cloneFailure
          : cloneFailure ?? _state.cloneFailure,
    );
    if (!_disposed) _states.add(_state);
  }

  /// Runs [operation] unless another entry action runs, keeping its
  /// repository failure.
  Future<void> run(Future<RepositorySessionState?> Function() operation) async {
    if (_state.busy) return;
    _set(busy: true, clearFailure: true);
    try {
      await operation();
    } on RepositorySessionException catch (error) {
      _set(failure: error.failure.code);
    } finally {
      _set(busy: false);
    }
  }

  /// Lets the user choose a repository folder and opens it.
  Future<void> open() => run(_repositories.chooseAndOpen);

  /// Opens the recent repository [identity] on this computer.
  Future<void> openRecent(NativePathIdentity identity) =>
      run(() => _repositories.openRecent(identity));

  /// Asks for a source and a destination and clones it.
  Future<void> clone(EntryInteraction interaction) async {
    final source = await interaction.chooseCloneSource();
    if (source == null || source.isEmpty || !interaction.active) return;
    await _cloning(() => _repositories.chooseAndClone(source: source));
  }

  Future<void> _cloning(Future<Object?> Function() operation) async {
    _set(busy: true, clearCloneFailure: true);
    try {
      await operation();
    } on CloneException catch (error) {
      _set(cloneFailure: error.failure.code);
    } on RepositorySessionException catch (error) {
      _set(failure: error.failure.code);
    } finally {
      _set(busy: false);
    }
  }

  /// Creates a repository on this computer or on a host.
  Future<void> initialize(
    EntryInteraction interaction, {
    bool initiallyBare = false,
  }) async {
    final choice = await interaction.chooseInitialize(
      initiallyBare: initiallyBare,
    );
    if (choice == null || !interaction.active) return;
    final profileId = choice.profileId;
    await run(
      () => profileId == null
          ? _repositories.chooseAndInitialize(bare: choice.bare)
          : interaction.initializeOnHost(profileId, bare: choice.bare),
    );
  }

  /// Retries the failed clone with credentials the user enters.
  Future<void> retryCloneWithCredentials(EntryInteraction interaction) async {
    final input = await interaction.cloneCredentials();
    if (input == null || !interaction.active) return;
    await _cloning(
      () => _repositories.chooseAndRetryCloneWithCredentials(
        username: input.username,
        password: input.secret,
      ),
    );
  }

  /// Shows the clone's host key and records the user's decision.
  Future<void> inspectCloneHostKey(EntryInteraction interaction) async {
    if (_state.busy) return;
    await _cloning(() async {
      final challenge = await _repositories.probeCloneHostKey();
      if (!interaction.active) return null;
      final accept = await interaction.trustHostKey(challenge);
      if (!interaction.active) return null;
      return _repositories.resolveCloneHostKey(
        challenge: challenge,
        accept: accept,
      );
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cli.detach();
    await _sessionStates.cancel();
    await _cloneStates.cancel();
    await _cliCommands.cancel();
    await _states.close();
    await _forwarded.close();
  }
}
