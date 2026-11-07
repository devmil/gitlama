import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/host_key_dialog.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/clone_attempt.dart';
import 'package:meridian_ui/meridian_ui.dart';

Future<bool? Function()> _open(
  WidgetTester tester,
  HostKeyChallenge challenge,
) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Center(
          child: MeridianButton(
            label: 'Open',
            onPressed: () => unawaited(
              confirmHostKey(
                context,
                challenge,
              ).then((value) => result = value),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => result;
}

HostKeyChallenge _challenge({int port = 22}) => HostKeyChallenge(
  challengeId: BigInt.one,
  host: 'git.example.test',
  port: port,
  algorithm: 'ssh-ed25519',
  fingerprint: 'SHA256:abcdef',
);

void main() {
  testWidgets('shows the server, key type and fingerprint as facts', (
    tester,
  ) async {
    final result = await _open(tester, _challenge());
    final facts = tester.widget<MeridianPropertyList>(
      find.byKey(const ValueKey('host-key-details')),
    );
    expect(
      {for (final fact in facts.properties) fact.label: fact.value},
      {
        'Server': 'git.example.test',
        'Key type': 'ssh-ed25519',
        'Fingerprint': 'SHA256:abcdef',
      },
    );
    expect(facts.properties.every((fact) => fact.monospace), isTrue);

    // It must be answered: the scrim does not dismiss it.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('host-key-details')), findsOne);
    await tester.tap(find.text('Trust and retry'));
    await tester.pumpAndSettle();
    expect(result(), isTrue);
  });

  testWidgets('names a non-default port with the server', (tester) async {
    final result = await _open(tester, _challenge(port: 2222));
    expect(find.text('git.example.test:2222'), findsOne);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(result(), isFalse);
  });
}
