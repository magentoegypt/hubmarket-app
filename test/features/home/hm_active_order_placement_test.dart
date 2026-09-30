import 'package:flutter/material.dart';
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
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_view.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/home_active_order.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';
import 'package:intl/intl.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import 'hm_home_fixtures.dart';

HmHomeSection _s(int id, HmSectionType type, {String? title}) =>
    HmHomeSection(id: id, type: type, title: title);

final _strip = _s(1, HmSectionType.deliveryStrip);
final _hero = _s(2, HmSectionType.heroBanners);
final _chips = _s(3, HmSectionType.categoryChips, title: 'Shop by category');
final _deals = _s(4, HmSectionType.todaysDeals, title: "Today's Deals");

/// Entries as "type" strings, the card as "CARD" (with the section id when
/// the admin placed it).
List<String> _names(List<HmHomeEntry> entries) => [
  for (final e in entries)
    e.isActiveOrder
        ? (e.section == null ? 'CARD' : 'CARD#${e.section!.id}')
        : e.section!.type.wire,
];

List<double> _gaps(List<HmHomeEntry> entries) => [
  for (var i = 0; i < entries.length; i++) hmHomeGapBefore(entries, i),
];

/// An open order placed yesterday at noon.
CustomerOrder _order() => CustomerOrder(
  number: '000000248',
  status: 'Processing',
  date: DateFormat('yyyy-MM-dd HH:mm:ss').format(
    DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(hours: 12)).subtract(const Duration(days: 1)),
  ),
  id: 'id-248',
  total: const Money(amount: 553, currency: 'AED'),
  lines: const [OrderLine(name: 'Line', quantity: 1)],
);

/// The fixture Home with ACTIVE_ORDER sections inserted before the sections
/// at [before] (ids of the fixture), each titled from [titles].
Map<String, dynamic> _homeWithPlacements({
  required bool arabic,
  required Map<int, (String?, String?)> before,
}) {
  final json = hmHomeJson(
    countdown: DateTime.now().add(const Duration(days: 2)),
    arabic: arabic,
  );
  final sections = <Map<String, dynamic>>[];
  var id = 90;
  for (final section in (json['sections'] as List).cast<Map<String, dynamic>>()) {
    final placement = before[section['id']];
    if (placement != null) {
      sections.add({
        'id': id++,
        'type': 'ACTIVE_ORDER',
        'title': placement.$1,
        'subtitle': placement.$2,
        'limit': 8,
        'ends_at': null,
        'countdown_ends_at': null,
        'personalizable': false,
        'more_link': null,
        'banners': null,
        'categories': null,
        'cms_block': null,
        'brands': null,
        'bundles': null,
        'stores': null,
        'products': null,
      });
    }
    sections.add(section);
  }
  return {...json, 'sections': sections};
}

