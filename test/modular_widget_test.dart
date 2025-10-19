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
    Modular.init(_TestModule());
    repository = Modular.get<TestRepository<int>>();
  });

  tearDown(() {
    cleanGlobals();
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    void Function(TestRepository<int> repo)? onContentBuild,
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
    await tester.pump(const Duration(milliseconds: 1000));

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
    TestRepository<int>? repoSeenInContent;

    await pumpHarness(
      tester,
      onContentBuild: (repo) => repoSeenInContent = repo,
    );

    repository.setData(42);
    await tester.pump(const Duration(milliseconds: 100));

    expect(repoSeenInContent, same(repository));
  });

  group('ModularWidget with multiple repositories', () {
    late FirstRepository firstRepository;
    late SecondRepository secondRepository;

    setUp(() {
      cleanGlobals();
      Modular.init(_MultiRepoModule());
      firstRepository = Modular.get<FirstRepository>();
      secondRepository = Modular.get<SecondRepository>();
    });

    Future<void> pumpMultiHarness(
      WidgetTester tester, {
      void Function(FirstRepository first, SecondRepository second)?
      onContentBuild,
    }) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _MultiRepoHarness(onContentBuild: onContentBuild),
        ),
      );
      await tester.pump();
    }

    testWidgets('stays loading until all watched repositories resolve', (
      tester,
    ) async {
      await pumpMultiHarness(tester);

      expect(find.text('multi-loader'), findsOneWidget);

      firstRepository.setData(1);
      await tester.pump();
      expect(find.text('multi-loader'), findsOneWidget);

      secondRepository.setData(2);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('multi-content: 1 + 2'), findsOneWidget);
    });

    testWidgets('shows error when any repository enters error state', (
      tester,
    ) async {
      await pumpMultiHarness(tester);

      firstRepository.setData(5);
      secondRepository.setData(9);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('multi-content: 5 + 9'), findsOneWidget);

      secondRepository.setError(Exception('multi boom'));
      await tester.pump();
      await tester.pump();

      expect(find.text('multi-error: Exception: multi boom'), findsOneWidget);
    });

    testWidgets('provides get accessor for each repository in content', (
      tester,
    ) async {
      FirstRepository? firstSeen;
      SecondRepository? secondSeen;

      await pumpMultiHarness(
        tester,
        onContentBuild: (first, second) {
          firstSeen = first;
          secondSeen = second;
        },
      );

      firstRepository.setData(3);
      secondRepository.setData(4);
      await tester.pump(const Duration(milliseconds: 100));

      expect(firstSeen, same(firstRepository));
      expect(secondSeen, same(secondRepository));
    });
  });
}

class _TestHarness extends ModularWidget<int> {
  const _TestHarness({this.onContentBuild});

  final void Function(TestRepository<int> repo)? onContentBuild;

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
    onContentBuild?.call(get<TestRepository<int>>());
    return Text('content: $data');
  }

  @override
  FutureOr<int> query(RepoAccessor watch) {
    final repo = watch<TestRepository<int>>();
    return repo.state.requireData;
  }
}

class _TestModule extends Module {
  @override
  void binds(Injector i) {
    i.addRepository<TestRepository<int>>(TestRepository<int>.new);
  }
}

class _MultiRepoHarness extends ModularWidget<String> {
  const _MultiRepoHarness({this.onContentBuild});

  final void Function(FirstRepository first, SecondRepository second)?
  onContentBuild;

  @override
  Widget buildLoader(BuildContext context) => const Text('multi-loader');

  @override
  Widget buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => Text('multi-error: $error');

  @override
  Widget buildContent(BuildContext context, String data, RepoAccessor get) {
    onContentBuild?.call(get<FirstRepository>(), get<SecondRepository>());
    return Text(data);
  }

  @override
  FutureOr<String> query(RepoAccessor watch) {
    final first = watch<FirstRepository>().state.requireData;
    final second = watch<SecondRepository>().state.requireData;
    return 'multi-content: $first + $second';
  }
}

class _MultiRepoModule extends Module {
  @override
  void binds(Injector i) {
    i
      ..addRepository<FirstRepository>(FirstRepository.new)
      ..addRepository<SecondRepository>(SecondRepository.new);
  }
}

class FirstRepository extends TestRepository<int> {}

class SecondRepository extends TestRepository<int> {}
