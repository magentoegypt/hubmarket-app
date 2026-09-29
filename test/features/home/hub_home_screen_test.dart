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
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/home/data/home_content_repository.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

// Live CMS markup (hub-market.magento2.click, store `en`, 29 Sep 2026).
const _cms = <String, String>{
  HomeCmsBlocks.deliveryPromise:
      '<p>Free delivery on qualifying orders &middot; Fast nationwide shipping</p>',
  HomeCmsBlocks.promos:
      '<div class="hm-promos"><a class="hm-promo" href="https://hub-market.magento2.click/en/electronics.html/"><span class="hm-promo__icon">⚡</span><span class="hm-promo__kicker">Flash Sale</span><span class="hm-promo__title">Up to 50% Off</span><span class="hm-promo__text">Electronics &amp; Tech &middot; Today only</span></a><a class="hm-promo" href="https://hub-market.magento2.click/en/super-market.html/"><span class="hm-promo__icon">🌙</span><span class="hm-promo__kicker">Seasonal Offers</span><span class="hm-promo__title">Fresh Grocery Deals</span><span class="hm-promo__text">Same-day delivery &middot; Free over AED 150</span></a></div>',
  HomeCmsBlocks.trust:
      '<div class="hm-trust"><div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers</span><span class="hm-trust__text">Verified &amp; approved</span></div><div class="hm-trust__item"><span class="hm-trust__title">Secure Payments</span><span class="hm-trust__text">Cash on delivery, Visa, Mastercard</span></div><div class="hm-trust__item"><span class="hm-trust__title">Easy Returns</span><span class="hm-trust__text">14-day return policy</span></div></div>',
};

const _categories = <Category>[
  Category(uid: 'Mw==', name: 'Super Market', urlKey: 'super-market', productCount: 7),
  Category(uid: 'NA==', name: 'Pharmacy', urlKey: 'pharmacy', productCount: 8),
  Category(uid: 'NQ==', name: 'Furniture', urlKey: 'furniture', productCount: 7),
  Category(uid: 'Ng==', name: 'Fashion', urlKey: 'fashion', productCount: 19),
  Category(uid: 'Nw==', name: 'FMCG', urlKey: 'fmcg', productCount: 5),
];

Product _p(String name, double price, [double? was]) => Product(
  sku: name,
  name: name,
  urlKey: name.toLowerCase().replaceAll(' ', '-'),
  brand: 'MIA CO',
  regularPrice: Money(amount: was ?? price, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
);

final _rail = <Product>[
  _p('Corner Sofa Bed', 425, 500),
  _p('3-Piece Living Room Set', 255, 300),
  _p('Burgundy Rocking Chair', 180),
];

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await load(AppTheme.latinFont, ['assets/fonts/Inter.ttf']);
  await load(AppTheme.arabicFont, ['assets/fonts/Cairo.ttf']);
  await load(AppTheme.displayFont, ['assets/fonts/PlayfairDisplay.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

Widget _harness(String locale, GlobalKey boundary, {bool storeDown = false}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HubHomeScreen()),
      for (final p in ['/categories', '/cart', '/wishlist', '/account', '/search', '/notifications', '/addresses'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
      GoRoute(path: '/category/:uid', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/product/:urlKey', builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      homeCmsBlocksProvider.overrideWith((ref) async => _cms),
      homeCategoriesProvider.overrideWith(
        (ref) async => storeDown
            ? throw const Failure(FailureKind.service, detail: 'HTTP 503')
            : _categories,
      ),
      categoryThumbnailsProvider.overrideWith((ref, key) async => const <String, String>{}),
      homeCategoryRailProvider.overrideWith((ref, uid) async => _rail),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
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

Future<void> _render(WidgetTester tester, String locale) async {
  tester.view.physicalSize = const Size(390, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(_harness(locale, key));
  await tester.pumpAndSettle();
  // Asset images (the logo) decode asynchronously; finish them before capture.
  await tester.runAsync(() async {
    for (final el in find.byType(Image).evaluate()) {
      await precacheImage((el.widget as Image).image, el);
    }
  });
  await tester.pumpAndSettle();
  // A visual record for review — build/ is gitignored, nothing is asserted on it.
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/home_$locale.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('Home renders every Build 1 section from Magento content (EN)', (tester) async {
    await _render(tester, 'en');
    expect(find.text('Free delivery on qualifying orders · Fast nationwide shipping'), findsOneWidget);
    expect(find.text('Shop by category'), findsOneWidget);
    expect(find.text('Super Market'), findsWidgets); // tile + rail title
    expect(find.text('Corner Sofa Bed'), findsWidgets); // rail products
    expect(find.text('Up to 50% Off'), findsOneWidget);
    expect(find.text('Trusted Sellers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home renders right-to-left in Arabic without overflow', (tester) async {
    await _render(tester, 'ar');
    expect(find.text('Corner Sofa Bed'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.byType(HubHomeScreen))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A failed catalogue load offers Retry instead of a blank Home', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness('en', GlobalKey(), storeDown: true));
    await tester.pumpAndSettle();
    expect(
      find.text('The store is temporarily unavailable. Please try again shortly.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Shop by category'), findsNothing);
  });
}
