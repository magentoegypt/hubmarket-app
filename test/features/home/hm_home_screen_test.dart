import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show GraphQLError, Response;
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/home/data/home_content_repository.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import 'hm_home_fixtures.dart';

/// The Build 1 sources, for the fallback cases.
const _build1Categories = <Category>[
  Category(
    uid: 'Mw==',
    name: 'Super Market',
    urlKey: 'super-market',
    productCount: 7,
  ),
  Category(
    uid: 'NQ==',
    name: 'Furniture',
    urlKey: 'furniture',
    productCount: 7,
  ),
];

final _build1Rail = <Product>[
  const Product(
    sku: 'sofa',
    name: 'Corner Sofa Bed',
    urlKey: 'corner-sofa-bed',
    regularPrice: Money(amount: 500, currency: 'AED'),
    finalPrice: Money(amount: 425, currency: 'AED'),
  ),
];

/// Where the Home navigated to.
final _visited = <String>[];

Widget _harness({
  required String locale,
  required GlobalKey boundary,
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  Future<HmHome?> Function()? home,
}) {
  _visited.clear();
  Widget stub(BuildContext context, GoRouterState state) {
    _visited.add(state.uri.toString());
    return Scaffold(appBar: AppBar(), body: Text('route ${state.uri}'));
  }

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HubHomeScreen()),
      for (final p in [
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
        '/search',
        '/notifications',
        '/addresses',
        '/deals',
        '/bundles',
        '/brands',
        '/stores',
        '/orders',
        '/track-order',
        '/page',
      ])
        GoRoute(path: p, builder: stub),
      for (final p in [
        '/category/:uid',
        '/product/:urlKey',
        '/brand/:urlKey',
        '/store/:code',
      ])
        GoRoute(path: p, builder: stub),
    ],
  );
  final countdown = DateTime.now().add(
    const Duration(days: 2, hours: 14, minutes: 32, seconds: 19),
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      hmHomeProvider.overrideWith(
        (ref) =>
            home?.call() ??
            Future.value(
              hmHomeFromJson(
                hmHomeJson(countdown: countdown, arabic: locale == 'ar'),
              ),
            ),
      ),
      // Build 1 sources, for the fallback.
      homeCmsBlocksProvider.overrideWith(
        (ref) async => const {
          HomeCmsBlocks.deliveryPromise: '<p>Build 1 promise</p>',
          HomeCmsBlocks.trust: kTrustHtml,
        },
      ),
      homeCategoriesProvider.overrideWith((ref) async => _build1Categories),
      categoryThumbnailsProvider.overrideWith(
        (ref, key) async => const <String, String>{},
      ),
      homeCategoryRailProvider.overrideWith((ref, uid) async => _build1Rail),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
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
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(390, 5200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('Home from hmAppHome (Build 2)', () {
    testWidgets('draws every section type in the admin order (EN)', (
      tester,
    ) async {
      final key = GlobalKey();
      await _pump(tester, _harness(locale: 'en', boundary: key));

      for (final text in [
        'Free delivery on qualifying orders', // DELIVERY_STRIP
        'Track order',
        'Fresh Groceries From Local Vendors', // HERO_BANNERS slide
        'SAME-DAY DELIVERY',
        'Shop Grocery',
        'Electronics Deals', // HERO_BANNERS tile
        '🎁 This week only',
        'Shop by category', // CATEGORY_CHIPS
        '🛒',
        '19+ items',
        "Today's Deals", // TODAYS_DEALS
        'All Deals',
        'remaining',
        'Egyptian Rice 1 kg',
        'Picked For You', // PICKED_FOR_YOU
        'Featured Stores', // FEATURED_STORES
        'ENARA',
        'Visit Store',
        'Grocery Essentials', // CATEGORY_RAIL
        'Fresh & delivered today',
        'Home Fitness Starter Pack', // BUNDLE_DEALS
        '-16% Bundle',
        'Add Bundle',
        'Up to 50% Off Electronics & Tech', // CMS_PROMOS
        'Best Selling Items', // BEST_SELLERS
        '#1 Best seller',
        '#2',
        'Joust Duffle Bag', // POPULAR_PRODUCTS (header hidden)
        'Top Brands on Hub Market', // TOP_BRANDS
        'Samsung',
        'Top Vendors This Month', // TOP_VENDORS
        '#1 VENDOR',
        'New Stores on Hub Market', // NEW_STORES
        'Test Dev8',
        'Trusted Sellers', // TRUST_ROW
        'Sell on Hub Market', // CMS_BLOCK
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      // Picked For You is top-rated products: no "AI" badge (QA02).
      expect(find.text('AI ENGINE'), findsNothing);
      // The countdown, days and clock.
      expect(find.text('2d'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^14:3\d:\d\d$')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders right-to-left in Arabic without overflow', (
      tester,
    ) async {
      final key = GlobalKey();
      await _pump(
        tester,
        _harness(
          locale: 'ar',
          boundary: key,
          hubApp: const HubAppState.available(
            HmAppConfig(
              storeCode: 'ar',
              search: HmSearchConfig(hint: 'ابحث في هب ماركت'),
            ),
          ),
        ),
      );
      expect(find.text('ابحث في هب ماركت'), findsOneWidget);

      expect(find.text('بقالة طازجة من بائعين محليين'), findsOneWidget);
      expect(find.text('عروض اليوم'), findsOneWidget);
      expect(find.text('كل العروض'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(HubHomeScreen))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty, ended, unknown and "-"-titled sections', (
      tester,
    ) async {
      await _pump(tester, _harness(locale: 'en', boundary: GlobalKey()));

      // A rail the backend emptied is not drawn, header included.
      expect(find.text('Empty Rail'), findsNothing);
      // Past its ends_at.
      expect(find.text('Ended Campaign'), findsNothing);
      expect(find.text('Old Promo'), findsNothing);
      // Unknown type.
      expect(find.text('Flash sale'), findsNothing);
      // "-": no header, the products still show.
      expect(find.text('-'), findsNothing);
      expect(find.text('Popular Products'), findsNothing);
      expect(find.text('Joust Duffle Bag'), findsOneWidget);
      // No Build 1 source was asked for.
      expect(find.text('Build 1 promise'), findsNothing);
    });

    testWidgets('"View all", slides and chips route natively', (tester) async {
      await _pump(tester, _harness(locale: 'en', boundary: GlobalKey()));

      await tester.tap(find.text('All Deals'));
      await tester.pumpAndSettle();
      expect(_visited.last, '/deals');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Shop Grocery'));
      await tester.pumpAndSettle();
      expect(_visited.last, '/category/Mw==');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('ENARA'));
      await tester.pumpAndSettle();
      expect(_visited.last, '/store/ENARA');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('All Bundles'));
      await tester.pumpAndSettle();
      expect(_visited.last, '/bundles');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Samsung'));
      await tester.pumpAndSettle();
      expect(_visited.last, '/brand/samsung');
    });
  });

  group('Build 1 fallback', () {
    testWidgets('an hmAppHome failure shows the Build 1 Home, rails and all', (
      tester,
    ) async {
      await _pump(
        tester,
        _harness(
          locale: 'en',
          boundary: GlobalKey(),
          home: () async => throw const Failure(
            FailureKind.server,
            detail: 'Could not read the Home sections.',
          ),
        ),
        size: const Size(390, 2400),
      );

      expect(find.text('Build 1 promise'), findsOneWidget);
      expect(find.text('Shop by category'), findsOneWidget);
      expect(find.text('Corner Sofa Bed'), findsWidgets); // lazy rails
      expect(find.text('Fresh Groceries From Local Vendors'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an hmAppHome with nothing to draw shows Build 1, not a blank',
      (tester) async {
        await _pump(
          tester,
          _harness(
            locale: 'en',
            boundary: GlobalKey(),
            home: () async => hmHomeFromJson({
              'store_code': 'en',
              'generated_at': '2026-09-30T06:00:00Z',
              'sections': [
                {
                  'id': 1,
                  'type': 'BEST_SELLERS',
                  'title': 'Best',
                  'products': [],
                },
              ],
            }),
          ),
          size: const Size(390, 2400),
        );

        expect(find.text('Build 1 promise'), findsOneWidget);
        expect(find.text('Corner Sofa Bed'), findsWidgets);
        expect(find.text('Best'), findsNothing);
      },
    );

    for (final state in const [
      HubAppState.unavailable(),
      HubAppState.unknown(),
    ]) {
      testWidgets('HubApp ${state.status.name}: the Build 1 Home', (
        tester,
      ) async {
        await _pump(
          tester,
          _harness(locale: 'en', boundary: GlobalKey(), hubApp: state),
          size: const Size(390, 2400),
        );
        expect(find.text('Build 1 promise'), findsOneWidget);
        expect(find.text('Fresh Groceries From Local Vendors'), findsNothing);
      });
    }
  });

  group('HmHomeRepository', () {
    test('the audience goes inline and the document fits in a URL', () {
      final guest = HmHomeRepository.documentFor(HmAudience.guest);
      final customer = HmHomeRepository.documentFor(HmAudience.customer);
      expect(guest, contains('hmAppHome(audience: GUEST)'));
      expect(customer, contains('hmAppHome(audience: CUSTOMER)'));
      expect(guest, isNot(contains(r'$')));

      final url = Uri.parse('https://hub-market.magento2.click/graphql')
          .replace(
            queryParameters: {
              'operationName': 'HmAppHome',
              'query': compactGraphQLDocument(customer),
            },
          );
      // nginx's default request line is 8 KB; the contract asks for < ~6 KB.
      expect(url.toString().length, lessThan(6000));
    });

    test(
      'a failed read is a Failure, a missing module HubAppMissing',
      () async {
        Future<Object?> read(Map<String, Object> answers) async {
          try {
            await HmHomeRepository(
              fakeHubAppClient(answers),
            ).fetchHome(HmAudience.guest);
            return null;
          } on Object catch (error) {
            return error;
          }
        }

        expect(
          await read({'HmAppHome': hubAppMissingResponse('hmAppHome')}),
          isA<HubAppMissing>(),
        );
        expect(
          await read({
            'HmAppHome': Response(
              errors: const [
                GraphQLError(message: 'Could not read the Home sections.'),
              ],
              response: const <String, dynamic>{},
            ),
          }),
          isA<Failure>(),
        );
      },
    );

    test('parses sections, dropping unreadable items', () {
      final home = hmHomeFromJson(
        hmHomeJson(countdown: DateTime.utc(2026, 10, 1, 20)),
      );
      final byType = {for (final s in home.sections) s.id: s};
      expect(home.storeCode, 'en');
      expect(byType[2]!.slides, hasLength(2));
      expect(byType[2]!.tiles, hasLength(2));
      expect(byType[2]!.slides.first.tone, const Color(0xFF123620));
      expect(byType[3]!.categories.map((c) => c.icon), contains('🛒'));
      expect(byType[4]!.countdownEndsAt, DateTime.utc(2026, 10, 1, 20));
      expect(byType[6]!.stores.first.dispatchTime!.label, '24h');
      expect(byType[9]!.bundles.single.hasSaving, isTrue);
      expect(byType[12]!.title, isNull); // "-"
      expect(byType[13]!.brands.first.optionId, 220);
      expect(byType[19]!.type, HmSectionType.unknown);
      final visible = home.visibleSections(DateTime.utc(2026, 9, 30));
      expect(visible.map((s) => s.id), isNot(containsAll([8, 18, 19])));
    });
  });
}
