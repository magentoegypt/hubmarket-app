import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/stores/presentation/screens/store_screen.dart';
import 'package:hubmarket_app/features/stores/presentation/screens/stores_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/search_fixtures.dart';
import '../../support/store_fixtures.dart';

/// The server of the stores screens' tests: the Figma sellers, MIA CO's page
/// and products, the best sellers. A featured-only list is MIA CO alone; a
/// name filters on the name or code, as the backend does.
Object Function(RecordedRequest) storesAnswers({String store = 'en'}) =>
    (request) => switch (request.operation) {
      'HmStores' when request.variables['featured'] == true => storesData([
        miaCard(store: store),
      ]),
      'HmStores' => storesData([
        for (final card in sampleStoreCards(store: store))
          if (_named(card, request.variables['name'] as String?)) card,
      ]),
      'HmStore' => miaStoreData(store: store),
      'HmStoreReviews' => miaReviewsData(store: store),
      'HmStoreCategories' => storeCategoriesData(store: store),
      'Products' => productsData(miaProducts(store: store), store: store),
      'HmBestSellers' => bestSellersData(store: store),
      _ => Exception('offline (test): ${request.operation}'),
    };

bool _named(Map<String, dynamic> card, String? name) {
  final needle = name?.trim().toLowerCase() ?? '';
  return needle.isEmpty ||
      (card['name'] as String).toLowerCase().contains(needle) ||
      (card['code'] as String).toLowerCase().contains(needle);
}

/// A phone-sized surface, so lists and sheets lay out as on a device.
Future<void> phoneSurface(WidgetTester tester, {double height = 844}) async {
  await tester.binding.setSurfaceSize(Size(390, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// The stores screens behind a router with stand-ins for everything they
/// open, on [backend] (the public GET client) with the Hub Market App in
/// [hubApp]'s state.
Widget storesHarness({
  required String location,
  required FakeStoresBackend backend,
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  String locale = 'en',
  Object? extra,
  GlobalKey? boundary,
  ({String type, String uid, String? urlKey})? resolved,
  List<Override> overrides = const <Override>[],
}) {
  Widget stub(String text) => Scaffold(
    appBar: AppBar(),
    body: Center(child: Text(text)),
  );
  final router = GoRouter(
    initialLocation: location,
    initialExtra: extra,
    routes: [
      GoRoute(path: '/stores', builder: (_, __) => const StoresScreen()),
      GoRoute(
        path: '/store/:code',
        builder: (_, state) => StoreScreen(
          code: state.pathParameters['code']!,
          preview: state.extra is HmStoreCard
              ? state.extra! as HmStoreCard
              : null,
        ),
      ),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) => stub('PDP ${state.pathParameters['urlKey']}'),
      ),
      GoRoute(path: '/search', builder: (_, __) => stub('SEARCH')),
      GoRoute(
        path: '/page',
        builder: (_, state) => stub('CMS ${state.uri.queryParameters['url']}'),
      ),
      for (final path in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
      ])
        GoRoute(path: path, builder: (_, __) => stub(path)),
    ],
  );
  final app = MaterialApp.router(
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
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(
          categories: locale == 'ar' ? kSearchTreeAr : kSearchTree,
          resolved: resolved,
        ),
      ),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      publicGraphqlClientProvider.overrideWithValue(backend.client),
      ...overrides,
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}
