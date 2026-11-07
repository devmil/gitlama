import '../../models/inspector.dart';

/// A browser-like stack of inspector locations.
final class InspectorNavigation {
  InspectorNavigation({this.capacity = 100});

  final int capacity;
  final List<InspectorLocation> _entries = [];
  int _index = -1;

  InspectorLocation? get current =>
      _index < 0 || _index >= _entries.length ? null : _entries[_index];
  int get index => _index;
  int get length => _entries.length;
  bool get canBack => _index > 0;
  bool get canForward => _index + 1 < _entries.length;

  /// Earlier locations, newest first.
  List<InspectorLocation> backEntries([int limit = 15]) => [
    for (var index = _index - 1; index >= 0 && _index - index <= limit; index--)
      _entries[index],
  ];

  /// Later locations, nearest first.
  List<InspectorLocation> forwardEntries([int limit = 15]) => [
    for (
      var index = _index + 1;
      index < _entries.length && index - _index <= limit;
      index++
    )
      _entries[index],
  ];

  /// Adds [location] after the current entry, dropping the forward entries
  /// and, beyond [capacity], the oldest entry.
  void push(InspectorLocation location) {
    if (_index + 1 < _entries.length) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(location);
    if (_entries.length > capacity) _entries.removeAt(0);
    _index = _entries.length - 1;
  }

  /// Replaces the current entry, or pushes the first one.
  void replace(InspectorLocation location) {
    if (_index < 0) {
      push(location);
      return;
    }
    _entries[_index] = location;
  }

  InspectorLocation? back() {
    if (!canBack) return null;
    _index -= 1;
    return current;
  }

  InspectorLocation? forward() {
    if (!canForward) return null;
    _index += 1;
    return current;
  }

  /// Moves to [delta] entries from the current one: negative is back.
  InspectorLocation? jump(int delta) {
    final target = _index + delta;
    if (delta == 0 || target < 0 || target >= _entries.length) return null;
    _index = target;
    return current;
  }

  void clear() {
    _entries.clear();
    _index = -1;
  }
}
