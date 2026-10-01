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
import 'package:hubmarket_app/core/network/connectivity.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/shimmer.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/categories_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/store_fixtures.dart';

/// The Categories tab (Figma 08 / AR 48:1442): the rail, and for the category
/// picked its banner, "Shop by type" tiles and "Top stores in …".
///
/// Renders to `build/test_screens/audit_08_categories_<locale>.png` for
/// comparison with the frame (network photos are not available in tests: the
/// banner shows its navy, the tiles their icons, the logos their initials).

Category _category(
  int id,
  String key,
  String en,
  String ar, {
  String locale = 'en',
  int count = 20,
  List<Category> children = const <Category>[],
}) => Category(
  uid: categoryUidFromId('$id'),
  name: locale == 'ar' ? ar : en,
  urlKey: key,
  productCount: count,
  children: children,
);

/// The rail of the frame: Furniture's branch is the live one (ids 74–77).
List<Category> _tree(String locale) {
  Category c(int id, String key, String en, String ar, {int count = 5}) =>
      _category(id, key, en, ar, locale: locale, count: count);
  return [
    c(12, 'super-market', 'Grocery', 'سوبر ماركت'),
    _category(
      74,
      'furniture',
      'Furniture',
      'أثاث',
      locale: locale,
      count: 214,
      children: [
        c(75, 'home-furniture', 'Home Furniture', 'أثاث منزلي'),
        c(76, 'office-furniture', 'Office Furniture', 'أثاث مكتبي'),
        c(77, 'living-room-sets', 'Living Room Sets', 'أطقم غرف المعيشة'),
        c(78, 'dining-chairs', 'Dining Chairs', 'كراسي طعام'),
        c(79, 'rocking-chairs', 'Rocking Chairs', 'كراسي هزازة'),
      ],
    ),
    c(11, 'pharmacy', 'Pharmacy', 'صيدلية'),
    c(14, 'clothes', 'Fashion', 'أزياء'),
    c(15, 'fmcg', 'FMCG', 'سلع استهلاكية'),
    c(17, 'games', 'Kids & Toys', 'الأطفال والألعاب'),
    c(18, 'health', 'Cosmetics', 'مستحضرات التجميل'),
    c(21, 'electronics', 'Electronics & Tech', 'إلكترونيات وتقنية'),
  ];
}

/// `hmStores` for a category: its two best sellers, of six.
Object Function(RecordedRequest) _stores(String locale) =>
    (request) => switch (request.operation) {
      'HmStores' => storesData([
        miaCard(store: locale),
        storeCardJson(
          code: 'ENARA',
          id: 9,
          name: 'ENARA',
          rating: 4.9,
          reviews: 19,
          products: 19,
          store: locale,
        ),
      ], total: 6),
      _ => Exception('offline (test): ${request.operation}'),
    };

