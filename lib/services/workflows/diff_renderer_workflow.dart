import 'dart:async';

import '../../models/diff_renderer.dart';
import '../inspector/inspector_service.dart';
import 'workflow.dart';

/// What rendering a diff with the configured renderer asks of the window.
abstract interface class DiffRendererInteraction
    implements WorkflowInteraction {
  /// Shows the exact commands [preview] runs and asks to run them.
  Future<bool> confirmRenderer(DiffRendererPreview preview);
}

/// One renderer run: its results until it is ready, and a way to stop it.
final class DiffRendererRun {
  DiffRendererRun._(this._inspector);

  final InspectorService _inspector;
  final StreamController<DiffRendererResult> _results =
      StreamController<DiffRendererResult>();
  DiffRendererPreview? _preview;
  var _stopped = false;

  /// The renderer's results; it closes when the renderer is done, was
  /// declined or was cancelled.
  Stream<DiffRendererResult> get results => _results.stream;

  /// Stops polling and cancels the renderer when it already started.
  Future<void> cancel() async {
    if (_stopped) return;
    _stopped = true;
    final preview = _preview;
    _preview = null;
    if (preview != null) await _inspector.cancelDiffRenderer(preview);
    if (!_results.isClosed) await _results.close();
  }

  void _add(DiffRendererResult result) {
    if (!_stopped && !_results.isClosed) _results.add(result);
  }
}

/// Renders the diff the inspector shows with a configured renderer: it
/// previews the commands, asks to run them and polls the renderer until it
/// is ready. A failure becomes a fallback result, so the built-in diff
/// stays.
final class DiffRendererWorkflow {
  DiffRendererWorkflow(
    this._inspector, {
    this.interval = const Duration(milliseconds: 40),
  });

  final InspectorService _inspector;
  final Duration interval;

  DiffRendererRun render(
    DiffRendererInteraction interaction,
    DiffRendererDefinition definition,
  ) {
    final run = DiffRendererRun._(_inspector);
    unawaited(_drive(run, interaction, definition));
    return run;
  }

  Future<void> _drive(
    DiffRendererRun run,
    DiffRendererInteraction interaction,
    DiffRendererDefinition definition,
  ) async {
    try {
      final preview = await _inspector.previewDiffRenderer(definition);
      if (run._stopped || !interaction.active) return;
      if (!await interaction.confirmRenderer(preview)) {
        await _inspector.cancelDiffRenderer(preview);
        return;
      }
      if (run._stopped) return;
      run._preview = preview;
      var result = await _inspector.executeDiffRenderer(preview);
      run._add(result);
      while (result.state == DiffRendererState.pending &&
          !run._stopped &&
          interaction.active) {
        await Future<void>.delayed(interval);
        if (run._stopped) return;
        result = await _inspector.pollDiffRenderer(preview);
        run._add(result);
      }
      run._preview = null;
    } on DiffRendererException catch (error) {
      run._add(
        DiffRendererResult(
          state: DiffRendererState.fallback,
          failure: error.code,
        ),
      );
    } finally {
      if (!run._results.isClosed) await run._results.close();
    }
  }
}
