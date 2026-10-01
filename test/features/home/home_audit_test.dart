import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/home/data/home_content_repository.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_view.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/home_active_order.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';
import 'package:intl/intl.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import 'hm_home_fixtures.dart';

/// UI audit of the Home against Figma 07 / AR-07: both Homes, whole page, in
/// both languages, signed in with an open order, an unread notification and
/// recent searches (everything the frame draws), captured as
/// `home_hubapp_<locale>` (Build 2) and `home_<locale>` (Build 1) for
/// `tool/ui_audit/pairs.py`. Run with `--dart-define=UI_AUDIT=true`.
///
/// Next to each capture it writes where every section sits
/// (`build/ui_audit/home_rects_<capture>.json`), so a section can be cut out of
/// the render and laid next to the same section of the frame.

/// The page is taller than the 6313 / 6427 px of the frames only when something
/// was added to it, so the viewport is a little taller than either.
const double _kViewportHeight = 7600;

/// Live CMS markup of the Build 1 blocks (hub-market.magento2.click, 1 Oct 2026).
const _build1Blocks = <String, String>{
  HomeCmsBlocks.deliveryPromise:
      '<p>Free delivery on qualifying orders &middot; Fast nationwide shipping</p>',
  HomeCmsBlocks.promos:
      '<div class="hm-promos">'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/electronics.html/"><span class="hm-promo__icon">⚡</span><span class="hm-promo__kicker">Flash Sale</span><span class="hm-promo__title">Up to 50% Off Electronics &amp; Tech</span><span class="hm-promo__text">Today only</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/super-market.html/"><span class="hm-promo__icon">🌙</span><span class="hm-promo__kicker">Seasonal Offers</span><span class="hm-promo__title">Fresh Grocery Deals</span><span class="hm-promo__text">Same-day delivery &middot; Free over AED 150</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/all.html/"><span class="hm-promo__icon">💳</span><span class="hm-promo__kicker">Buy Now Pay Later</span><span class="hm-promo__title">Split in 4 with Tabby</span><span class="hm-promo__text">0% interest &middot; Instant approval</span></a>'
      '</div>',
  HomeCmsBlocks.trust:
      '<div class="hm-trust">'
      '<div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers</span><span class="hm-trust__text">Verified &amp; approved</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Secure Payments</span><span class="hm-trust__text">Cards, cash on delivery, Tabby &amp; Tamara</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Fast Delivery</span><span class="hm-trust__text">Across all seven emirates</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Easy Returns</span><span class="hm-trust__text">14-day return policy</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">WhatsApp Support</span><span class="hm-trust__text">24/7 customer care</span></div>'
      '</div>',
};

const _build1Categories = <Category>[
  Category(uid: 'Mw==', name: 'Grocery', urlKey: 'super-market', productCount: 7),
  Category(uid: 'NA==', name: 'Pharmacy', urlKey: 'pharmacy', productCount: 8),
  Category(uid: 'NQ==', name: 'Furniture', urlKey: 'furniture', productCount: 7),
  Category(uid: 'Ng==', name: 'Fashion', urlKey: 'clothes', productCount: 19),
  Category(uid: 'Nw==', name: 'FMCG', urlKey: 'fmcg', productCount: 5),
];

Product _p(String name, double price, [double? was, double? rating]) => Product(
  sku: name,
  name: name,
  urlKey: name.toLowerCase().replaceAll(' ', '-'),
  brand: 'MIA CO',
  regularPrice: Money(amount: was ?? price, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
  ratingSummary: rating == null ? null : rating * 20,
  reviewCount: rating == null ? null : 3,
);

final _build1Rail = <Product>[
  _p('Corner Sofa Bed', 425, 500, 4.7),
  _p('3-Piece Living Room Set', 255, 300),
  _p('Dining Table Set 6 Seats', 340, 400),
  _p('Oak Bookshelf', 190, 220),
];

CustomerOrder _openOrder() => CustomerOrder(
  number: '000000248',
  status: 'Processing',
  date: DateFormat('yyyy-MM-dd HH:mm:ss').format(
    DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(hours: 12)).subtract(const Duration(days: 1)),
  ),
  id: 'id-248',
  total: const Money(amount: 553, currency: 'AED'),
  lines: const [
    OrderLine(name: 'Line 0', quantity: 1),
    OrderLine(name: 'Line 1', quantity: 1),
  ],
);

