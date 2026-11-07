import 'package:flutter/widgets.dart';

import '../../models/diff.dart';

/// How diffs are shown, and how a diff view changes that for every diff
/// view. The workspace stores the preferences in the settings; an inspector
/// window keeps its own for as long as it is open.
class DiffViewPreferencesScope extends InheritedWidget {
  const DiffViewPreferencesScope({
    super.key,
    required this.preferences,
    required this.onChanged,
    required super.child,
  });

  final DiffViewPreferences preferences;
  final ValueChanged<DiffViewPreferences> onChanged;

  static DiffViewPreferencesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiffViewPreferencesScope>();

  @override
  bool updateShouldNotify(DiffViewPreferencesScope oldWidget) =>
      preferences != oldWidget.preferences;
}

/// A diff view's reading of [DiffViewPreferencesScope]. Without a scope the
/// view keeps its preferences itself.
mixin DiffViewPreferencesState<T extends StatefulWidget> on State<T> {
  DiffViewPreferences _own = const DiffViewPreferences();
  DiffViewPreferences? _scoped;
  DiffViewPreferencesScope? _scope;

  /// The load choices last handed to [loadDiffPreferences], so a diff
  /// widened past them by Show More Context keeps its context until the
  /// preferences change.
  DiffViewPreferences? _loaded;

  DiffViewPreferences get diffPreferences => _scoped ?? _own;

  /// Reloads the shown diff with the load choices of [preferences].
  void loadDiffPreferences(DiffViewPreferences preferences);

  /// Whether the shown diff was loaded with other choices than
  /// [preferences], before any preference change was seen.
  bool diffLoadedOtherwise(DiffViewPreferences preferences);

  @override
  void initState() {
    super.initState();
    // Without a dependency yet; the first load already follows the scope.
    _scoped = context
        .getInheritedWidgetOfExactType<DiffViewPreferencesScope>()
        ?.preferences;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = DiffViewPreferencesScope.maybeOf(context);
    _scoped = _scope?.preferences;
    _follow(diffPreferences);
  }

  /// Changes the preferences of every diff view.
  void changeDiffPreferences(DiffViewPreferences preferences) {
    if (preferences == diffPreferences) return;
    if (_scope case final scope?) {
      scope.onChanged(preferences);
    } else {
      setState(() => _own = preferences);
      _follow(preferences);
    }
  }

  void _follow(DiffViewPreferences preferences) {
    final loaded = _loaded;
    _loaded = preferences;
    final changed = loaded == null
        ? diffLoadedOtherwise(preferences)
        : !preferences.loadsLike(loaded);
    if (changed) loadDiffPreferences(preferences);
  }
}
