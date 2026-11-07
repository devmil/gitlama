import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';

import '../../models/repository_drop.dart';
import '../repository_drop_repository.dart';

abstract interface class RepositoryDropEventSource {
  void initialize();
  void addListener(RawDropListener listener);
  void removeListener(RawDropListener listener);
}

final class DesktopRepositoryDropEventSource
    implements RepositoryDropEventSource {
  const DesktopRepositoryDropEventSource();

  @override
  void initialize() => DesktopDrop.instance.init();

  @override
  void addListener(RawDropListener listener) =>
      DesktopDrop.instance.addRawDropEventListener(listener);

  @override
  void removeListener(RawDropListener listener) =>
      DesktopDrop.instance.removeRawDropEventListener(listener);
}

typedef RepositoryDropPathType =
    Future<FileSystemEntityType> Function(String path);

Future<FileSystemEntityType> _nativePathType(String path) =>
    FileSystemEntity.type(path, followLinks: true);

final class NativeRepositoryDropRepository implements RepositoryDropRepository {
  NativeRepositoryDropRepository({
    RepositoryDropEventSource? source,
    RepositoryDropPathType? pathType,
  }) : _source = source ?? const DesktopRepositoryDropEventSource(),
       _pathType = pathType ?? _nativePathType;

  static const maximumItemsPerDrop = 32;

  final RepositoryDropEventSource _source;
  final RepositoryDropPathType _pathType;
  final StreamController<RepositoryDropEvent> _events =
      StreamController<RepositoryDropEvent>.broadcast(sync: true);
  Future<void> _classificationQueue = Future.value();
  var _initialized = false;

  @override
  Stream<RepositoryDropEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _source.initialize();
    _source.addListener(_onDropEvent);
  }

  void _onDropEvent(DropEvent event) {
    if (_events.isClosed) return;
    switch (event) {
      case DropEnterEvent():
        _events.add(const RepositoryDropEvent.entered());
      case DropExitEvent():
        _events.add(const RepositoryDropEvent.exited());
      case DropDoneEvent():
        _events.add(const RepositoryDropEvent.exited());
        _classificationQueue = _classificationQueue.then(
          (_) => _classify(event.files),
        );
      case DropUpdateEvent():
        break;
    }
  }

  Future<void> _classify(List<DropItem> items) async {
    final bounded = items.take(maximumItemsPerDrop).toList(growable: false);
    final directories = <String>[];
    var rejected = items.length - bounded.length;
    for (final item in bounded) {
      final path = item.path;
      if (path.isEmpty) {
        rejected += 1;
        continue;
      }
      FileSystemEntityType type;
      try {
        type = await _pathType(path);
      } on Object {
        rejected += 1;
        continue;
      }
      if (type == FileSystemEntityType.directory) {
        directories.add(path);
      } else {
        rejected += 1;
      }
    }
    if (!_events.isClosed) {
      _events.add(
        RepositoryDropEvent.dropped(
          directories: List.unmodifiable(directories),
          rejectedItems: rejected,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    _source.removeListener(_onDropEvent);
    await _classificationQueue;
    await _events.close();
  }
}
