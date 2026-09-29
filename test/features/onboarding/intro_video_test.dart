import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/hero_slides_provider.dart';
import 'package:hubmarket_app/features/catalog/data/home_config_provider.dart';
import 'package:hubmarket_app/features/catalog/domain/home_config.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/onboarding/presentation/intro_video_screen.dart';
import 'package:hubmarket_app/features/onboarding/presentation/launch_splash_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

/// The intro is bundled, so an encode that silently stops shipping would be
/// invisible until a user hit a black first launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IntroVideoView', () {
    Widget harness({
      required VoidCallback onFinished,
      required VoidCallback onFailed,
      String locale = 'en',
    }) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: IntroVideoView(onFinished: onFinished, onFailed: onFailed),
    );

    // The client asked for Skip after five seconds (CL042-QA01). Before that
    // the intro cannot be dismissed at all, so the timing is the whole of the
    // shopper's escape route and worth pinning down.
    testWidgets('hides Skip until the five seconds are up', (tester) async {
      await tester.pumpWidget(harness(onFinished: () {}, onFailed: () {}));
      await tester.pump();
      expect(find.text('Skip Intro'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Skip Intro'), findsNothing);

      await tester.pump(const Duration(seconds: 2)); // 6s total
      expect(find.text('Skip Intro'), findsOneWidget);
    });

    testWidgets('Skip finishes exactly once, however often it is tapped', (
      tester,
    ) async {
      var finished = 0;
      await tester.pumpWidget(
        harness(onFinished: () => finished++, onFailed: () {}),
      );
      await tester.pump(kIntroSkipDelay + const Duration(seconds: 1));
      await tester.tap(find.text('Skip Intro'));
      await tester.pump();
      await tester.tap(find.text('Skip Intro'));
      await tester.pump();
      expect(finished, 1);
    });

    testWidgets('reports failure rather than holding a black frame', (
      tester,
    ) async {
      // There is no video platform channel under flutter_test, so initialize()
      // fails here exactly as it would on a device that cannot decode the
      // asset. That path matters more now the intro runs on every launch: a
      // decode failure would otherwise block every start, not just the first.
      var failed = 0;
      await tester.pumpWidget(
        harness(onFinished: () {}, onFailed: () => failed++),
      );
      await tester.pumpAndSettle();
      expect(failed, 1);
    });

    testWidgets('uses the Arabic wording the client supplied', (tester) async {
      await tester.pumpWidget(
        harness(onFinished: () {}, onFailed: () {}, locale: 'ar'),
      );
      await tester.pump(kIntroSkipDelay + const Duration(seconds: 1));
      expect(find.text('تخطي المقدمة'), findsOneWidget);
    });
  });

  group('LaunchSplashScreen — intro gate', () {
    Widget harness(LocalCache cache, {String? token}) {
      final router = GoRouter(
        initialLocation: AppRoutes.splash,
        routes: [
          GoRoute(
            path: AppRoutes.splash,
            builder: (_, __) => const LaunchSplashScreen(),
          ),
          for (final p in [AppRoutes.welcome, AppRoutes.home])
            GoRoute(
              path: p,
              builder: (_, __) => Scaffold(body: Text('at $p')),
            ),
        ],
      );
      return ProviderScope(
        overrides: [
          localCacheProvider.overrideWithValue(cache),
          secureTokenStoreProvider.overrideWithValue(
            FakeSecureTokenStore(token),
          ),
          // The splash warms Home in the background; stub those so the test
          // never reaches the network.
          categoryTreeProvider.overrideWith((ref) async => []),
          homeConfigProvider.overrideWith((ref) async => HomeConfig.empty),
          heroSlidesProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(
          routerConfig: router,
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

    testWidgets('plays the intro on every cold start', (tester) async {
      // The client reversed the once-only behaviour (CL042-QA01): it must show
      // "every time we open the app".
      final cache = FakeLocalCache();
      for (var launch = 1; launch <= 3; launch++) {
        await tester.pumpWidget(harness(cache));
        await tester.pump();
        expect(
          find.byType(IntroVideoView),
          findsOneWidget,
          reason: 'launch $launch should still play the intro',
        );
        await tester.pumpAndSettle();
        // Tear the tree down so the next iteration is a fresh launch.
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('persists nothing that could suppress a later launch', (
      tester,
    ) async {
      final cache = FakeLocalCache();
      await tester.pumpWidget(harness(cache));
      await tester.pumpAndSettle();
      // The old build wrote an "intro_video_seen" key; nothing should now.
      expect(cache.readString('intro_video_seen'), isNull);
    });

    testWidgets('a failed intro still routes on, it does not hang', (
      tester,
    ) async {
      await tester.pumpWidget(harness(FakeLocalCache()));
      await tester.pumpAndSettle();
      expect(find.text('at ${AppRoutes.welcome}'), findsOneWidget);
    });

    testWidgets('a signed-in customer still lands on Home', (tester) async {
      await tester.pumpWidget(harness(FakeLocalCache(), token: 'tok'));
      await tester.pumpAndSettle();
      expect(find.text('at ${AppRoutes.home}'), findsOneWidget);
    });
  });
}
