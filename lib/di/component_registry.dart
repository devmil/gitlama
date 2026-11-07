import 'dart:async';

import 'component_creation_info.dart';

abstract interface class ComponentResolver {
  T resolve<T extends Object>();
}

/// Instance-scoped owner of component construction and lifecycle.
final class ComponentRegistry implements ComponentResolver {
  final Map<Type, ComponentLifecycle> _components = {};
  final List<Type> _registrationOrder = [];
  final List<Type> _constructionOrder = [];
  final List<Type> _resolutionPath = [];
  Future<void>? _initialization;
  Future<void>? _disposal;
  bool _disposed = false;

  void register<T extends Object>(
    T Function(ComponentResolver resolver) create, {
    String? name,
    FutureOr<void> Function(T instance)? initialize,
    FutureOr<void> Function(T instance)? dispose,
  }) {
    if (_initialization != null || _disposal != null || _disposed) {
      throw StateError('The registry is sealed.');
    }
    if (_components.containsKey(T)) {
      throw StateError('A component is already registered for $T.');
    }
    _components[T] = ComponentCreationInfo<T>(
      () => _create<T>(create),
      name: name,
      initialize: initialize,
      dispose: dispose,
    );
    _registrationOrder.add(T);
  }

  @override
  T resolve<T extends Object>() {
    if (_disposed) {
      throw StateError('Cannot resolve $T after disposal.');
    }
    final component = _components[T];
    if (component == null) {
      throw StateError('No component is registered for $T.');
    }
    return (component as ComponentCreationInfo<T>).instance;
  }

  T _create<T extends Object>(T Function(ComponentResolver resolver) create) {
    final cycleStart = _resolutionPath.indexOf(T);
    if (cycleStart >= 0) {
      final cycle = [..._resolutionPath.sublist(cycleStart), T].join(' -> ');
      throw StateError('Cyclic component dependency: $cycle.');
    }
    _resolutionPath.add(T);
    try {
      final instance = create(this);
      _constructionOrder.add(T);
      return instance;
    } finally {
      _resolutionPath.removeLast();
    }
  }

  Future<void> initializeAll() {
    if (_disposed) throw StateError('Cannot initialize after disposal.');
    return _initialization ??= _initializeAll();
  }

  Future<void> _initializeAll() async {
    for (final type in _registrationOrder) {
      final component = _components[type]!;
      if (!component.hasInitializer) continue;
      try {
        await component.initializeInstance();
      } on Object catch (cause) {
        await _disposeConstructed(suppressFailures: true);
        throw ComponentInitializationException(
          componentName: component.componentName,
          cause: cause,
        );
      }
    }
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await _disposeConstructed(suppressFailures: false);
  }

  Future<void> _disposeConstructed({required bool suppressFailures}) async {
    Object? firstFailure;
    StackTrace? firstStackTrace;
    for (final type in _constructionOrder.reversed) {
      try {
        await _components[type]!.disposeInstance();
      } on Object catch (failure, stackTrace) {
        firstFailure ??= failure;
        firstStackTrace ??= stackTrace;
      }
    }
    if (!suppressFailures && firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }
  }
}

final class ComponentInitializationException implements Exception {
  const ComponentInitializationException({
    required this.componentName,
    required this.cause,
  });

  final String componentName;
  final Object cause;

  @override
  String toString() => 'ComponentInitializationException($componentName)';
}
