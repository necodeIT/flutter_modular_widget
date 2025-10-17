import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_modular_widget/flutter_modular_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcquenji_core/mcquenji_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestRepository repository;

  setUp(() {
    Modular.init(_TestModule());
    repository = Modular.get<TestRepository>();
  });

  tearDown(() {
    cleanGlobals();
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    void Function(TestRepository repo)? onContentBuild,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _TestHarness(onContentBuild: onContentBuild),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows loader while watched repository is loading', (
    tester,
  ) async {
    await pumpHarness(tester);

    expect(find.text('loader'), findsOneWidget);
  });

  testWidgets('renders derived content once repository provides data', (
    tester,
  ) async {
    await pumpHarness(tester);
    repository.setData(7);
    await tester.pump(Duration(milliseconds: 1000));

    expect(find.text('content: 7'), findsOneWidget);
  });

  testWidgets('renders error UI when repository enters error state', (
    tester,
  ) async {
    await pumpHarness(tester);
    repository.setData(1);
    await tester.pump();
    await tester.pump();

    repository.setError(Exception('boom'));
    await tester.pump();
    await tester.pump();

    expect(find.text('error: Exception: boom'), findsOneWidget);
  });

  testWidgets('exposes non-reactive repository access via get callback', (
    tester,
  ) async {
    TestRepository? repoSeenInContent;

    await pumpHarness(
      tester,
      onContentBuild: (repo) => repoSeenInContent = repo,
    );

    repository.setData(42);
    await tester.pump(Duration(milliseconds: 100));

    expect(repoSeenInContent, same(repository));
  });
}

class _TestHarness extends ModularWidget<int> {
  const _TestHarness({this.onContentBuild});

  final void Function(TestRepository repo)? onContentBuild;

  @override
  Widget buildLoader(BuildContext context) => const Text('loader');

  @override
  Widget buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => Text('error: $error');

  @override
  Widget buildContent(BuildContext context, int data, RepoAccessor get) {
    onContentBuild?.call(get<TestRepository>());
    return Text('content: $data');
  }

  @override
  FutureOr<int> query(RepoAccessor watch) {
    final repo = watch<TestRepository>();
    return repo.state.requireData;
  }
}

class _TestModule extends Module {
  @override
  void binds(Injector i) {
    i.addRepository<TestRepository>(TestRepository.new);
  }
}

class TestRepository extends Repository<AsyncValue<int>> {
  TestRepository() : super(AsyncValue.loading());

  void setData(int value) => emit(AsyncValue.data(value));

  void setError(Object error) => emit(AsyncValue.error(error));
}
