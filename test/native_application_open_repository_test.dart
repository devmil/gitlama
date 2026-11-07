import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/native_application_open_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gitlama/application_open');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('takes exact native paths using the main-engine channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takePaths');
      expect(call.arguments, isNull);
      return ['/work/a repository', '/work/日本語'];
    });
    final repository = NativeApplicationOpenRepository(
      channel: channel,
      supported: true,
    );
    expect(await repository.takePaths(), ['/work/a repository', '/work/日本語']);
  });

  test('other platforms do not invoke the macOS boundary', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('unexpected native call'),
    );
    expect(
      await NativeApplicationOpenRepository(supported: false).takePaths(),
      isEmpty,
    );
  });

  test('unavailable native boundary leaves CLI forwarding usable', () async {
    final repository = NativeApplicationOpenRepository(
      channel: channel,
      supported: true,
    );
    expect(await repository.takePaths(), isEmpty);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'application_open_unavailable');
    });
    expect(await repository.takePaths(), isEmpty);
  });
}
