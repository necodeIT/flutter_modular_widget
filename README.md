# flutter_modular_widget

A tiny base layer for Flutter screens that depend on multiple **Modular** repositories.
It wires your UI to repositories from [`mcquenji_core`](https://github.com/mcquenji/mcquenji_core) / `flutter_modular`, handles **loading/error** states for you, and gives you a clean place to **derive view data** before building.

## ✨ What you get

* **Declarative dependencies** — declare which repositories your screen needs by *watching* them inside `query`.
* **Built-in loading & error UI** — if any watched repo is loading you get `buildLoader()`, if any errored you get `buildError(error)`.
* **Derived view model** — compute and pass a typed `T` into your content widget once all repos are healthy.
* **Non-reactive access in build** — use `get<MyRepo>()` inside `buildContent` for event handlers, helpers, etc.
* **Optional local state** — mix in `StatefulContent` to keep widget-local state in a familiar `State` subclass (`ModularState<T>`).

## 📦 Install

```yaml
dependencies:
  flutter_modular_widget:
    git:
      url: https://github.com/necodeIT/flutter_modular_widget
  flutter_modular: ^6.3.4
  mcquenji_core:
    git:
      url: https://github.com/mcquenji/mcquenji_core.git
```

> The package expects **repositories** from `mcquenji_core` (which expose an `AsyncValue` state) to be registered in your Modular graph.

## 🧠 Core concepts

* **Repository**: a piece of business logic (from `mcquenji_core`) whose `state` is an `AsyncValue` (`loading / data / error`).
* **watch<R extends Repository>()**: declare a reactive dependency on a repo in `query`. The screen will rebuild when that repo’s state changes.
* **get<R extends Repository>()**: fetch a repo **non-reactively** (use in `buildContent` for callbacks, methods, etc.).
* **query() -> FutureOr<T>**: derive your view data `T` from watched repositories. Runs once all watched repos are ready; re-runs when any of them changes. It is safe to throw here; the error will be caught and passed to `buildError`.
* **buildLoader / buildError / buildContent**: the three render phases that `ModularWidget<T>` manages for you.
* **StatefulContent + ModularState**: opt-in mixin to keep local widget state while still receiving the derived `T` and the `get` accessor.

## 🚀 Quick start

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mcquenji_core/mcquenji_core.dart';
import 'package:flutter_modular_widget/modular_widget.dart';

/// Example repositories
class UserRepo extends Repository<AsyncValue<User>> { /* ... */ }
class SettingsRepo extends Repository<AsyncValue<Settings>> { /* ... */ }

/// The screen’s derived view data
class MyViewData {
  final User user;
  final Settings settings;
  const MyViewData(this.user, this.settings);
}

class MyScreen extends ModularWidget<MyViewData> with StatefulContent<MyViewData> {
  // 1) Show while any watched repo is loading
  @override
  Widget buildLoader(BuildContext context) => const Center(child: Text('Loading…'));

  // 2) Show when any watched repo errors
  @override
  Widget buildError(BuildContext context, Object error) =>
      Center(child: Text('Oops: $error'));

  // 3) Derive view data once repos are healthy (declare deps here!)
  @override
  FutureOr<MyViewData> query<R extends Repository>(R Function<R extends Repository>() watch) async {
    final userRepo = watch<UserRepo>();        // reactive
    final settingsRepo = watch<SettingsRepo>(); // reactive

    final user = (await userRepo.state.requireData);
    final settings = (await settingsRepo.state.requireData);

    return MyViewData(user, settings);
  }

  // 4) Build the actual UI
  @override
  Widget buildContent(
    BuildContext context,
    MyViewData data,
    R Function<R extends Repository>() get, // non-reactive accessor
  ) {
    final userRepo = get<UserRepo>(); // for actions/callbacks, not reactive
    return Column(
      children: [
        Text('Hello, ${data.user.name}'),
        ElevatedButton(
          onPressed: () => userRepo.refresh(), // example side-effect
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  // 5) (Optional) Keep local widget state
  @override
  ModularState<MyViewData> createContentState() => _MyScreenState();
}

class _MyScreenState extends ModularState<MyViewData> {
  // Local UI state (text controllers, animations, focus nodes, etc.)
  @override
  Widget build(BuildContext context) {
    final data = widget.data;                   // derived MyViewData
    final settings = widget.get<SettingsRepo>(); // non-reactive access
    // Compose additional UI here if you prefer keeping it in a State subclass
    return Container(); // or return null and keep all UI in buildContent above
  }
}
```

## 🔄 Lifecycle & reactivity

* On first build, `ModularWidget` subscribes to every repository you **watch** in `query`.
* If **any watched repo** is `loading`, you get `buildLoader`.
* If **any watched repo** is in `error`, you get `buildError(error)` (first error wins).
* Once **all watched repos** are ready, `query` runs to produce `T`, then `buildContent` renders with that `T`.
* On later changes, if any watched repo’s state changes, `query` runs again and the widget rebuilds accordingly.
* Subscriptions are disposed automatically.

* **Declare all dependencies in `query` using `watch`**. Don’t call `get` in `query` (that would be non-reactive).
* **Keep `buildContent` pure**. Use `get` only for callbacks, methods, or one-off, non-reactive reads.
* **Short-circuit heavy work**: if you need expensive mapping, do it in `query` and pass the result down.
* **Local UI state?** Use `with StatefulContent` and a `ModularState<T>` to keep animations, controllers, etc.
* **Error/Loading precedence**: error beats loading; otherwise loading beats content.

```dart
abstract class ModularWidget<T> extends StatefulWidget {
  const ModularWidget({super.key});

  // Render phases
  Widget buildLoader(BuildContext context);
  Widget buildError(BuildContext context, Object error);
  Widget buildContent(
    BuildContext context,
    T data,
    R Function<R extends Repository>() get,
  );

  // Declare reactive dependencies & derive view data
  FutureOr<T> query(R Function<R extends Repository>() watch);
}
```

Optional local state:

```dart
mixin StatefulContent<T> on ModularWidget<T> {
  ModularState<T> createContentState(); // provide your State subclass
}

typedef ModularState<T> = State<StatefulModularWidget<T>>;
```

## 🙋 FAQ

**Q: How are errors “resolved”?**
When a previously errored repository transitions to a non-error state, the screen will leave `buildError` automatically and re-evaluate `query`. You don’t need to track which repo failed; subscriptions handle that.

**Q: Can I mix `watch` and `get`?**
Yes. Use `watch` inside `query` (reactive). Use `get` inside `buildContent` or your `ModularState` for callbacks and helpers (non-reactive).

**Q: Do I need `StatefulContent`?**
Only if you want local UI state (animations, controllers, etc.). Otherwise, keep everything in `buildContent`.
