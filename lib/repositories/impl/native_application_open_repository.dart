import 'dart:io';

import 'package:flutter/services.dart';

import '../application_open_repository.dart';

final class NativeApplicationOpenRepository
    implements ApplicationOpenRepository {
  NativeApplicationOpenRepository({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('gitlama/application_open'),
      _supported = supported ?? Platform.isMacOS;

  final MethodChannel _channel;
  final bool _supported;

  @override
  Future<List<String>> takePaths() async {
    if (!_supported) return const [];
    try {
      return await _channel.invokeListMethod<String>('takePaths') ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
