import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/hub_top_bar.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/plp_controller.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';

/// A listing opened by uid for a category the admin keeps out of the menu
/// (`include_in_menu` 0: on Hub Market Shoes, Bags, Mobile & Tablet ...), as a
/// banner link, a push notification or a website link does. The listing takes
/// its title and its sub-category rail from the category; the menu tree does not
/// hold such a category, so the title was the generic "Categories" and there was
/// no rail. It is now fetched by its uid.

const _furniture = Category(
  uid: 'NzQ=',
  name: 'Furniture',
  urlKey: 'furniture',
  children: [
    Category(uid: 'NzU=', name: 'Home Furniture', urlKey: 'home-furniture'),
  ],
);

/// Shoes as the live store has it (1 Oct 2026): out of the menu, with two
/// children that are in it, and an archive one added here that is not.
const _shoes = Category(
  uid: 'NTM=',
  name: 'Shoes',
  urlKey: 'shoes',
  includeInMenu: false,
  children: [
    Category(uid: 'NTU=', name: 'Women', urlKey: 'women'),
    Category(uid: 'NTQ=', name: 'Men', urlKey: 'men'),
    Category(
      uid: 'OTk=',
      name: 'Archive',
      urlKey: 'archive',
      includeInMenu: false,
    ),
  ],
);

FakeCatalogRepository _catalog() => FakeCatalogRepository(
  categories: const [_furniture],
  categoriesByUid: const {'NTM=': _shoes},
  aggregations: const [],
);

/// The by-uid fetch answers when the test says so (or never, or with an error).
class _ControlledCatalog extends FakeCatalogRepository {
  _ControlledCatalog() : super(categories: const [_furniture]);

  final Completer<Category?> answer = Completer<Category?>();

  @override
  Future<Category?> fetchCategoryByUid(String uid) {
    categoryByUidCalls.add(uid);
    return answer.future;
  }
}

/// The by-uid fetch fails, as a dropped connection does.
class _FailingCatalog extends FakeCatalogRepository {
  _FailingCatalog() : super(categories: const [_furniture]);

  @override
  Future<Category?> fetchCategoryByUid(String uid) =>
      Future<Category?>.error(const Failure(FailureKind.network));
}

ProviderContainer _container(CatalogRepository repo) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      catalogRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(CatalogRepository repo, String uid) {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [
      GoRoute(
        path: '/page',
        builder: (_, __) => PlpScreen(categoryUid: uid),
      ),
      GoRoute(path: '/search', builder: (_, __) => const Scaffold()),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(repo),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light('en'),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The listing's app bar title.
Finder _title(String text) =>
    find.descendant(of: find.byType(HubTopBar), matching: find.text(text));

void main() {
  group('categoryByUidProvider', () {
    test('reads a category of the menu tree from it, with no request', () async {
      final repo = _catalog();
      final container = _container(repo);

      final top = await container.read(categoryByUidProvider('NzQ=').future);
      final nested = await container.read(categoryByUidProvider('NzU=').future);

      expect(top?.name, 'Furniture');
      expect(nested?.name, 'Home Furniture');
      expect(repo.categoryByUidCalls, isEmpty);
    });

    test('fetches a category the menu tree does not hold, by its uid', () async {
      final repo = _catalog();
      final container = _container(repo);

      final shoes = await container.read(categoryByUidProvider('NTM=').future);

      expect(shoes?.name, 'Shoes');
      expect(shoes?.includeInMenu, isFalse);
      expect(shoes?.children.map((c) => c.name), ['Women', 'Men', 'Archive']);
      expect(repo.categoryByUidCalls, ['NTM=']);
    });

    test('is null for a uid nobody has', () async {
      final repo = _catalog();
      final container = _container(repo);

      expect(
        await container.read(categoryByUidProvider('Tm9wZQ==').future),
        isNull,
      );
      expect(repo.categoryByUidCalls, ['Tm9wZQ==']);
    });

    test('a failed fetch is an error, not an empty category', () async {
      final container = _container(_FailingCatalog());

      await expectLater(
        container.read(categoryByUidProvider('NTM=').future),
        throwsA(isA<Failure>()),
      );
    });
  });

  group('categoryInTreeProvider', () {
    test('never makes a request: a category outside the tree is null', () async {
      final repo = _catalog();
      final container = _container(repo);

      expect(await container.read(categoryInTreeProvider('NTM=').future), isNull);
      expect(
        (await container.read(categoryInTreeProvider('NzQ=').future))?.name,
        'Furniture',
      );
      expect(repo.categoryByUidCalls, isEmpty);
    });
  });

  group('PlpController', () {
    test('does not hold the first page of products for the by-uid fetch', () async {
      // The default sort asks for the category's url key before the first page
      // is requested; a category outside the menu tree must not make that wait
      // for a request of its own (this one never answers).
      final repo = _ControlledCatalog();
      final container = _container(repo);

      await container
          .read(plpControllerProvider('NTM=').notifier)
          .refresh()
          .timeout(const Duration(seconds: 5));

      final state = container.read(plpControllerProvider('NTM='));
      expect(state.isLoading, isFalse);
      expect(state.products, isNotEmpty);
      expect(repo.categoryByUidCalls, isEmpty);
    });
  });

  group('the listing of a category outside the menu', () {
    testWidgets('shows its own title and only the sub-categories of the menu', (
      tester,
    ) async {
      _surface(tester);
      final repo = _catalog();
      await tester.pumpWidget(_app(repo, 'NTM='));
      await tester.pumpAndSettle();

      expect(_title('Shoes'), findsOneWidget);
      expect(_title('Categories'), findsNothing);
      // The rail: the two children of the menu; the hidden one stays out.
      expect(find.text('Women'), findsOneWidget);
      expect(find.text('Men'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      expect(repo.categoryByUidCalls, ['NTM=']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the generic title until the category has arrived', (
      tester,
    ) async {
      _surface(tester);
      final repo = _ControlledCatalog();
      await tester.pumpWidget(_app(repo, 'NTM='));
      await tester.pump(const Duration(milliseconds: 50));

      final generic = lookupAppLocalizations(const Locale('en')).navCategories;
      expect(_title(generic), findsOneWidget);
      expect(find.text('Women'), findsNothing);

      repo.answer.complete(_shoes);
      await tester.pumpAndSettle();

      expect(_title('Shoes'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a uid nobody has keeps the generic title and no rail', (
      tester,
    ) async {
      _surface(tester);
      final repo = _catalog();
      await tester.pumpWidget(_app(repo, 'Tm9wZQ=='));
      await tester.pumpAndSettle();

      final generic = lookupAppLocalizations(const Locale('en')).navCategories;
      expect(_title(generic), findsOneWidget);
      expect(find.text('Women'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a category of the menu does not ask for it again', (
      tester,
    ) async {
      _surface(tester);
      final repo = _catalog();
      await tester.pumpWidget(_app(repo, 'NzQ='));
      await tester.pumpAndSettle();

      expect(_title('Furniture'), findsOneWidget);
      expect(find.text('Home Furniture'), findsWidgets);
      expect(repo.categoryByUidCalls, isEmpty);
    });
  });
}
