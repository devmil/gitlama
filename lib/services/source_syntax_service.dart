import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../models/diff_syntax.dart';
import '../models/remote_contract.g.dart';
import '../models/source_syntax.dart';
import '../repositories/source_syntax_repository.dart';

/// Completes when the next frame has been drawn.
typedef SourceSyntaxFrame = Future<void> Function();

/// Owns the syntax colours of texts a window holds, such as a conflicted
/// file's sides and its unsaved merge result: their requests, the overlays
/// they publish and when they may run.
///
/// Colours never hold up text. A view asks only after its text was shown
/// and the user paused for [idle]; input pauses it again. At most
/// [concurrentRequests] requests run at once across views, one per view;
/// replies are published at most [linesPerFrame] lines per frame. Any
/// failure leaves text plain.
final class SourceSyntaxService {
  SourceSyntaxService(
    this._repository, {
    SourceSyntaxFrame? nextFrame,
    this.idle = const Duration(milliseconds: 150),
    this.concurrentRequests = 2,
    this.linesPerFrame = 32,
  }) : _nextFrame =
           nextFrame ??
           (() => Future<void>.delayed(const Duration(milliseconds: 16)));

  final SourceSyntaxRepository _repository;
  final SourceSyntaxFrame _nextFrame;

  /// Quiet time after input or a new text before a view requests colours.
  final Duration idle;
  final int concurrentRequests;
  final int linesPerFrame;

  final Set<SourceSyntaxView> _views = {};
  final Queue<SourceSyntaxView> _waiting = Queue();
  int _running = 0;
  BigInt _nextId = BigInt.one;
  bool _disposed = false;

  /// A view of [text], coloured by the grammar [path] selects. Dispose it
  /// when the text is no longer shown.
  SourceSyntaxView view({required List<int> path, required String text}) {
    final view = SourceSyntaxView._(this, _id(), List.unmodifiable(path), text);
    if (_disposed) {
      view._retired = true;
    } else {
      _views.add(view);
    }
    return view;
  }

  /// Retires every view.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final view in _views.toList()) {
      view.dispose();
    }
    _waiting.clear();
  }

  BigInt _id() {
    final id = _nextId;
    _nextId += BigInt.one;
    return id;
  }

  /// Runs [view]'s next request now or when a slot frees up.
  void _ask(SourceSyntaxView view) {
    if (_disposed || view._retired) return;
    if (_running < concurrentRequests) {
      _running += 1;
      unawaited(view._run().whenComplete(_release));
    } else if (!_waiting.contains(view)) {
      _waiting.add(view);
    }
  }

  void _release() {
    _running -= 1;
    while (_waiting.isNotEmpty && _running < concurrentRequests) {
      final view = _waiting.removeFirst();
      if (view._retired) continue;
      _running += 1;
      unawaited(view._run().whenComplete(_release));
    }
  }

  void _forget(SourceSyntaxView view) {
    _views.remove(view);
    _waiting.remove(view);
  }
}

/// The syntax colours of one held text, as an overlay keyed by one-based
/// line. Widgets read [runsOf] and listen for changes; they never start
/// work from build.
final class SourceSyntaxView {
  SourceSyntaxView._(this._service, this._id, this.path, this._text);

  /// Chunks of colours one view keeps; the ones farthest from the visible
  /// lines go first.
  static const retainedChunks = 16;
  static const _chunk = ContractLimits.textSyntaxPageLines;

  final SourceSyntaxService _service;
  final BigInt _id;
  final List<int> path;

  String _text;
  int _generation = 0;
  Uint8List? _bytes;
  List<int>? _starts;

  final Map<int, List<DiffSyntaxRun>> _overlay = {};

  /// Chunk indexes whose outcome is settled, coloured or plain.
  final Set<int> _settled = {};

  /// Chunks that came back deferred once and may be asked once more.
  final Set<int> _deferredOnce = {};

  /// The whole text stays plain until it changes.
  bool _plain = false;
  final Queue<(int, int, List<DiffSyntaxRun>)> _unpublished = Queue();

  int _firstVisible = 1;
  int _lastVisible = _chunk;
  Timer? _idleTimer;
  bool _interacting = false;
  bool _requesting = false;
  bool _publishing = false;
  bool _retired = false;
  BigInt? _inFlight;

  final List<void Function()> _listeners = [];

  /// The text the colours describe.
  String get text => _text;

