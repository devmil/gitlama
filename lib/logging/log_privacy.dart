/// Sensitivity assigned to a reviewed structured log field.
enum LogSensitivity { public, diagnostic, privateIdentifier, secret }

final class LogField {
  const LogField(this.value, this.sensitivity);

  final Object? value;
  final LogSensitivity sensitivity;
}

final class LogEvent {
  const LogEvent(this.code, [this.fields = const {}]);

  final String code;
  final Map<String, LogField> fields;

  @override
  String toString() => LogPrivacy.format(this);
}

/// Conservative sink-level privacy backstop, not permission to log private data.
final class LogPrivacy {
  LogPrivacy._();

  static final _webUri = RegExp(
    r'''\bhttps?://[^\s"']+''',
    caseSensitive: false,
  );
  static final _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final _absolutePath = RegExp(
    r'''(?<![A-Za-z0-9_])(?:/(?:Users|home|private|var|tmp|data|opt|Applications)/|[A-Za-z]:[\\/])[^\s"']+''',
  );
  static final _authorization = RegExp(
    r'\bauthorization\s*([=:])\s*(?:bearer\s+)?[^\s,;]+',
    caseSensitive: false,
  );
  static final _credential = RegExp(
    r'\b(password|(?:access[_-]?|refresh[_-]?|id[_-]?)?token|cookie|secret|account[_-]?id|user[_-]?id)\s*([=:])\s*([^\s,;]+)',
    caseSensitive: false,
  );
  static final _opaqueId = RegExp(
    r'\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b',
    caseSensitive: false,
  );

  static String format(Object? value) {
    if (value is! LogEvent) return redact(value);
    final fields = <String>[];
    for (final entry in value.fields.entries) {
      final rendered = switch (entry.value.sensitivity) {
        LogSensitivity.public ||
        LogSensitivity.diagnostic => redact(entry.value.value),
        LogSensitivity.privateIdentifier => '<redacted-id>',
        LogSensitivity.secret => '<omitted>',
      };
      fields.add('${redact(entry.key)}=$rendered');
    }
    return fields.isEmpty
        ? redact(value.code)
        : '${redact(value.code)} ${fields.join(' ')}';
  }

  static String redact(Object? value) {
    var result = value?.toString() ?? '';
    result = result.replaceAll(_webUri, '<redacted-uri>');
    result = result.replaceAll(_email, '<redacted-email>');
    result = result.replaceAll(_absolutePath, '<redacted-path>');
    result = result.replaceAllMapped(
      _authorization,
      (match) => 'authorization${match.group(1)}<redacted>',
    );
    result = result.replaceAllMapped(
      _credential,
      (match) => '${match.group(1)}${match.group(2)}<redacted>',
    );
    result = result.replaceAll(_opaqueId, '<redacted-id>');
    if (result.length > 512) {
      return '${result.substring(0, 512)}…<truncated>';
    }
    return result;
  }
}
