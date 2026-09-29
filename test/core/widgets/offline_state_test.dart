import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/shell/hub_scaffold.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/network/connectivity.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/async_value_view.dart';
import 'package:hubmarket_app/core/widgets/offline_state.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';

/// The OS network state, driven by the test.
class _Network {
  _Network(this.online);

  bool online;
  int checks = 0;
  final _changes = StreamController<bool>.broadcast();

  Stream<bool> watch() async* {
    checks++;
    yield online;
    yield* _changes.stream;
  }

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  Override get override => networkStatusSourceProvider.overrideWithValue(watch);
}

Widget _app({
  required _Network network,
  required GoRouter router,
  String locale = 'en',
  List<Override> overrides = const [],
  GlobalKey? boundary,
}) {
  final app = MaterialApp.router(
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: AppTheme.light(locale),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    // As in HubApp: the strip is installed around the navigator.
    builder: (context, child) => OfflineBannerHost(child: child!),
  );
  return ProviderScope(
    overrides: [
      network.override,
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      ...overrides,
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// A screen whose content failed to load with [error].
Widget _failed(Object error, VoidCallback onRetry) => Scaffold(
  body: AsyncValueView<int>(
    value: AsyncValue<int>.error(error, StackTrace.empty),
    data: (_) => const Text('DATA'),
    onRetry: onRetry,
  ),
);

GoRouter _router(Widget Function() page) => GoRouter(
  initialLocation: '/page',
  routes: [GoRoute(path: '/page', builder: (_, _) => page())],
);

/// Products never arrive: the request did not reach the store.
class _OfflineCatalog extends FakeCatalogRepository {
  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? manufacturerId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async => throw const Failure(FailureKind.network, detail: 'offline');
}

GoRouter _plpRouter(String title) => GoRouter(
  initialLocation: AppRoutes.category('cat-furniture'),
  routes: [
    GoRoute(
      path: '/category/:uid',
      builder: (_, state) =>
          PlpScreen(categoryUid: state.pathParameters['uid']!, title: title),
    ),
    for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account'])
      GoRoute(path: p, builder: (_, _) => const Scaffold()),
    GoRoute(path: '/product/:urlKey', builder: (_, _) => const Scaffold()),
  ],
);

void main() {
  group('S3 offline state (AsyncValueView)', () {
    testWidgets('a request that never reached the store shows S3 with Try again',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _app(
          network: _Network(true),
          router: _router(
            () => _failed(
              const Failure(FailureKind.network, detail: 'SocketException'),
              () => retries++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You’re offline'), findsOneWidget);
      expect(
        find.text(
          'Check your Wi-Fi or mobile data. Your cart is saved on this device.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "We couldn't reach the store. Check your connection and try again.",
        ),
        findsNothing,
      );
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('other failures keep their message while the network is up', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          network: _Network(true),
          router: _router(
            () => _failed(
              const Failure(FailureKind.service, detail: 'HTTP 503'),
              () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You’re offline'), findsNothing);
      expect(
        find.text('The store is temporarily unavailable. Please try again shortly.'),
        findsOneWidget,
      );
    });

    testWidgets('any failure reads as offline while the OS has no network', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          network: _Network(false),
          router: _router(
            () => _failed(const Failure(FailureKind.unknown), () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('You’re offline'), findsOneWidget);
    });

    testWidgets('it retries by itself when the network comes back', (
      tester,
    ) async {
      var retries = 0;
      final network = _Network(false);
      await tester.pumpWidget(
        _app(
          network: network,
          router: _router(
            () => _failed(const Failure(FailureKind.network), () => retries++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(retries, 0);

      network.set(true);
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets('Arabic', (tester) async {
      await tester.pumpWidget(
        _app(
          locale: 'ar',
          network: _Network(false),
          router: _router(
            () => _failed(const Failure(FailureKind.network), () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('أنت غير متصل'), findsOneWidget);
      expect(find.text('حاول مجددًا'), findsOneWidget);
      expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    });
  });

  group('S3 "No internet connection" strip', () {
    testWidgets('appears app-wide while offline and goes when the network is back',
        (tester) async {
      final network = _Network(true);
      await tester.pumpWidget(
        _app(
          network: network,
          router: _router(() => const Scaffold(body: Text('PLAIN'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsNothing);

      network.set(false);
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsOneWidget);
      // Under the page, not over it.
      expect(
        tester.getBottomLeft(find.text('PLAIN')).dy,
        lessThan(tester.getTopLeft(find.byType(OfflineBanner)).dy),
      );

      network.set(true);
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsNothing);
    });

    testWidgets('Retry asks the OS again', (tester) async {
      final network = _Network(false);
      await tester.pumpWidget(
        _app(
          network: network,
          router: _router(() => const Scaffold(body: Text('PLAIN'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(network.checks, 1);

      network.online = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(network.checks, 2);
      expect(find.text('No internet connection'), findsNothing);
    });

    testWidgets('screens with the tab bar show it once, right above the tabs',
        (tester) async {
      final network = _Network(false);
      await tester.pumpWidget(
        _app(
          network: network,
          router: _router(
            () => const HubScaffold(
              currentTab: AppTab.categories,
              body: Text('TABBED'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBanner), findsOneWidget);
      final banner = tester.getRect(find.byType(OfflineBanner));
      final tabs = tester.getRect(find.text('Categories').last);
      expect(banner.bottom, lessThanOrEqualTo(tabs.top));
    });
  });

  group('S3 render', () {
    setUpAll(loadAppFonts);

    for (final locale in ['en', 'ar']) {
      testWidgets('on the product list, as the frame [$locale]', (
        tester,
      ) async {
        await withRealShadows(() async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          await tester.pumpWidget(
            _app(
              locale: locale,
              network: _Network(false),
              router: _plpRouter(locale == 'ar' ? 'أثاث منزلي' : 'Home Furniture'),
              overrides: [
                catalogRepositoryProvider.overrideWithValue(_OfflineCatalog()),
              ],
              boundary: key,
            ),
          );
          await tester.pumpAndSettle();
          await captureScreen(tester, key, 'S3_offline_$locale');

          expect(find.byType(OfflineState), findsOneWidget);
          expect(find.byType(OfflineBanner), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  });
}
