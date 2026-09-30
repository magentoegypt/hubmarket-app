import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/presentation/newsletter_controller.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_screen.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

Future<FakeLocalCache> _pump(
  WidgetTester tester, {
  required FakeAccountRepository account,
  bool push = false,
  bool newsletterEnabled = true,
  String? token = 'persisted',
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cache = FakeLocalCache();
  final router = GoRouter(
    initialLocation: AppRoutes.notificationSettings,
    routes: [
      GoRoute(
        path: AppRoutes.notificationSettings,
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account', '/signin'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        accountRepositoryProvider.overrideWithValue(account),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
        pushNotificationsAvailableProvider.overrideWithValue(push),
        storeFeaturesProvider.overrideWith(
          (ref) async => StoreFeatures(newsletterEnabled: newsletterEnabled),
        ),
        // Build 1: the backend takes no device tokens.
        hubAppOverride(const HubAppState.unavailable()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
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
  await tester.pumpAndSettle();
  return cache;
}

Finder get _save => find.widgetWithText(FilledButton, 'Save');

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('with push off, only the account newsletter is offered', (
    tester,
  ) async {
    await _pump(tester, account: FakeAccountRepository());
    expect(find.text(en.notificationSettingsTitle), findsOneWidget);
    expect(find.text(en.newsletterGeneral), findsOneWidget);
    expect(find.text(en.notificationsPromoTitle), findsNothing);
    expect(find.byType(Switch), findsNothing);
    // Nothing changed yet, nothing to save.
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });

  testWidgets('subscribing saves is_subscribed on the account', (tester) async {
    final account = FakeAccountRepository();
    await _pump(tester, account: account);

    await tester.tap(find.text(en.newsletterGeneral));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(account.newsletterCalls, isEmpty, reason: 'saved only on Save');

    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(account.newsletterCalls, [true]);
    expect(find.text(en.notificationSettingsSaved), findsOneWidget);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });

  testWidgets('unsubscribing sends false', (tester) async {
    final account = FakeAccountRepository(newsletterSubscribed: true);
    await _pump(tester, account: account);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(account.newsletterCalls, [false]);
  });

  testWidgets('a store that needs e-mail confirmation says so', (
    tester,
  ) async {
    final account = FakeAccountRepository(newsletterNeedsConfirmation: true);
    await _pump(tester, account: account);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(account.newsletterCalls, [true]);
    expect(find.text(en.footerSubscribeConfirm), findsOneWidget);
    // The box shows what the store saved: not subscribed until confirmed.
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('push appears with FCM and saves the promotions opt-in', (
    tester,
  ) async {
    final cache = await _pump(
      tester,
      account: FakeAccountRepository(),
      push: true,
    );
    expect(find.text(en.notificationsPushSection.toUpperCase()), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(cache.readString(kPromoPrefKey), 'false');
  });

  testWidgets('nothing to set when push is off and the newsletter disabled', (
    tester,
  ) async {
    await _pump(
      tester,
      account: FakeAccountRepository(),
      newsletterEnabled: false,
    );
    expect(find.text(en.notificationSettingsNone), findsOneWidget);
    expect(_save, findsNothing);
  });

  testWidgets('a guest is asked to sign in', (tester) async {
    await _pump(tester, account: FakeAccountRepository(), token: null);
    expect(find.text(en.notificationSettingsSignIn), findsOneWidget);
  });

  testWidgets('renders right-to-left in Arabic', (tester) async {
    await _pump(tester, account: FakeAccountRepository(), locale: 'ar');
    final ar = lookupAppLocalizations(const Locale('ar'));
    expect(find.text(ar.newsletterGeneral), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.newsletterGeneral))),
      TextDirection.rtl,
    );
  });

  group('NewsletterController', () {
    test('reads the account flag and reverts a failed save', () async {
      final account = _FailingNewsletterRepo();
      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          secureTokenStoreProvider.overrideWithValue(
            FakeSecureTokenStore('persisted'),
          ),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          accountRepositoryProvider.overrideWithValue(account),
        ],
      );
      addTearDown(container.dispose);
      // Let the session restore from the stored token first.
      container.read(authControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);

      container.listen(newsletterProvider, (_, __) {});
      expect(await container.read(newsletterProvider.future), isTrue);

      await expectLater(
        container.read(newsletterProvider.notifier).setSubscribed(false),
        throwsA(anything),
      );
      expect(container.read(newsletterProvider).valueOrNull, isTrue);
    });
  });
}

class _FailingNewsletterRepo extends FakeAccountRepository {
  _FailingNewsletterRepo() : super(newsletterSubscribed: true);

  @override
  Future<bool> setNewsletterSubscription(bool subscribed) async =>
      throw Exception('offline');
}
