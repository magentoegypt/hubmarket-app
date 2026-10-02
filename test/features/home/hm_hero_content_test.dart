import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_models.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/hm_hero.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

// Hero Banner records as the live store sends them (hub-market.magento2.click,
// 2 Oct 2026): the slide's kicker is typed in title case, the Bundle Deals tile
// has no image and only a tone.
const _slide = HmHeroBanner(
  id: 1,
  slot: HmBannerSlot.slide,
  title: 'Fresh Groceries From Local Vendors',
  kicker: 'Same-Day Delivery',
  subtitle: 'Organic produce, dairy and pantry essentials, delivered in hours.',
  ctaLabel: 'Shop Grocery',
  tone: Color(0xFF0D3320),
  accent: Color(0xFF2D7A3A),
  link: HmLink(
    type: HmLinkType.category,
    url: 'https://hub-market.magento2.click/en/super-market.html',
    uid: 'MTAx',
  ),
);

const _bundleTile = HmHeroBanner(
  id: 13,
  slot: HmBannerSlot.tile,
  title: 'Bundle Deals',
  kicker: '🎁 This week only',
  subtitle: 'Buy more, pay less',
  tone: Color(0xFFF26522),
  link: HmLink(
    type: HmLinkType.bundles,
    url: 'https://hub-market.magento2.click/en/bundles',
    path: 'bundles',
  ),
);

Widget _app(Widget child, {String locale = 'en'}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: child)),
      GoRoute(
        path: AppRoutes.bundles,
        builder: (_, __) => const Scaffold(body: Text('route bundles')),
      ),
    ],
  );
  return ProviderScope(
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
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('the slide kicker is set in capitals, as the frame and the website do', () {
    testWidgets('whatever case the admin typed (en)', (tester) async {
      await tester.pumpWidget(_app(const HmHeroCarousel(slides: [_slide])));
      await tester.pump();
      expect(find.text('SAME-DAY DELIVERY'), findsOneWidget);
      expect(find.text('Same-Day Delivery'), findsNothing);
      // The headline and the button are the admin's words, untouched.
      expect(find.text('Fresh Groceries From Local Vendors'), findsOneWidget);
      expect(find.text('Shop Grocery'), findsOneWidget);
    });

    testWidgets('Arabic has no capitals: the kicker reads as typed', (
      tester,
    ) async {
      const ar = HmHeroBanner(
        id: 7,
        slot: HmBannerSlot.slide,
        title: 'بقالة طازجة من بائعين محليين',
        kicker: 'توصيل في نفس اليوم',
        accent: Color(0xFF2D7A3A),
        link: HmLink(
          type: HmLinkType.category,
          url: 'https://hub-market.magento2.click/ar/super-market.html',
          uid: 'MTAx',
        ),
      );
      await tester.pumpWidget(
        _app(const HmHeroCarousel(slides: [ar]), locale: 'ar'),
      );
      await tester.pump();
      expect(find.text('توصيل في نفس اليوم'), findsOneWidget);
    });
  });

  group('a tile without an image (the live Bundle Deals tile)', () {
    testWidgets('is a solid tile in its tone colour with its text as typed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const HmPromoTiles(tiles: [_bundleTile])),
      );
      await tester.pump();

      final tile = find.byType(HmPromoTile);
      expect(tile, findsOneWidget);
      final surface = tester.widget<Material>(
        find.descendant(of: tile, matching: find.byType(Material)).first,
      );
      expect(surface.color, const Color(0xFFF26522));
      expect(
        find.descendant(of: tile, matching: find.byType(HubImage)),
        findsNothing,
      );
      // The tile's kicker is not a pill: it stays as typed, emoji included.
      expect(find.text('🎁 This week only'), findsOneWidget);
      expect(find.text('Bundle Deals'), findsOneWidget);
      expect(find.text('Buy more, pay less'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens the Bundles page', (tester) async {
      await tester.pumpWidget(
        _app(const HmPromoTiles(tiles: [_bundleTile])),
      );
      await tester.pump();

      await tester.tap(find.text('Bundle Deals'));
      await tester.pumpAndSettle();
      expect(find.text('route bundles'), findsOneWidget);
    });
  });
}