Widget _app({
  required String locale,
  required Map<String, dynamic> home,
  bool signedIn = true,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HubHomeScreen()),
      GoRoute(
        path: '/:rest(.*)',
        builder: (_, state) => Text('route ${state.uri}'),
      ),
    ],
  );
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
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'persisted' : null),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(
        FakeAccountRepository(orders: [_order()]),
      ),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
      hmHomeProvider.overrideWith((ref) async => hmHomeFromJson(home)),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('hmHomeEntries', () {
    test('no ACTIVE_ORDER: the card goes under a leading delivery strip', () {
      final entries = hmHomeEntries([
        _strip,
        _hero,
        _chips,
      ], withActiveOrder: true);
      expect(_names(entries), [
        'DELIVERY_STRIP',
        'CARD',
        'HERO_BANNERS',
        'CATEGORY_CHIPS',
      ]);
      // Figma 07: 16 under the strip, then 28 between sections.
      expect(_gaps(entries), [0, 16, 28, 28]);
    });

    test('no ACTIVE_ORDER and no strip: the card leads the Home', () {
      final entries = hmHomeEntries([_hero, _chips], withActiveOrder: true);
      expect(_names(entries), ['CARD', 'HERO_BANNERS', 'CATEGORY_CHIPS']);
      expect(_gaps(entries), [16, 28, 28]);
    });

    test('the admin\'s ACTIVE_ORDER places the card, and only once', () {
      final entries = hmHomeEntries([
        _strip,
        _hero,
        _chips,
        _s(9, HmSectionType.activeOrder, title: 'Your order'),
        _deals,
        _s(10, HmSectionType.activeOrder),
      ], withActiveOrder: true);
      expect(_names(entries), [
        'DELIVERY_STRIP',
        'HERO_BANNERS',
        'CATEGORY_CHIPS',
        'CARD#9',
        'TODAYS_DEALS',
      ]);
      expect(entries[3].section!.title, 'Your order');
      expect(_gaps(entries), [0, 16, 28, 28, 28]);
    });

    test('without an order nothing is left of the card or its section', () {
      final placed = hmHomeEntries([
        _strip,
        _s(9, HmSectionType.activeOrder, title: 'Your order'),
        _hero,
      ], withActiveOrder: false);
      expect(_names(placed), ['DELIVERY_STRIP', 'HERO_BANNERS']);
      // The hero keeps the gap it has under the strip.
      expect(_gaps(placed), [0, 16]);

      expect(
        _names(hmHomeEntries([_strip, _hero], withActiveOrder: false)),
        ['DELIVERY_STRIP', 'HERO_BANNERS'],
      );
    });

    test('ACTIVE_ORDER is read, kept though it has no content, and is no '
        'Home on its own', () {
      final section = hmHomeSectionFromJson({
        'id': 9,
        'type': 'ACTIVE_ORDER',
        'title': null,
        'limit': 8,
      })!;
      expect(section.type, HmSectionType.activeOrder);
      expect(section.type.isPlacement, isTrue);
      expect(section.hasContent, isTrue);
      expect(section.hasHeader, isFalse);
      final home = HmHome(storeCode: 'en', sections: [section, _hero]);
      expect(home.visibleSections(DateTime.now()), hasLength(1));
      expect(hmHomeHasContent([section]), isFalse);
      expect(hmHomeHasContent([section, _chips]), isTrue);
      expect(HmSectionType.heroBanners.isPlacement, isFalse);
    });
  });

  group('Home (Build 2) with the admin\'s ACTIVE_ORDER', () {
    for (final locale in const ['en', 'ar']) {
      testWidgets('drawn where the admin put it, with its title, once '
          '($locale)', (tester) async {
        final arabic = locale == 'ar';
        final key = GlobalKey();
        await _pump(
          tester,
          _app(
            locale: locale,
            boundary: key,
            home: _homeWithPlacements(
              arabic: arabic,
              before: {
                // After Shop by category, before Today's Deals …
                4: (arabic ? 'طلبك' : 'Your order', null),
                // … and a second one further down, which is never drawn.
                7: (null, null),
              },
            ),
          ),
        );
        await captureScreen(tester, key, 'home_hubapp_active_order_placed_$locale');

        final card = find.byType(ActiveOrderCard);
        expect(card, findsOneWidget);
        expect(find.text('Processing'), findsOneWidget);
        final title = find.text(arabic ? 'طلبك' : 'Your order');
        expect(title, findsOneWidget);
        final chips = find.text(arabic ? 'تسوّق حسب الفئة' : 'Shop by category');
        final deals = find.text(arabic ? 'عروض اليوم' : "Today's Deals");
        final hero = find.text(
          arabic ? 'بقالة طازجة من بائعين محليين' : 'Fresh Groceries From Local Vendors',
        );
        final cardTop = tester.getTopLeft(card).dy;
        expect(cardTop, greaterThan(tester.getTopLeft(chips).dy));
        expect(cardTop, lessThan(tester.getTopLeft(deals).dy));
        expect(cardTop, greaterThan(tester.getTopLeft(hero).dy),
            reason: 'not at the default place above the hero as well');
        expect(tester.getTopLeft(title).dy, lessThan(cardTop));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a guest gets neither the card nor its title', (tester) async {
      await _pump(
        tester,
        _app(
          locale: 'en',
          signedIn: false,
          home: _homeWithPlacements(
            arabic: false,
            before: {4: ('Your order', 'On its way')},
          ),
        ),
      );
      expect(find.byType(ActiveOrderCard), findsNothing);
      expect(find.text('Your order'), findsNothing);
      expect(find.text('On its way'), findsNothing);
      expect(find.text("Today's Deals"), findsOneWidget);
    });
  });
}
