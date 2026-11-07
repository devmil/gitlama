import 'dart:async';

abstract interface class ComponentLifecycle {
  String get componentName;
  bool get hasInitializer;
  Future<void> initializeInstance();
  Future<void> disposeInstance();
}

/// Lazy component factory with shared initialization and disposal work.
final class ComponentCreationInfo<T> implements ComponentLifecycle {
  ComponentCreationInfo(
    this._create, {
    String? name,
    this.initialize,
    this.dispose,
  }) : componentName = name ?? T.toString();

  final T Function() _create;
  final FutureOr<void> Function(T instance)? initialize;
  final FutureOr<void> Function(T instance)? dispose;
  @override
  final String componentName;
  T? _instance;
  Future<void>? _initialization;
  Future<void>? _disposal;

  @override
  bool get hasInitializer => initialize != null;

  T get instance => _instance ??= _create();

  @override
  Future<void> initializeInstance() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await initialize?.call(instance);
  }

  @override
  Future<void> disposeInstance() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    final value = _instance;
    if (value != null) await dispose?.call(value);
  }
}
