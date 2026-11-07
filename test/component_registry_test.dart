import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/di/component_registry.dart';

abstract interface class _Repository {}

final class _RepositoryImpl implements _Repository {}

final class _Service {
  const _Service(this.repository);

  final _Repository repository;
}

final class _CycleA {
  const _CycleA();
}

final class _CycleB {
  const _CycleB();
}

final class _FirstRoot {
  const _FirstRoot();
}

final class _FailingRoot {
  const _FailingRoot();
}

final class _Dependency {
  const _Dependency();
}

void main() {
  test('constructs a dependency graph lazily and once', () {
    var repositoryCreations = 0;
    final registry = ComponentRegistry()
      ..register<_Repository>((_) {
        repositoryCreations += 1;
        return _RepositoryImpl();
      })
      ..register<_Service>(
        (resolver) => _Service(resolver.resolve<_Repository>()),
      );

    expect(repositoryCreations, 0);
    final service = registry.resolve<_Service>();
    expect(service.repository, isA<_RepositoryImpl>());
    expect(registry.resolve<_Service>(), same(service));
    expect(repositoryCreations, 1);
  });

  test('rejects missing, duplicate, and cyclic dependencies', () {
    final registry = ComponentRegistry()
      ..register<_Repository>((_) => _RepositoryImpl())
      ..register<_CycleA>((resolver) {
        resolver.resolve<_CycleB>();
        return const _CycleA();
      })
      ..register<_CycleB>((resolver) {
        resolver.resolve<_CycleA>();
        return const _CycleB();
      });

    expect(
      () => registry.register<_Repository>((_) => _RepositoryImpl()),
      throwsStateError,
    );
    expect(() => registry.resolve<_Service>(), throwsStateError);
    expect(
      () => registry.resolve<_CycleA>(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('_CycleA -> _CycleB -> _CycleA'),
        ),
      ),
    );
  });

  test('disposes in reverse actual construction order', () async {
    final events = <String>[];
    final registry = ComponentRegistry()
      ..register<_Service>(
        (resolver) => _Service(resolver.resolve<_Repository>()),
        dispose: (_) => events.add('service'),
      )
      ..register<_Repository>(
        (_) => _RepositoryImpl(),
        dispose: (_) => events.add('repository'),
      );

    registry.resolve<_Service>();
    await registry.dispose();
    await registry.dispose();

    expect(events, ['service', 'repository']);
  });

  test('initialization failure unwinds every constructed dependency', () async {
    final events = <String>[];
    final registry = ComponentRegistry()
      ..register<_FirstRoot>(
        (_) => const _FirstRoot(),
        initialize: (_) => events.add('initialize first'),
        dispose: (_) => events.add('dispose first'),
      )
      ..register<_FailingRoot>(
        (resolver) {
          resolver.resolve<_Dependency>();
          return const _FailingRoot();
        },
        initialize: (_) => throw StateError('injected'),
        dispose: (_) => events.add('dispose failing'),
      )
      ..register<_Dependency>(
        (_) => const _Dependency(),
        dispose: (_) => events.add('dispose dependency'),
      );

    await expectLater(
      registry.initializeAll(),
      throwsA(
        isA<ComponentInitializationException>().having(
          (failure) => failure.componentName,
          'componentName',
          '_FailingRoot',
        ),
      ),
    );

    expect(events, [
      'initialize first',
      'dispose failing',
      'dispose dependency',
      'dispose first',
    ]);
    await registry.dispose();
    expect(events.length, 4);
  });

  test(
    'disposal continues after failure and reports the first failure',
    () async {
      final events = <String>[];
      final registry = ComponentRegistry()
        ..register<_FirstRoot>(
          (_) => const _FirstRoot(),
          dispose: (_) {
            events.add('first');
            throw StateError('first failure');
          },
        )
        ..register<_Dependency>(
          (_) => const _Dependency(),
          dispose: (_) {
            events.add('dependency');
            throw ArgumentError('dependency failure');
          },
        );
      registry.resolve<_FirstRoot>();
      registry.resolve<_Dependency>();

      await expectLater(registry.dispose(), throwsArgumentError);
      expect(events, ['dependency', 'first']);
    },
  );
}
