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
  Widget buildError(BuildContext context, Object error, StackTrace? stackTrace);

  /// Build shown when all watched repositories are healthy and [query] has
  /// produced [data].
  ///
  /// The [get] callback allows **non-reactive** access to repositories, i.e.
  /// it is equivalent to `Modular.get<R>()` and does **not** subscribe to
  /// repository changes.
  Widget buildContent(BuildContext context, T data, RepoAccessor get);

  /// Derive the view data from repositories.
  ///
  /// Call [watch] for each repository you depend on. This both **returns** the
  /// repo instance and **subscribes** the widget to its stream so that changes
  /// trigger re-computation.
  ///
  /// May return data synchronously or asynchronously.
  FutureOr<T> query(RepoAccessor watch);

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

  AsyncValue<T> _state = AsyncValue<T>.loading();

  /// Guard to prevent concurrent executions of [_refresh].
  bool _isRefreshing = false;

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
        _state = AsyncValue<T>.error(repoError!);
      });
      return;
    }

    if (anyLoading) {
      setState(() {
        _state = AsyncValue<T>.loading();
      });
      return;
    }

    _refresh();
  }

  /// Re-compute [_data] by invoking [widget.query] with [_get].
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

    _isRefreshing = true;

    _state = await AsyncValue.guard(() => widget.query(_watch));

    _isRefreshing = false;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();

    _init();
  }

  void _init() async {
    // 1) Establish dependencies by running query once with [_watch].
    //    This registers all repositories that the screen depends on.
    try {
      final data = await widget.query(_watch);

      _state = AsyncValue<T>.data(data);
    } catch (e) {
      // Ignore errors here; they will be handled in the next frame.
    } finally {
      // 2) Compute the initial data on the next frame to avoid doing heavy work
      //    during init/build and to ensure all subscriptions are in place.
      // _refreshQueued = true;
      // WidgetsBinding.instance.addPostFrameCallback((_) async {
      //   await _refresh();
      //   _refreshQueued = false;
      // });
    }
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
    return _state.when(
      data: (data) => widget.buildContent(context, data, _get),
      loading: () => widget.buildLoader(context),
      error: (error, stackTrace) =>
          widget.buildError(context, error, stackTrace),
    );
  }
}

/// Type alias for a function that retrieves a repository of type [R].
typedef RepoAccessor = R Function<R extends Repository>();
