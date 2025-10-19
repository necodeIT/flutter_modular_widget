import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_modular_widget/flutter_modular_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcquenji_core/mcquenji_core.dart';

import 'support/test_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestRepository<int> repository;

  setUp(() {
    Modular.init(_StatefulModule());
    repository = Modular.get<TestRepository<int>>();
  });

  tearDown(() {
    cleanGlobals();
  });

  Future<void> pumpStatefulHarness(
    WidgetTester tester, {
    void Function(_HarnessContentState state)? onStateBuilt,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _StatefulHarness(onStateBuilt: onStateBuilt),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpKeyedHarness(
    WidgetTester tester, {
    void Function(_KeyedContentState state)? onStateBuilt,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _KeyedStatefulHarness(onStateBuilt: onStateBuilt),
      ),
    );
    await tester.pump();
  }

  testWidgets('passes derived data and repo access into content state', (
    tester,
  ) async {
    _HarnessContentState? seenState;

    await pumpStatefulHarness(
      tester,
      onStateBuilt: (state) => seenState = state,
    );

    repository.setData(8);
    await tester.pump(const Duration(milliseconds: 100));

    final state = seenState!;
    expect(find.text('state:${state.id} data:8'), findsOneWidget);
    expect(state.widget.data, 8);
    expect(state.repoFromGet, same(repository));
  });

  testWidgets('retains the same state instance without a content key', (
    tester,
  ) async {
    final states = <_HarnessContentState>{};

    await pumpStatefulHarness(tester, onStateBuilt: states.add);

    repository.setData(1);
    await tester.pump(const Duration(milliseconds: 100));

    repository.setData(2);
    await tester.pump(const Duration(milliseconds: 100));

    expect(states.length, 1);
    expect(states.single.buildCount, greaterThanOrEqualTo(2));
  });

  testWidgets('recreates content state when contentKey returns a new value', (
    tester,
  ) async {
    final ids = <int>{};

    await pumpKeyedHarness(tester, onStateBuilt: (state) => ids.add(state.id));

    repository.setData(10);
    await tester.pump(const Duration(milliseconds: 100));

    repository.setData(11);
    await tester.pump(const Duration(milliseconds: 100));

    final idList = ids.toList();
    expect(idList.length, 2);
    expect(idList.first, isNot(idList.last));
  });
}

class _StatefulHarness extends ModularWidget<int> with StatefulContent<int> {
  const _StatefulHarness({this.onStateBuilt});

  final void Function(_HarnessContentState state)? onStateBuilt;

  @override
  Widget buildLoader(BuildContext context) => const Text('loader');

  @override
  Widget buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => Text('error: $error');

  @override
  ModularState<int> createContentState() => _HarnessContentState(onStateBuilt);

  @override
  FutureOr<int> query(RepoAccessor watch) {
    final repo = watch<TestRepository<int>>();
    return repo.state.requireData;
  }
}

class _KeyedStatefulHarness extends ModularWidget<int>
    with StatefulContent<int> {
  const _KeyedStatefulHarness({this.onStateBuilt});

  final void Function(_KeyedContentState state)? onStateBuilt;

  @override
  Widget buildLoader(BuildContext context) => const Text('loader');

  @override
  Widget buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => Text('error: $error');

  @override
  ModularState<int> createContentState() => _KeyedContentState(onStateBuilt);

  @override
  Key? contentKey(int data) => ValueKey<int>(data);

  @override
  FutureOr<int> query(RepoAccessor watch) {
    final repo = watch<TestRepository<int>>();
    return repo.state.requireData;
  }
}

class _HarnessContentState extends ModularState<int> {
  _HarnessContentState(this.onStateBuilt);

  static int _nextId = 0;

  final void Function(_HarnessContentState state)? onStateBuilt;

  late final int id;
  int buildCount = 0;
  TestRepository<int>? repoFromGet;

  @override
  void initState() {
    super.initState();
    id = _nextId++;
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    repoFromGet ??= widget.get<TestRepository<int>>();
    onStateBuilt?.call(this);
    return Text('state:$id data:${widget.data}');
  }
}

class _KeyedContentState extends ModularState<int> {
  _KeyedContentState(this.onStateBuilt);

  static int _nextId = 0;

  final void Function(_KeyedContentState state)? onStateBuilt;

  late final int id;

  @override
  void initState() {
    super.initState();
    id = _nextId++;
  }

  @override
  Widget build(BuildContext context) {
    onStateBuilt?.call(this);
    return Text('keyed-state:$id data:${widget.data}');
  }
}

class _StatefulModule extends Module {
  @override
  void binds(Injector i) {
    i.addRepository<TestRepository<int>>(TestRepository<int>.new);
  }
}
