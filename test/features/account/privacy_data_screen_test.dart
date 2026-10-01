import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/presentation/screens/privacy_data_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/features/store_credit/domain/store_credit.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/store_credit_fakes.dart';

Future<FakeAuthRepository> _pump(
  WidgetTester tester, {
  String? token = 'persisted',
  String locale = 'en',
  Override? hubApp,
  FakeStoreCreditRepository? credit,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = FakeAuthRepository();
  final router = GoRouter(
    initialLocation: AppRoutes.privacyData,
    routes: [
      GoRoute(
        path: AppRoutes.privacyData,
        builder: (_, __) => const PrivacyDataScreen(),
      ),
      GoRoute(
        path: AppRoutes.cmsPage,
        builder: (_, s) => Text('PAGE ${s.uri.queryParameters['url']}'),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
      for (final p in ['/categories', '/cart', '/wishlist', '/account'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
        authRepositoryProvider.overrideWithValue(auth),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cmsRepositoryProvider.overrideWithValue(
          FakeCmsRepository(blocks: const {'hm_footer_legal': kLegalLinksBlock}),
        ),
        // Build 1 unless a test says otherwise: no store credit.
        hubApp ?? hubAppOverride(const HubAppState.unavailable()),
        storeCreditRepositoryProvider.overrideWithValue(
          credit ?? FakeStoreCreditRepository(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('links the store policies from the footer block', (tester) async {
    await _pump(tester);
    expect(find.text(en.privacyDataTitle), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Cookies'), findsOneWidget);

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(
      find.text('PAGE privacy-policy-cookie-restriction-mode'),
      findsOneWidget,
    );
  });

  testWidgets('nothing the backend cannot do is offered', (tester) async {
    await _pump(tester);
    // Figma 20b's data export, consent toggle and password field have no
    // backend behind them.
    expect(find.textContaining('Download'), findsNothing);
    expect(find.textContaining('onsent'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('deletion needs the explicit "I understand" first', (
    tester,
  ) async {
    final auth = await _pump(tester);
    expect(find.text(en.deleteAccountIntro), findsOneWidget);

    final button = find.widgetWithText(FilledButton, en.deleteAccountAction);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.deleteAccountCalled, isFalse);

    await tester.tap(find.text(en.deleteAccountUnderstand));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.deleteAccountCalled, isTrue);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text(en.deleteAccountDone), findsOneWidget);
  });

  group('the credit balance is lost with the account', () {
    testWidgets('warned while the balance is above zero', (tester) async {
      final credit = FakeStoreCreditRepository();
      await _pump(tester, hubApp: accountHubApp(), credit: credit);
      expect(
        find.text(en.deleteAccountLoseCredit('\u2066AED 120\u2069')),
        findsOneWidget,
      );
      expect(credit.calls, ['fetchBalance']);
    });

    testWidgets('no line for an empty balance', (tester) async {
      await _pump(
        tester,
        hubApp: accountHubApp(),
        credit: FakeStoreCreditRepository(
          pages: [
            StoreCreditAccount(balance: aedCredit(0), canUseAtCheckout: true),
          ],
        ),
      );
      expect(find.text(en.deleteAccountIntro), findsOneWidget);
      expect(find.textContaining('store credit'), findsNothing);
    });

    testWidgets('no line (and no request) without store credit', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository();
      await _pump(tester, credit: credit);
      expect(find.textContaining('store credit'), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('Arabic keeps the amount left-to-right', (tester) async {
      await _pump(tester, locale: 'ar', hubApp: accountHubApp());
      expect(
        find.text(ar.deleteAccountLoseCredit('\u2066AED 120\u2069')),
        findsOneWidget,
      );
    });
  });

  testWidgets('a guest sees the policies but no deletion', (tester) async {
    await _pump(tester, token: null);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text(en.deleteAccountIntro), findsNothing);
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.text(ar.deleteAccountAction), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.deleteAccountAction))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