Widget _app({
  required String locale,
  required GlobalKey boundary,
  required bool hubApp,
  required FakeLocalCache cache,
}) {
  Widget stub(BuildContext context, GoRouterState state) =>
      Scaffold(appBar: AppBar(), body: Text('route ${state.uri}'));
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
        '/category/:uid',
        '/product/:urlKey',
        '/brand/:urlKey',
        '/store/:code',
        '/order',
        '/order-tracking',
      ])
        GoRoute(path: p, builder: stub),
    ],
  );
  final countdown = DateTime.now().add(
    const Duration(days: 2, hours: 14, minutes: 32, seconds: 19),
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore('persisted'),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(
        FakeAccountRepository(orders: [_openOrder()]),
      ),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      hubAppOverride(
        hubApp
            // No search hint of its own: the field then says what the frame does.
            ? HubAppState.available(HmAppConfig(storeCode: locale))
            : const HubAppState.unavailable(),
      ),
      hmHomeProvider.overrideWith(
        (ref) async => hubApp
            ? hmHomeFromJson(
                hmAuditHomeJson(countdown: countdown, arabic: locale == 'ar'),
              )
            : null,
      ),
      homeCmsBlocksProvider.overrideWith((ref) async => _build1Blocks),
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

/// Where [finder] sits in the capture: `[left, top, width, height]`.
List<double> _rect(WidgetTester tester, Finder finder) {
  final r = tester.getRect(finder.first);
  return [r.left, r.top, r.width, r.height];
}

/// `captureScreen` that precaches the asset images only (the logo): the
/// original asks the network image cache for every `Image` in real time and
/// never returns for the audit's thumbnail URLs, which only need to show their
/// placeholder tint.
Future<void> _writeCapture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = (element.widget as Image).image;
      final source = image is ResizeImage ? image.imageProvider : image;
      if (source is AssetImage || source is ExactAssetImage) {
        await precacheImage(image, element);
      }
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _capture(
  WidgetTester tester, {
  required String locale,
  required bool hubApp,
}) async {
  NotificationInbox.instance.items.value = [
    NotificationItem(
      id: 'n1',
      kind: NotificationKind.order,
      title: 'Your order shipped',
      body: '',
      receivedAt: DateTime.now(),
    ),
  ];
  addTearDown(() => NotificationInbox.instance.items.value = const []);
  // "YOUR SEARCHES": the customer's own recent searches, newest first.
  final cache = FakeLocalCache();
  await cache.writeString(
    'search_history',
    jsonEncode(['bag', 'shirt', 'dress', 'women']),
  );

  tester.view.physicalSize = const Size(390, _kViewportHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    _app(locale: locale, boundary: key, hubApp: hubApp, cache: cache),
  );
  await tester.pumpAndSettle();

  final name = hubApp ? 'home_hubapp_$locale' : 'home_$locale';
  await _writeCapture(tester, key, name);

  // Where everything sits, for tool-side alignment with the frame.
  final rects = <String, Object?>{
    'viewport': [390.0, _kViewportHeight],
    'sections': <String, Object?>{},
  };
  final sections = rects['sections']! as Map<String, Object?>;
  if (hubApp) {
    final json = hmAuditHomeJson(countdown: DateTime.now(), arabic: false);
    for (final s in (json['sections'] as List).cast<Map<String, dynamic>>()) {
      final item = find.byKey(ValueKey('hm-section-${s['id']}-${s['type']}'));
      // Every section of the audit dataset is drawn.
      expect(item, findsOneWidget, reason: 'section ${s['id']} ${s['type']}');
      sections['${s['id']}'] = {
        'type': s['type'],
        'rect': _rect(tester, find.descendant(of: item, matching: find.byType(HmSectionView))),
      };
    }
    final card = find.byType(ActiveOrderCard);
    if (card.evaluate().isNotEmpty) {
      sections['active'] = {'type': 'ACTIVE_ORDER', 'rect': _rect(tester, card)};
    }
  }
  File('build/ui_audit/home_rects_$name.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rects));

  expect(tester.takeException(), isNull);

  // Let the timers the decoded logo left behind run out.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(loadAppFonts);

  // The bundle thumbnails are network images: give the image cache a temporary
  // folder so a load attempt fails quietly (HTTP is stubbed to 400 in widget
  // tests) instead of on a missing plugin.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.createTempSync('hm_audit').path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  for (final locale in const ['en', 'ar']) {
    testWidgets('Build 2 Home, the whole page ($locale)', (tester) async {
      await _capture(tester, locale: locale, hubApp: true);
    });

    testWidgets('Build 1 Home, the whole page ($locale)', (tester) async {
      await _capture(tester, locale: locale, hubApp: false);
    });
  }
}
