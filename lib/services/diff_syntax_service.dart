import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import '../models/diff.dart';
import '../models/diff_syntax.dart';
import '../models/remote_contract.g.dart';
import '../models/repository_state.dart';
import '../repositories/diff_syntax_repository.dart';

/// Converts core byte spans to paintable UTF-16 runs. Production runs it on
/// a separate isolate; tests may convert synchronously.
typedef DiffSyntaxConverter =
    Future<List<DiffRowSyntax?>> Function(List<DiffSyntaxConversion> rows);

/// Completes when the next frame has been drawn.
typedef DiffSyntaxFrame = Future<void> Function();

/// One row's text and spans to convert.
final class DiffSyntaxConversion {
  const DiffSyntaxConversion(this.text, this.result);

  final List<int> text;
  final DiffSyntaxRowResult result;
}

/// Converts on a short-lived isolate, away from the UI isolate.
Future<List<DiffRowSyntax?>> convertDiffSyntaxOnIsolate(
  List<DiffSyntaxConversion> rows,
) => Isolate.run(() => convertDiffSyntax(rows));

/// The paintable colours of [rows]: byte spans become UTF-16 runs in one
/// forward scan of each row's UTF-8 text. A side whose spans are malformed
/// (unordered, empty, outside the text, inside a character) or whose text
/// is not valid UTF-8 stays plain; the other side is unaffected.
List<DiffRowSyntax?> convertDiffSyntax(List<DiffSyntaxConversion> rows) => [
  for (final row in rows) _convertRow(row),
];

DiffRowSyntax? _convertRow(DiffSyntaxConversion row) {
  final result = row.result;
  final old = result.oldState == DiffSyntaxSideState.ready
      ? _runs(row.text, result.oldSpans)
      : null;
  final current = result.newState == DiffSyntaxSideState.ready
      ? _runs(row.text, result.newSpans)
      : null;
  if (old == null && current == null) return null;
  return DiffRowSyntax(old: old, current: current);
}

List<DiffSyntaxRun>? _runs(List<int> text, List<DiffSyntaxByteSpan> spans) {
  if (spans.isEmpty) return const [];
  // Boundaries in byte order; every span must start where the previous
  // ended or later.
  var previous = 0;
  for (final span in spans) {
    if (span.start < previous ||
        span.end <= span.start ||
        span.end > text.length) {
      return null;
    }
    previous = span.end;
  }
  final runs = <DiffSyntaxRun>[];
  var byte = 0;
  var unit = 0;
  var spanIndex = 0;
  var start = -1;
  while (true) {
    // Record a boundary that falls on the current character start.
    while (spanIndex < spans.length) {
      final span = spans[spanIndex];
      if (start < 0) {
        if (span.start == byte) {
          start = unit;
          continue;
        }
        if (span.start < byte) return null;
        break;
      }
      if (span.end == byte) {
        if (span.kind != DiffSyntaxKind.plain) {
          runs.add(DiffSyntaxRun(start, unit, span.kind));
        }
        start = -1;
        spanIndex += 1;
        continue;
      }
      if (span.end < byte) return null;
      break;
    }
    if (byte >= text.length) break;
    final lead = text[byte];
    final (length, units) = lead < 0x80
        ? (1, 1)
        : lead >= 0xC2 && lead <= 0xDF
        ? (2, 1)
        : lead >= 0xE0 && lead <= 0xEF
        ? (3, 1)
        : lead >= 0xF0 && lead <= 0xF4
        ? (4, 2)
        : (0, 0);
    if (length == 0 || byte + length > text.length) return null;
    for (var next = byte + 1; next < byte + length; next += 1) {
      if (text[next] & 0xC0 != 0x80) return null;
    }
    byte += length;
    unit += units;
  }
  return spanIndex == spans.length ? runs : null;
}

/// Owns the syntax colours of every diff view in one window: their
/// requests, the overlays they publish and when they may run.
///
/// Colours never hold up text. A view admits work only after its rows were
/// published and the user paused for [idle]; input pauses it again. At most
/// [concurrentRequests] requests run at once across views, one per view;
/// replies are converted away from the UI isolate and published at most
/// [rowsPerFrame] rows per frame. Any failure leaves text plain.
final class DiffSyntaxService {
  DiffSyntaxService(
    this._repository, {
    this._convert = convertDiffSyntaxOnIsolate,
    DiffSyntaxFrame? nextFrame,
    this.idle = const Duration(milliseconds: 150),
    this.concurrentRequests = 2,
    this.rowsPerFrame = 4,
  }) : _nextFrame =
           nextFrame ??
           (() => Future<void>.delayed(const Duration(milliseconds: 16)));