  /// Calls [listener] whenever lines gain or lose colours.
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Paintable colours of the one-based [line], or null for plain text.
  List<DiffSyntaxRun>? runsOf(int line) => _overlay[line];

  /// Whether any line has colours.
  bool get hasColours => _overlay.isNotEmpty;

  /// The lines that have colours, in order.
  List<int> get colouredLines => _overlay.keys.toList()..sort();

  /// The UTF-16 offset of the text where the one-based [line] starts.
  int lineStart(int line) => _lineStarts()[line - 1];

  /// Lines of the text, counting a last line without a terminator.
  int get lineCount {
    final starts = _lineStarts();
    if (_text.isEmpty) return 0;
    return _text.endsWith('\n') ? starts.length - 1 : starts.length;
  }

  /// The one-based line holding the UTF-16 [offset] of the text.
  int lineAt(int offset) {
    final starts = _lineStarts();
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low + 1;
  }

  /// UTF-16 offset of each line's start.
  List<int> _lineStarts() => _starts ??= [
    0,
    for (var index = 0; index < _text.length; index += 1)
      if (_text.codeUnitAt(index) == 0x0A) index + 1,
  ];

  /// The one-based [line] without its terminator.
  String _line(int line) {
    final starts = _lineStarts();
    final start = starts[line - 1];
    var end = line < starts.length ? starts[line] - 1 : _text.length;
    if (end > start && _text.codeUnitAt(end - 1) == 0x0D) end -= 1;
    return _text.substring(start, end);
  }

  /// Replaces the text, as an edit does. Colours of the unchanged lines
  /// before and after the edit stay until the new text has its own.
  void update(String text) {
    if (_retired || text == _text) return;
    final old = _text;
    var prefix = 0;
    final shorter = old.length < text.length ? old.length : text.length;
    while (prefix < shorter &&
        old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            text.codeUnitAt(text.length - 1 - suffix)) {
      suffix += 1;
    }
    // Whole lines before the first and after the last changed character.
    final before = '\n'.allMatches(old.substring(0, prefix)).length;
    final after = '\n'.allMatches(old.substring(old.length - suffix)).length;
    final oldLines = '\n'.allMatches(old).length + 1;
    final newLines = '\n'.allMatches(text).length + 1;
    final kept = <int, List<DiffSyntaxRun>>{};
    for (final MapEntry(key: line, value: runs) in _overlay.entries) {
      if (line <= before) {
        kept[line] = runs;
      } else if (line > oldLines - after) {
        kept[line + newLines - oldLines] = runs;
      }
    }
    _overlay
      ..clear()
      ..addAll(kept);
    _text = text;
    _generation += 1;
    _bytes = null;
    _starts = null;
    _settled.clear();
    _deferredOnce.clear();
    _unpublished.clear();
    _plain = false;
    _cancelInFlight();
    _restartIdle();
  }

  /// The one-based lines on screen, reported after scrolling settles.
  void setVisible(int first, int last) {
    if (_retired) return;
    final start = first < 1 ? 1 : first;
    final end = last < start ? start : last;
    _firstVisible = start;
    _lastVisible = end;
    _restartIdle();
  }

  /// Scrolling, dragging or typing in progress: pauses both new requests
  /// and publication until it ends.
  void setInteracting(bool interacting) {
    if (_retired || interacting == _interacting) return;
    _interacting = interacting;
    if (interacting) {
      _idleTimer?.cancel();
    } else {
      _restartIdle();
      unawaited(_publish());
    }
  }

  /// Any user input: postpones requests by the service's idle time.
  void noteActivity() {
    if (_retired) return;
    _restartIdle();
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    if (_interacting) return;
    _idleTimer = Timer(_service.idle, () {
      if (!_retired && !_interacting && !_requesting && _nextChunk() != null) {
        _requesting = true;
        _service._ask(this);
      }
    });
  }

  /// The next chunk to ask for: a visible one first, then the one below
  /// the visible lines.
  int? _nextChunk() {
    if (_plain) return null;
    final count = lineCount;
    final first = (_firstVisible - 1) ~/ _chunk;
    final last = (_lastVisible - 1) ~/ _chunk + 1;
    for (var chunk = first; chunk <= last; chunk += 1) {
      if (chunk * _chunk >= count) break;
      if (!_settled.contains(chunk)) return chunk;
    }
    return null;
  }

  Future<void> _run() async {
    try {
      final chunk = _nextChunk();
      if (_retired || chunk == null) return;
      await _request(chunk);
    } finally {
      _requesting = false;
      // More visible chunks wait for the next idle moment.
      if (!_retired && !_interacting && _nextChunk() != null) _restartIdle();
    }
  }

