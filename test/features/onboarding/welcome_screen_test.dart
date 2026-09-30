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
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/hm_hero.dart';
import 'package:hubmarket_app/features/onboarding/presentation/welcome_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

HmHeroBanner _slide(int id, String kicker) => HmHeroBanner(
  id: id,
  slot: HmBannerSlot.slide,
  title: 'Slide $id',
  kicker: kicker,
  // A URL so the slide counts as a photo; tests never load it.
  imageUrl: 'https://hub-market.magento2.click/media/hero/$id.jpg',
  accent: const Color(0xFF0F7B3F),
  link: const HmLink(
    type: HmLinkType.deals,
    url: 'https://hub-market.magento2.click/en/deals',
  ),
);

Widget _harness({
  required List<HmHeroBanner> slides,
  String locale = 'en',
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: '/welcome',
    routes: [
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      for (final p in ['/home', '/signin', '/signup'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(
        slides.isEmpty
            ? const HubAppState.unavailable()
            : const HubAppState.available(kSampleHmAppConfig),
      ),
      welcomeSlidesProvider.overrideWith((ref) async => slides),
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

/// [captureScreen] minus its image pre-cache: the slides are network images,
/// which the test can't load, so their placeholders are what is drawn.
Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  // The slides are network images: give the image cache a temporary folder so
  // a load attempt fails quietly (HTTP is stubbed to 400 in widget tests)
  // instead of on a missing plugin.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.createTempSync('hm_welcome').path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('the Hero Banner slides as the photo carousel ($locale)', (
      tester,
    ) async {
      await _phone(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        _harness(
          locale: locale,
          boundary: key,
          slides: [
            _slide(
              1,
              locale == 'ar' ? 'توصيل في نفس اليوم' : 'SAME-DAY DELIVERY',
            ),
            _slide(2, locale == 'ar' ? 'عروض الأسبوع' : 'WEEKLY OFFERS'),
            _slide(3, 'NEW'),
          ],
        ),
      );
      // The photos never arrive in a test: their shimmer runs on, so pump a
      // few frames instead of waiting to settle, and capture without
      // pre-caching them (the network image cache never answers here).
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _capture(tester, key, 'welcome_slides_$locale');

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(HmPagerDots), findsOneWidget);
      expect(
        find.text(locale == 'ar' ? 'توصيل في نفس اليوم' : 'SAME-DAY DELIVERY'),
        findsOneWidget,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(WelcomeScreen)),
      );
      expect(find.text(l10n.welcomeHeadline), findsOneWidget);
      expect(find.text(l10n.welcomeCreateAccount), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('without slides: the logo panel (Build 1)', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_harness(slides: const []));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.byType(HmPagerDots), findsNothing);
    expect(find.text('SAME-DAY DELIVERY'), findsOneWidget); // the app's kicker
    expect(find.text('Continue as guest'), findsOneWidget);
  });
}