  final DiffSyntaxRepository _repository;
  final DiffSyntaxConverter _convert;
  final DiffSyntaxFrame _nextFrame;

  /// Quiet time after input or new rows before a view requests colours.
  final Duration idle;
  final int concurrentRequests;
  final int rowsPerFrame;

  final Set<DiffSyntaxView> _views = {};
  final Queue<DiffSyntaxView> _waiting = Queue();
  int _running = 0;
  BigInt _nextRequest = BigInt.one;
  bool _disposed = false;

  /// A view of the accepted [origin] projection [diffRequestId] of
  /// [identity]. Dispose it when the projection is replaced or not shown.
  DiffSyntaxView view({
    required RepositorySessionIdentity identity,
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
  }) {
    final view = DiffSyntaxView._(this, identity, origin, diffRequestId);
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

  BigInt _requestId() {
    final id = _nextRequest;
    _nextRequest += BigInt.one;
    return id;
  }

  /// Runs [view]'s next request now or when a slot frees up.
  void _ask(DiffSyntaxView view) {
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

  void _forget(DiffSyntaxView view) {
    _views.remove(view);
    _waiting.remove(view);
  }
}

/// The syntax colours of one accepted diff projection, as an overlay keyed
/// by stable row identity. Widgets read [rowSyntax] and listen for
/// changes; they never start work from build or row callbacks.
final class DiffSyntaxView {
  DiffSyntaxView._(
    this._service,
    this.identity,
    this.origin,
    this.diffRequestId,
  );

  /// Chunks of colours one view keeps; the ones farthest from the visible
  /// rows go first.
  static const retainedChunks = 8;

  final DiffSyntaxService _service;
  final RepositorySessionIdentity identity;
  final DiffSyntaxOrigin origin;
  final BigInt diffRequestId;

  final Map<int, DiffPage> _pages = {};
  final Map<String, DiffRowSyntax> _overlay = {};
  final Map<int, List<String>> _chunkRows = {};

  /// Chunk offsets whose outcome is settled, coloured or plain.
  final Set<int> _settled = {};

  /// Chunks that came back deferred once and may be asked once more.
  final Set<int> _deferredOnce = {};
  final Queue<(String, DiffRowSyntax)> _unpublished = Queue();

  int _firstVisible = 0;
  int _lastVisible = ContractLimits.syntaxPageRows - 1;
  Timer? _idleTimer;
  bool _interacting = false;
  bool _requesting = false;
  bool _publishing = false;
  bool _retired = false;
  BigInt? _inFlight;

  final List<void Function()> _listeners = [];

  /// Calls [listener] whenever more rows have colours.
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Paintable colours of the row [stableId], or null for plain text.
  DiffRowSyntax? rowSyntax(String stableId) => _overlay[stableId];

  /// Rows of a page the workflow accepted and already shows as plain text.
  /// Colours are requested later, once the user is idle.
  void accept(DiffPage page) {
    if (_retired || page.requestId != diffRequestId) return;
    _pages[page.offset] = page;
    _restartIdle();
  }

  /// The rows on screen, reported after scrolling settles.
  void setVisible(int first, int last) {
    if (_retired) return;
    _firstVisible = first;
    _lastVisible = last < first ? first : last;
    _restartIdle();
  }

  /// Scrolling, dragging, typing or navigation in progress: pauses both new
  /// requests and publication until it ends.
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

  /// Any user input or foreground work: postpones requests by [idle].
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
  /// the visible rows. Only accepted rows; never a page fetched for colour.
  int? _nextChunk() {
    const size = ContractLimits.syntaxPageRows;
    final first = (_firstVisible ~/ size) * size;
    for (var chunk = first; chunk <= _lastVisible + size; chunk += size) {
      if (_settled.contains(chunk)) continue;
      if (_pageFor(chunk) == null) continue;
      return chunk;
    }
    return null;
  }

  DiffPage? _pageFor(int index) {
    for (final page in _pages.values) {
      if (index >= page.offset && index < page.offset + page.rows.length) {
        return page;
      }
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
    final page = _pageFor(chunk)!;
    const size = ContractLimits.syntaxPageRows;
    var offset = chunk;
    final end = (chunk + size).clamp(0, page.offset + page.rows.length);
    var anyDeferred = false;
    while (offset < end && !_retired) {
      final requestId = _service._requestId();
      _inFlight = requestId;
      final DiffSyntaxPage reply;
      try {
        reply = await _service._repository.diffSyntaxPage(
          identity,
          origin: origin,
          diffRequestId: diffRequestId,
          syntaxRequestId: requestId,
          offset: offset,
          maximumRows: end - offset,
        );
      } on Object {
        // A stale projection, a disconnect or a missing family: plain text.
        _settled.add(chunk);
        return;
      } finally {
        _inFlight = null;
      }
      if (_retired) return;
      final rows = _validRows(reply, requestId, offset, end, page);
      if (rows == null) {
        _settled.add(chunk);
        return;
      }
      anyDeferred |= rows.any(
        (row) =>
            row.oldState == DiffSyntaxSideState.deferred ||
            row.newState == DiffSyntaxSideState.deferred,
      );
      final conversions = [
        for (var index = 0; index < rows.length; index += 1)
          DiffSyntaxConversion(
            page.rows[offset - page.offset + index].text,
            rows[index],
          ),
      ];
      final List<DiffRowSyntax?> converted;
      try {
        converted = await _service._convert(conversions);
      } on Object {
        _settled.add(chunk);
        return;
      }
      if (_retired) return;
      final ids = _chunkRows.putIfAbsent(chunk, () => []);
      for (var index = 0; index < rows.length; index += 1) {
        final syntax = converted[index];
        if (syntax == null) continue;
        ids.add(rows[index].stableId);
        _unpublished.add((rows[index].stableId, syntax));
      }
      unawaited(_publish());
      if (reply.nextOffset == null) break;
      offset = reply.nextOffset!;
    }
    if (anyDeferred && _deferredOnce.add(chunk)) {
      // One more demand-driven try once the worker had capacity.
      return;
    }
    _settled.add(chunk);
    _evict();
  }

  /// The reply's rows when it matches this view, the request and the
  /// accepted rows exactly; null otherwise.
  List<DiffSyntaxRowResult>? _validRows(
    DiffSyntaxPage reply,
    BigInt requestId,
    int offset,
    int end,
    DiffPage page,
  ) {
    if (reply.origin != origin ||
        reply.diffRequestId != diffRequestId ||
        reply.syntaxRequestId != requestId ||
        reply.offset != offset ||
        reply.rows.isEmpty ||
        offset + reply.rows.length > end) {
      return null;
    }
    final next = reply.nextOffset;
    if (next != null && next != offset + reply.rows.length) return null;
    for (var index = 0; index < reply.rows.length; index += 1) {
      if (reply.rows[index].stableId !=
          page.rows[offset - page.offset + index].stableId) {
        return null;
      }
    }
    return reply.rows;
  }

  /// Publishes converted rows a few per frame, never while the user
  /// scrolls or selects.
  Future<void> _publish() async {
    if (_publishing) return;
    _publishing = true;
    try {
      while (_unpublished.isNotEmpty && !_retired && !_interacting) {
        await _service._nextFrame();
        if (_retired || _interacting) return;
        for (
          var count = 0;
          count < _service.rowsPerFrame && _unpublished.isNotEmpty;
          count += 1
        ) {
          final (id, syntax) = _unpublished.removeFirst();
          _overlay[id] = syntax;
        }
        _notify();
      }
    } finally {
      _publishing = false;
    }
  }

  /// Drops the chunks farthest from the visible rows beyond
  /// [retainedChunks]; they settle again only if asked for again.
  void _evict() {
    if (_chunkRows.length <= retainedChunks) return;
    final center = (_firstVisible + _lastVisible) ~/ 2;
    final chunks = _chunkRows.keys.toList()
      ..sort((a, b) => (b - center).abs().compareTo((a - center).abs()));
    for (final chunk in chunks.take(_chunkRows.length - retainedChunks)) {
      for (final id in _chunkRows.remove(chunk)!) {
        _overlay.remove(id);
      }
      _settled.remove(chunk);
    }
  }

  /// Stops all work of this view and forgets its colours.
  void dispose() {
    if (_retired) return;
    _retired = true;
    _idleTimer?.cancel();
    final inFlight = _inFlight;
    if (inFlight != null) {
      unawaited(
        _service._repository
            .cancelDiffSyntax(
              identity,
              origin: origin,
              diffRequestId: diffRequestId,
              syntaxRequestId: inFlight,
            )
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    _service._forget(this);
    _pages.clear();
    _overlay.clear();
    _unpublished.clear();
    _listeners.clear();
  }
}