Widget _harness(
  GlobalKey boundary, {
  required String locale,
  bool hubApp = true,
  List<Category>? tree,
  CatalogRepository? catalog,
  String location = '/categories',
  List<Override> overrides = const <Override>[],
  void Function(String location)? onOpen,
}) {
  Widget stub(String text) => Scaffold(
    appBar: AppBar(),
    body: Center(child: Text(text)),
  );
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/categories',
        builder: (_, __) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/subcategories/:uid',
        builder: (_, state) => SubcategoriesScreen(
          categoryUid: state.pathParameters['uid']!,
          title: 'Sub',
        ),
      ),
      GoRoute(
        path: '/category/:uid',
        builder: (_, state) {
          onOpen?.call(state.uri.toString());
          return stub('PLP ${state.extra}');
        },
      ),
      GoRoute(path: '/search', builder: (_, __) => stub('SEARCH')),
      GoRoute(path: '/bundles', builder: (_, __) => stub('BUNDLES')),
      GoRoute(
        path: '/store/:code',
        builder: (_, state) => stub('STORE ${state.pathParameters['code']}'),
      ),
      for (final p in ['/home', '/cart', '/wishlist', '/account'])
        GoRoute(path: p, builder: (_, __) => stub(p)),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(
        catalog ?? FakeCatalogRepository(categories: tree ?? _tree(locale)),
      ),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(
        hubApp
            ? const HubAppState.available(kVendorsHmAppConfig)
            : const HubAppState.unavailable(),
      ),
      publicGraphqlClientProvider.overrideWithValue(
        FakeStoresBackend(_stores(locale)).client,
      ),
      ...overrides,
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(locale),
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('08 Categories renders in $locale', (tester) async {
      _phone(tester);
      final key = GlobalKey();
      await withRealShadows(() async {
        await tester.pumpWidget(_harness(key, locale: locale));
        await tester.pumpAndSettle();
        // The frame has Furniture picked.
        await tester.tap(
          find.text(locale == 'ar' ? 'أثاث' : 'Furniture').first,
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'audit_08_categories_$locale');
      });

      // The banner's counts, the tiles, the stores.
      expect(
        find.text(
          '${l10n.categoryProductCount(214)} · ${l10n.categoryStoreCount(6)}',
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.categoryShopByType), findsOneWidget);
      expect(find.byType(TypeTile), findsNWidgets(5));
      expect(
        find.text(l10n.categoryTopStores(_tree(locale)[1].name)),
        findsOneWidget,
      );
      expect(find.text('ENARA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the first category is picked until another is', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_harness(GlobalKey(), locale: 'en'));
    await tester.pumpAndSettle();

    // Grocery has no sub-categories: its banner, no tiles.
    expect(find.byType(TypeTile), findsNothing);
    expect(find.text('Shop by type'), findsNothing);

    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();
    expect(find.byType(TypeTile), findsNWidgets(5));
    expect(find.text('Top stores in Furniture'), findsOneWidget);
    // Tapping a store opens it.
    await tester.tap(find.text('MIA CO'));
    await tester.pumpAndSettle();
    expect(find.text('STORE MIA'), findsOneWidget);
  });

  testWidgets('a tile and the banner open a listing', (tester) async {
    _phone(tester);
    final opened = <String>[];
    await tester.pumpWidget(
      _harness(GlobalKey(), locale: 'en', onOpen: opened.add),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dining Chairs'));
    await tester.pumpAndSettle();
    expect(find.text('PLP Dining Chairs'), findsOneWidget);
    expect(opened.single, '/category/${categoryUidFromId('78')}');

    // Back, then the banner opens Furniture itself.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-banner')));
    await tester.pumpAndSettle();
    expect(find.text('PLP Furniture'), findsOneWidget);
    expect(opened.last, '/category/${categoryUidFromId('74')}');
  });

  testWidgets('without the Hub Market App: no Bundle Deals, no stores', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_harness(GlobalKey(), locale: 'en', hubApp: false));
    await tester.pumpAndSettle();
    expect(find.text('Bundle Deals'), findsNothing);
    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();
    // Furniture's banner counts only its products, and no stores are listed.
    expect(find.text('214 products'), findsOneWidget);
    expect(find.textContaining('Top stores'), findsNothing);
    expect(find.byType(TypeTile), findsNWidgets(5));
  });

  testWidgets('with the Hub Market App the rail ends with Bundle Deals', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_harness(GlobalKey(), locale: 'en'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bundle Deals'));
    await tester.pumpAndSettle();
    expect(find.text('BUNDLES'), findsOneWidget);
  });

  testWidgets('loading shows the page\'s skeleton, in its place', (
    tester,
  ) async {
    _phone(tester);
    final key = GlobalKey();
    final tree = Completer<List<Category>>();
    await tester.pumpWidget(
      _harness(key, locale: 'en', catalog: _SlowCatalog(tree.future)),
    );
    await tester.pump();
    await captureScreen(tester, key, 'audit_08_categories_loading_en');
    // The rail's and the panel's.
    expect(find.byType(Shimmer), findsNWidgets(2));
    expect(find.byType(TypeTile), findsNothing);

    tree.complete(_tree('en'));
    await tester.pumpAndSettle();
    expect(find.byType(Shimmer), findsNothing);
    // Grocery is picked: it is the rail's row and the banner's name.
    expect(find.text('Grocery'), findsNWidgets(2));
  });

  testWidgets('a failed read says so and offers Retry', (tester) async {
    _phone(tester);
    final tree = Completer<List<Category>>();
    await tester.pumpWidget(
      _harness(
        GlobalKey(),
        locale: 'en',
        catalog: _SlowCatalog(tree.future),
        overrides: [isOfflineProvider.overrideWithValue(false)],
      ),
    );
    await tester.pump();
    tree.completeError(const Failure(FailureKind.server));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the sub-category route lists the tiles of the category', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _harness(
        GlobalKey(),
        locale: 'en',
        location: '/subcategories/${categoryUidFromId('74')}',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TypeTile), findsNWidgets(5));
    expect(find.text('Furniture'), findsOneWidget);
    await tester.tap(find.text('Rocking Chairs'));
    await tester.pumpAndSettle();
    expect(find.text('PLP Rocking Chairs'), findsOneWidget);
  });
}

/// A catalogue whose category tree arrives when the test says.
class _SlowCatalog extends FakeCatalogRepository {
  _SlowCatalog(this.tree);

  final Future<List<Category>> tree;

  @override
  Future<List<Category>> fetchCategoryTree() => tree;
}