  Future<void> _request(int chunk) async {
    final generation = _generation;
    final firstLine = chunk * _chunk + 1;
    final requestId = _service._id();
    _inFlight = requestId;
    final SourceSyntaxPage reply;
    try {
      reply = await _service._repository.sourceSyntaxPage(
        viewId: _id,
        syntaxRequestId: requestId,
        path: path,
        source: _bytes ??= utf8.encode(_text),
        firstLine: firstLine,
        maximumLines: _chunk,
      );
    } on Object {
      // A canceled request belongs to text that changed; anything else
      // leaves this chunk plain.
      if (!_retired && generation == _generation) _settled.add(chunk);
      return;
    } finally {
      if (_inFlight == requestId) _inFlight = null;
    }
    if (_retired || generation != _generation) return;
    if (reply.viewId != _id ||
        reply.syntaxRequestId != requestId ||
        reply.firstLine != firstLine) {
      _settled.add(chunk);
      return;
    }
    if (reply.state != DiffSyntaxSideState.ready) {
      if (reply.state == DiffSyntaxSideState.deferred &&
          _deferredOnce.add(chunk)) {
        return;
      }
      if (reply.state == DiffSyntaxSideState.deferred) {
        _settled.add(chunk);
      } else {
        _plain = true;
      }
      return;
    }
    final count = lineCount;
    final expected = (count - firstLine + 1).clamp(0, _chunk);
    if (reply.lines.length != expected) {
      _settled.add(chunk);
      return;
    }
    var anyDeferred = false;
    for (var index = 0; index < reply.lines.length; index += 1) {
      final line = reply.lines[index];
      final number = firstLine + index;
      if (line.state == DiffSyntaxSideState.deferred) anyDeferred = true;
      if (line.state != DiffSyntaxSideState.ready || line.runs.isEmpty) {
        continue;
      }
      if (!_valid(line.runs, _line(number).length)) continue;
      _unpublished.add((generation, number, line.runs));
    }
    unawaited(_publish());
    if (anyDeferred && _deferredOnce.add(chunk)) return;
    _settled.add(chunk);
    _evict();
  }

  static bool _valid(List<DiffSyntaxRun> runs, int length) {
    var cursor = 0;
    for (final run in runs) {
      if (run.start < cursor || run.end <= run.start || run.end > length) {
        return false;
      }
      cursor = run.end;
    }
    return true;
  }

  /// Publishes lines a few per frame, never while the user scrolls or
  /// selects.
  Future<void> _publish() async {
    if (_publishing) return;
    _publishing = true;
    try {
      while (_unpublished.isNotEmpty && !_retired && !_interacting) {
        await _service._nextFrame();
        if (_retired || _interacting) return;
        var published = false;
        for (
          var count = 0;
          count < _service.linesPerFrame && _unpublished.isNotEmpty;
          count += 1
        ) {
          final (generation, line, runs) = _unpublished.removeFirst();
          if (generation != _generation) continue;
          _overlay[line] = runs;
          published = true;
        }
        if (published) _notify();
      }
    } finally {
      _publishing = false;
    }
  }

  /// Drops the chunks farthest from the visible lines beyond
  /// [retainedChunks]; they settle again only if asked for again.
  void _evict() {
    if (_settled.length <= retainedChunks) return;
    final center = ((_firstVisible + _lastVisible) ~/ 2 - 1) ~/ _chunk;
    final chunks = _settled.toList()
      ..sort((a, b) => (b - center).abs().compareTo((a - center).abs()));
    for (final chunk in chunks.take(_settled.length - retainedChunks)) {
      _settled.remove(chunk);
      _deferredOnce.remove(chunk);
      final first = chunk * _chunk + 1;
      for (var line = first; line < first + _chunk; line += 1) {
        _overlay.remove(line);
      }
    }
  }

  void _cancelInFlight() {
    final inFlight = _inFlight;
    if (inFlight == null) return;
    _inFlight = null;
    unawaited(
      _service._repository
          .cancelSourceSyntax(viewId: _id, syntaxRequestId: inFlight)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// Stops all work of this view and forgets its colours.
  void dispose() {
    if (_retired) return;
    _retired = true;
    _idleTimer?.cancel();
    _cancelInFlight();
    _service._forget(this);
    _overlay.clear();
    _unpublished.clear();
    _listeners.clear();
  }
}
