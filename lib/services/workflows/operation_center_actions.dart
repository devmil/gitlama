import 'dart:async';

import '../../models/operation_center.dart';
import '../operation_center_service.dart';
import '../repository_session_service.dart';
import 'transfer_workflows.dart';

/// Routes the operation center's Cancel, Retry and Dismiss to whatever runs
/// the entry: the clone attempt, a transfer this window started, or the
/// operation center itself. The welcome screen and the workspace share it.
final class OperationCenterActions {
  OperationCenterActions(
    this._repositories,
    this._operationCenter, [
    this._transfers,
  ]);

  final RepositorySessionService _repositories;
  final OperationCenterService _operationCenter;
  final TransferWorkflowService? _transfers;

  bool _isClone(OperationCenterEntry entry) =>
      entry.cloneAttemptId != null &&
      entry.cloneAttemptId == _repositories.currentClone?.attemptId;

  /// Whether Cancel can stop [entry].
  bool canCancel(OperationCenterEntry entry) =>
      entry.canCancel || _transfers?.transferFor(entry) != null;

  void cancel(OperationCenterEntry entry) {
    if (_isClone(entry)) {
      unawaited(_repositories.cancelClone());
    } else if (_transfers?.transferFor(entry) case final preview?) {
      unawaited(_repositories.transfers.cancel(preview));
    }
  }

  void retry(OperationCenterEntry entry) {
    if (_isClone(entry)) unawaited(_repositories.retryClone());
  }

  void dismiss(OperationCenterEntry entry) {
    if (_isClone(entry)) {
      unawaited(_repositories.dismissClone());
    } else {
      unawaited(_operationCenter.dismiss(entry));
    }
  }

  void dismissAll() => unawaited(_operationCenter.dismissAll());

  /// The newest entry Retry (or Cancel) applies to, if any.
  OperationCenterEntry? latest({required bool retry}) {
    for (final entry in _operationCenter.current.entries.reversed) {
      if (retry ? entry.canRetry : canCancel(entry)) return entry;
    }
    return null;
  }
}
