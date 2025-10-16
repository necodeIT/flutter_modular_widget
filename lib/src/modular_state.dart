import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mcquenji_core/mcquenji_core.dart';

import 'modular_widget.dart';

/// Hosts **stateful, local UI logic** for a [ModularWidget]’s `buildContent`
/// while still receiving the **derived view data** (`T`) and the **non-reactive
/// repository accessor** (`get`).
///
/// This widget is created internally by the [StatefulContent] mixin and
/// should rarely be instantiated directly by users. It exists to decouple
/// the stateful content from the `ModularWidget` base class.
///
/// Typical flow:
/// 1. Your screen extends `ModularWidget<T>` and mixes in [StatefulContent].
/// 2. You implement `createContentState()` to return your own `ModularState<T>`.
/// 3. Your `ModularState<T>` uses `widget.data` and `widget.get<R>()` as needed.
///
/// ### Why this exists
/// `ModularWidget<T>` orchestrates repo watching, loading & error states, and
/// querying. Many screens still need **local UI state** (form controllers,
/// toggles, scroll positions, etc.). This adapter provides a normal `State`
/// surface dedicated to content-only logic.
///
/// ### Example
/// ```dart
/// class MyScreen extends ModularWidget<MyData> with StatefulContent<MyData> {
///   @override
///   ModularState<MyData> createContentState() => _MyScreenState();
///   // ... query / buildLoader / buildError ...
/// }
///
/// class _MyScreenState extends ModularState<MyData> {
///   bool expanded = false;
///
///   @override
///   Widget build(BuildContext context) {
///     final repo = widget.get<MyRepo>(); // non-reactive repo access
///     final data = widget.data;          // derived data from ModularWidget.query
///     return ListTile(
///       title: Text(data.title),
///       trailing: Switch(
///         value: expanded,
///         onChanged: (v) => setState(() => expanded = v),
///       ),
///       onTap: repo.refresh,
///     );
///   }
/// }
/// ```
///
/// See also:
/// - [StatefulContent] mixin: ergonomic integration for `ModularWidget<T>`.
/// - [ModularState] typedef: canonical base type for the content `State`.
class StatefulModularWidget<T> extends StatefulWidget {
  /// Creates a stateful host for content of a [ModularWidget].
  ///
  /// - [data] is the *derived* view model produced by [ModularWidget.query].
  /// - [get] provides **non-reactive** access to repositories (same as
  ///   `Modular.get<R>()`), intended for callbacks and one-off reads.
  /// - [_createContentState] constructs the user-provided `State` that
  ///   owns local UI state and renders the subtree.
  const StatefulModularWidget(
    this._createContentState, {
    super.key,
    required this.data,
    required this.get,
  });

  /// The *derived* data calculated by `ModularWidget.query` and passed
  /// into the content state for rendering.
  final T data;

  /// Non-reactive repository accessor (equivalent to `Modular.get<R>()`).
  ///
  /// Use this from your content `State` for button handlers and
  /// non-listening operations. It **does not** subscribe to repo updates.
  final R Function<R extends Repository>() get;

  /// Factory for the user’s content [State].
  ///
  /// This is intentionally provided by the caller (via [StatefulContent])
  /// so the user can maintain normal `State` with local fields, lifecycle
  /// methods, etc.
  final ModularState<T> Function() _createContentState;

  @override
  // We intentionally “inject” the user’s State here to give them a standard
  // `State` surface. The logic is minimal and deliberate, hence the ignore.
  // ignore: no_logic_in_create_state
  State<StatefulModularWidget<T>> createState() => _createContentState();
}

/// Mixin for `ModularWidget<T>` that turns `buildContent` into a **stateful
/// area** backed by a user-provided `State`.
///
/// Add this mixin to your `ModularWidget<T>` and implement:
/// - [createContentState] → return a `ModularState<T>` (your local `State`)
/// - *(optional)* [contentKey] → provide a stable [Key] based on [data] if
///   you need to rebuild/replace the content state when the data identity
///   changes.
///
/// This keeps the outer `ModularWidget` responsible for:
/// - Declaring dependencies via `query(watch)`
/// - Handling loading / error states
/// - Passing the final derived [data] and [get] into the stateful content
///
/// While your inner `State` remains a normal Flutter `State` with local
/// fields, `initState`, `setState`, etc.
mixin StatefulContent<T> on ModularWidget<T> {
  @override
  @nonVirtual
  Widget buildContent(
    BuildContext context,
    T data,
    R Function<R extends Repository>() get,
  ) => StatefulModularWidget<T>(
    createContentState,
    data: data,
    get: get,
    // If your content’s identity should follow `data`, provide a key here.
    // This is useful when you need to reset local state for new data sets.
    key: contentKey(data),
  );

  /// Create the **stateful content** that renders this screen’s body.
  ///
  /// Return a `State` that extends [ModularState] so it receives:
  /// - `widget.data` — the derived data for the current frame
  /// - `widget.get<R>()` — non-reactive repo access for actions
  ModularState<T> createContentState();

  /// Optional key factory for the content widget.
  ///
  /// Provide a key derived from [data] when you want the content `State`
  /// to be **recreated** whenever a semantically “new” dataset arrives.
  /// Return `null` to keep the same `State` instance across updates.
  Key? contentKey(T data) => null;
}

/// Canonical base type for the content `State`.
///
/// Extend this for your content state class (e.g. `_MyScreenState`) to get the
/// correct widget typing: `State<StatefulModularWidget<T>>`.
///
/// Example:
/// ```dart
/// class _MyScreenState extends ModularState<MyData> {
///   @override
///   Widget build(BuildContext context) {
///     final data = widget.data;
///     final repo = widget.get<MyRepo>();
///     // ...
///     return Container();
///   }
/// }
/// ```
typedef ModularState<T> = State<StatefulModularWidget<T>>;
