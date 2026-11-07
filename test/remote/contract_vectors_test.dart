import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';

/// The helper's tests read the same vectors (rust-core/remote-helper/tests/
/// contract.rs), so both sides agree on every wire name and limit.
void main() {
  final vectors =
      jsonDecode(
            File(
              'rust-core/remote-helper/fixtures/contract_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  List<String> strings(Object? value) => (value! as List).cast<String>();
  Map<String, Object?> map(Object? value) => value! as Map<String, Object?>;

  RemoteCapability? familyCapability(String method) {
    final suffix = method.startsWith('preview')
        ? method.substring('preview'.length)
        : method.startsWith('execute')
        ? method.substring('execute'.length)
        : null;
    if (suffix == null || suffix.isEmpty) return null;
    for (final family in RemoteOperationFamily.values) {
      final name = family.name;
      if ('${name[0].toUpperCase()}${name.substring(1)}' == suffix) {
        return family.capability;
      }
    }
    return null;
  }

  test('write methods need the capability of their family', () {
    for (final pair
        in (vectors['methodCapabilities']! as List).cast<List<Object?>>()) {
      expect(
        familyCapability(pair[0] as String)?.name,
        pair[1],
        reason: '$pair',
      );
    }
    for (final method in strings(vectors['notWriteMethods'])) {
      expect(familyCapability(method), isNull, reason: method);
    }
  });

  test('capabilities, outcomes and error codes have the helper names', () {
    final capabilities = map(vectors['capabilities']);
    expect(
      RemoteCapability.values.map((value) => value.name),
      strings(capabilities['accept']),
    );
    for (final name in strings(capabilities['reject'])) {
      expect(
        RemoteCapability.values.map((value) => value.name),
        isNot(contains(name)),
      );
    }
    expect(
      remoteWriteCapabilities.map((value) => value.name),
      strings(vectors['writeCapabilities']),
    );
    expect(
      remoteReceiptWriteCapabilities.map((value) => value.name),
      strings(vectors['receiptWriteCapabilities']),
    );
    final outcomes = map(vectors['outcomes']);
    for (final name in strings(outcomes['definite'])) {
      expect(RemoteOperationOutcome.values.byName(name).definite, isTrue);
    }
    for (final name in strings(outcomes['open'])) {
      expect(RemoteOperationOutcome.values.byName(name).definite, isFalse);
    }
    final errors = map(vectors['errors']);
    // `disconnected` is the client's own code for a closed channel.
    expect(
      RemoteErrorCode.values
          .where((code) => code != RemoteErrorCode.disconnected)
          .map((code) => code.name),
      strings(errors['accept']),
    );
  });

  test('limits are the helper limits', () {
    final limits = map(vectors['limits']);
    expect(limits, {
      'stagePaths': ContractLimits.stagePaths,
      'stageRows': ContractLimits.stageRows,
      'patchBytes': ContractLimits.patchBytes,
      'frameBytes': ContractLimits.frameBytes,
      'transactionBytes': ContractLimits.transactionBytes,
      'pathBytes': ContractLimits.pathBytes,
      'summaryCharacters': ContractLimits.summaryCharacters,
      'pageRows': ContractLimits.pageRows,
    });
  });
}
