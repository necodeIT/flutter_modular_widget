import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mcquenji_core/mcquenji_core.dart';

/// A base widget that wires a screen to **Repositories** registered with
/// `flutter_modular`.
///
/// `ModularWidget` helps you:
/// - **Declare dependencies** by *watching* repositories inside [query].
/// - **React to repository state** (`AsyncValue`) to show loading and error UIs.
/// - **Derive view data** ([T]) once all watched repositories are healthy.
/// - **Access repositories** non-reactively inside [buildContent] via `get`.
///
/// Type parameter:
/// - [T] is the *derived* data passed to [buildContent].
abstract class ModularWidget<T> extends StatefulWidget {
  /// Creates a new `ModularWidget`.
  const ModularWidget({super.key});

  /// Build shown while any watched repository is loading *or* while [query]
  /// hasn’t produced data yet.
  Widget buildLoader(BuildContext context);

  /// Build shown when any watched repository errors or when [query] throws.
  ///
  /// The [error] is the first encountered error from a watched repository’s
  /// `AsyncValue` or from [query] itself.
  Widget buildError(BuildContext context, Object error);

  /// Build shown when all watched repositories are healthy and [query] has
  /// produced [data].
  ///
  /// The [get] callback allows **non-reactive** access to repositories, i.e.
  /// it is equivalent to `Modular.get<R>()` and does **not** subscribe to
  /// repository changes.
  Widget buildContent(
    BuildContext context,
    T data,
    R Function<R extends Repository>() get,
  );

  /// Derive the view data from repositories.
  ///
  /// Call [watch] for each repository you depend on. This both **returns** the
  /// repo instance and **subscribes** the widget to its stream so that changes
  /// trigger re-computation.
  ///
  /// May return data synchronously or asynchronously.
  FutureOr<T> query(R Function<R extends Repository>() watch);

  @override
  State<ModularWidget<T>> createState() => _ModularWidgetState<T>();
}

class _ModularWidgetState<T> extends State<ModularWidget<T>> {
  /// Active subscriptions to watched repository streams.
  ///
  /// Populated lazily on first [_watch] call per repository; disposed in [dispose].
  final List<StreamSubscription> _subs = [];

  /// Set of repositories that were declared via [_watch].
  ///
  /// Used for efficient iteration when checking loading/error states.
  final Set<Repository> _watched = {};

  /// The most recent error coming from a watched repository or from [_refresh].
  Object? _error;

  /// The latest successfully derived data from [ModularWidget.query].
  T? _data;

  /// Whether the UI should currently show the loader.
  ///
  /// This is set when *any* watched repository reports `isLoading` on its
  /// `AsyncValue` or while initial data is being computed.
  bool _loading = false;

  /// Guard to prevent concurrent executions of [_refresh].
  bool _isRefreshing = false;

  /// Indicates that a refresh has been scheduled for the next frame to avoid
  /// re-entrancy during build/layout.
  bool _refreshQueued = false;

  // --- dependency tracking ---

  /// Watch (and obtain) a repository of type [R].
  ///
  /// - Returns the repository instance via `Modular.get<R>()`.
  /// - On first access per repo, subscribes to its [Repository.stream] so that
  ///   future changes call [_onRepoChanged].
  ///
  /// Use this exclusively inside [ModularWidget.query] to **declare** dependencies.
  R _watch<R extends Repository>() {
    final repo = Modular.get<R>();
    if (!_watched.contains(repo)) {
      _watched.add(repo);
      _subs.add(repo.stream.listen((_) => _onRepoChanged()));
    }
    return repo;
  }

  // --- non-reactive accessor for buildContent ---

  /// Obtain a repository of type [R] **without** subscribing to its changes.
  ///
  /// Intended for use inside [ModularWidget.buildContent] (e.g., for button callbacks or
  /// invoking repository methods). This does not affect dependency tracking.
  R _get<R extends Repository>() => Modular.get<R>();

  /// Handle any change emitted by watched repositories.
  ///
  /// Evaluates all [_watched] repos:
  /// - If any has an error (`AsyncValue.hasError`), records it and shows
  ///   [ModularWidget.buildError].
  /// - Else if any is loading (`AsyncValue.isLoading`), sets [_loading] and
  ///   shows [ModularWidget.buildLoader].
  /// - Else clears error/loading and schedules a data [_refresh] if none is
  ///   currently running or queued.
  void _onRepoChanged() {
    Object? repoError;
    bool anyLoading = false;

    for (final repo in _watched) {
      final s = repo.state;
      if (s is AsyncValue) {
        if (s.hasError) {
          repoError = s.error;
          // Errors take precedence over loading, thus we can break early
          // to avoid unnecessary work.
          break;
        }
        if (s.isLoading) anyLoading = true;
      }
    }

    if (!mounted) return;

    if (repoError != null) {
      setState(() {
        _error = repoError;
        _loading = false;
      });
      return;
    }

    if (anyLoading) {
      setState(() {
        _error = null;
        _loading = true;
      });
      return;
    }

    // Healthy: clear flags and schedule a refresh if needed.
    setState(() {
      _error = null;
      _loading = false;
    });

    if (_isRefreshing || _refreshQueued) return;
    _refreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _refreshQueued = false;
    });
  }

  /// Re-compute [_data] by invoking [widget.query] with [_watch].
  ///
  /// Safeguards:
  /// - Returns early when the widget is unmounted.
  /// - Skips while already refreshing ([ _isRefreshing ]).
  /// - Skips if currently loading or in an error state to avoid thrashing.
  ///
  /// On success, updates [_data] and clears [_error]/[_loading].
  /// On failure, stores the thrown error in [_error] and clears [_loading].
  Future<void> _refresh() async {
    if (!mounted) return;
    if (_isRefreshing) return;
    if (_loading) return;
    if (_error != null) return;

    _isRefreshing = true;

    try {
      final result = await widget.query(_watch);
      if (!mounted) return;
      setState(() {
        _data = result;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }

    _isRefreshing = false;
  }

  @override
  void initState() {
    super.initState();

    // 1) Establish dependencies by running query once with [_watch].
    //    This registers all repositories that the screen depends on.
    widget.query(_watch);

    // 2) Compute the initial data on the next frame to avoid doing heavy work
    //    during init/build and to ensure all subscriptions are in place.
    _refreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _refreshQueued = false;
    });
  }

  @override
  void dispose() {
    // Cancel all repo subscriptions to prevent memory leaks.
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return widget.buildError(context, _error!);
    if (_loading || _data == null) return widget.buildLoader(context);
    return widget.buildContent(context, _data as T, _get);
  }
}
