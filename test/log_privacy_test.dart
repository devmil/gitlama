import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/logging/log_privacy.dart';

void main() {
  test('redacts sensitive structured fields', () {
    const event = LogEvent('request_failed', {
      'endpoint': LogField(
        'https://service.example/private?id=42',
        LogSensitivity.diagnostic,
      ),
      'account': LogField(
        'person@example.test',
        LogSensitivity.privateIdentifier,
      ),
      'credential': LogField('secret-value', LogSensitivity.secret),
    });

    final rendered = LogPrivacy.format(event);

    expect(rendered, contains('request_failed'));
    expect(rendered, contains('<redacted-uri>'));
    expect(rendered, contains('<redacted-id>'));
    expect(rendered, contains('<omitted>'));
    expect(rendered, isNot(contains('person@example.test')));
    expect(rendered, isNot(contains('secret-value')));
  });

  test('redacts common secrets and private paths at the sink', () {
    final rendered = LogPrivacy.redact(
      'token=abc123 /Users/example/private.txt '
      'person@example.test 01234567-89ab-cdef-0123-456789abcdef',
    );

    expect(rendered, isNot(contains('abc123')));
    expect(rendered, isNot(contains('/Users/example')));
    expect(rendered, isNot(contains('person@example.test')));
    expect(rendered, isNot(contains('01234567-89ab')));
  });

  test('bounds rendered data', () {
    expect(LogPrivacy.redact('a' * 800).length, lessThan(540));
  });
}
