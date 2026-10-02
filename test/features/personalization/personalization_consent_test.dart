import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_providers.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/features/personalization/data/insights_tracker.dart';
import 'package:hubmarket_app/features/personalization/data/personalization_identity.dart';
import 'package:hubmarket_app/features/personalization/data/product_object_ids.dart';
import 'package:hubmarket_app/features/personalization/presentation/personalization_consent_prompt.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

// "Personalise my picks?": nothing about the shopper's activity is used, sent
// or even given an id until they say Allow (the website does the same without
// the cookie consent). Allow / Not now on the Home, the Settings switch after.

const _settings = AlgoliaSettings(
  appId: 'HL67ED06DQ',
  searchKey: 'search-only-key',
  indexName: 'hubmarket_en',
);

class _FixedSettings implements AlgoliaSettingsRepository {
  @override
  Future<AlgoliaSettings> settingsFor(String storeCode) async => _settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedIds extends ProductObjectIds {
  _FixedIds(this.ids) : super(FakeHubAppClient(const {}));

  final Map<String, String> ids;

  @override
  Future<Map<String, String>> resolve(Iterable<String> skus) async => {
    for (final sku in skus)
      if (ids[sku] case final id?) sku: id,
  };
}

/// What reached Algolia.
class _Algolia {
  final requests = <http.Request>[];

  List<Map<String, dynamic>> get events => [
    for (final request in requests)
      ...(jsonDecode(request.body)['events'] as List).cast<Map<String, dynamic>>(),
  ];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return http.Response('{"status":200,"message":"OK"}', 200);
  });
}

ProviderContainer _phone(FakeLocalCache cache) {
  final container = ProviderContainer(
    overrides: [localCacheProvider.overrideWithValue(cache)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(loadAppFonts);

  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  group('the answer', () {
    test('a phone that was never asked is undecided: nothing is allowed and '
        'there is no id', () {
      final cache = FakeLocalCache.neverAsked();
      final container = _phone(cache);

      expect(
        container.read(personalizationConsentProvider),
        PersonalizationConsent.undecided,
      );
      expect(container.read(personalizationEnabledProvider), isFalse);
      expect(container.read(personalizationTokenProvider), isNull);
      expect(cache.readString(kPersonalizationTokenKey), isNull);
      expect(cache.readString(kPersonalizationEnabledKey), isNull);
    });

    test('Not now is kept, is not a yes and makes no id', () async {
      final cache = FakeLocalCache.neverAsked();
      final container = _phone(cache);

      await container.read(personalizationConsentProvider.notifier).decline();

      expect(
        container.read(personalizationConsentProvider),
        PersonalizationConsent.declined,
      );
      expect(container.read(personalizationEnabledProvider), isFalse);
      expect(container.read(personalizationTokenProvider), isNull);
      expect(cache.readString(kPersonalizationEnabledKey), 'false');
      expect(cache.readString(kPersonalizationTokenKey), isNull);
    });

    test('Allow is kept and makes one random id, the same one every time and '
        'after a restart', () async {
      final cache = FakeLocalCache.neverAsked();
      final container = _phone(cache);

      await container.read(personalizationConsentProvider.notifier).allow();

      expect(container.read(personalizationEnabledProvider), isTrue);
      final token = container.read(personalizationTokenProvider)!;
      expect(isValidPersonalizationToken(token), isTrue);
      expect(token, startsWith('hm-'));
      expect(container.read(personalizationTokenProvider), token);
      expect(cache.readString(kPersonalizationEnabledKey), 'true');
      expect(cache.readString(kPersonalizationTokenKey), token);

      // the next launch reads the same phone
      final relaunched = _phone(cache);
      expect(
        relaunched.read(personalizationConsentProvider),
        PersonalizationConsent.allowed,
      );
      expect(relaunched.read(personalizationTokenProvider), token);
    });

    test('turning it off deletes the id, and Allow again starts a new profile', () async {
      final cache = FakeLocalCache.neverAsked();
      final container = _phone(cache);
      final consent = container.read(personalizationConsentProvider.notifier);

      await consent.allow();
      final first = container.read(personalizationTokenProvider)!;
      await consent.set(false);

      expect(container.read(personalizationTokenProvider), isNull);
      expect(cache.readString(kPersonalizationTokenKey), isNull);
      expect(cache.readString(kPersonalizationEnabledKey), 'false');

      await consent.set(true);
      final second = container.read(personalizationTokenProvider)!;
      expect(isValidPersonalizationToken(second), isTrue);
      expect(second, isNot(first));
    });

    test('an id the first builds made before the app asked is deleted, unless '
        'the shopper had allowed it', () {
      for (final (answer, kept) in [
        (null, false),
        ('false', false),
        ('true', true),
      ]) {
        final cache = FakeLocalCache.neverAsked()
          ..writeString(kPersonalizationTokenKey, 'hm-made-before');
        if (answer != null) cache.writeString(kPersonalizationEnabledKey, answer);

        _phone(cache).read(personalizationConsentProvider);

        expect(
          cache.readString(kPersonalizationTokenKey),
          kept ? 'hm-made-before' : isNull,
          reason: 'answer $answer',
        );
      }
    });

    test('the id follows the answer while the app is running', () async {
      final container = _phone(FakeLocalCache.neverAsked());
      final seen = <String?>[];
      container.listen<String?>(
        personalizationTokenProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      final consent = container.read(personalizationConsentProvider.notifier);

      await consent.allow();
      await pumpEventQueue();
      await consent.decline();
      await pumpEventQueue();

      expect(seen, hasLength(3));
      expect(seen.first, isNull);
      expect(seen[1], startsWith('hm-'));
      expect(seen.last, isNull);
    });
  });

  group('nothing leaves the phone before Allow', () {
    ProviderContainer app(_Algolia algolia, FakeLocalCache cache) {
      final container = ProviderContainer(
        overrides: auditOverrides(
          overrides: [
            localCacheProvider.overrideWithValue(cache),
            algoliaHttpClientProvider.overrideWithValue(algolia.client),
            algoliaSettingsRepositoryProvider.overrideWithValue(_FixedSettings()),
            productObjectIdsProvider.overrideWithValue(
              _FixedIds(const {'sku1': '101'}),
            ),
          ],
        ),
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the app\'s tracker sends no event while the shopper has not allowed '
        'it, then sends under the new id, then stops again', () async {
      final algolia = _Algolia();
      final cache = FakeLocalCache.neverAsked();
      final container = app(algolia, cache);
      final tracker = container.read(insightsTrackerProvider);

      tracker
        ..productViewed('sku1')
        ..productClicked('sku1')
        ..addedToCart('sku1')
        ..addedToWishlist('sku1');
      await pumpEventQueue();
      expect(algolia.requests, isEmpty);
      expect(cache.readString(kPersonalizationTokenKey), isNull);

      final consent = container.read(personalizationConsentProvider.notifier);
      await consent.allow();
      tracker.productClicked('sku1');
      await pumpEventQueue();
      expect(algolia.events, hasLength(1));
      expect(algolia.events.single['userToken'], cache.readString(kPersonalizationTokenKey));
      expect(algolia.events.single['userToken'], startsWith('hm-'));

      await consent.decline();
      tracker.productClicked('sku1');
      await pumpEventQueue();
      expect(algolia.events, hasLength(1));
      expect(cache.readString(kPersonalizationTokenKey), isNull);
    });

    test('Not now sends nothing either', () async {
      final algolia = _Algolia();
      final container = app(algolia, FakeLocalCache());
      container.read(insightsTrackerProvider)
        ..productViewed('sku1')
        ..orderPlaced(const [TrackedLine(sku: 'sku1', quantity: 1)]);
      await pumpEventQueue();
      expect(algolia.requests, isEmpty);
    });
  });

  group('the question', () {
    Future<ProviderContainer> page(
      WidgetTester tester, {
      String locale = 'en',
      FakeLocalCache? cache,
      double height = 844,
    }) => pumpAudit(
      tester,
      locale: locale,
      pushed: false,
      height: height,
      screen: const PersonalizationConsentPrompt(
        child: Scaffold(body: Center(child: Text('the Home'))),
      ),
      overrides: [
        localCacheProvider.overrideWithValue(cache ?? FakeLocalCache.neverAsked()),
      ],
    );

    testWidgets('opens when the Home first opens: what it is for, where to '
        'change it, and both answers, over the page', (tester) async {
      await page(tester);

      expect(find.text(en.personalisationPromptTitle), findsOneWidget);
      expect(find.text(en.personalisationPromptBody), findsOneWidget);
      expect(find.text(en.personalisationPromptNote), findsOneWidget);
      expect(find.text(en.personalisationPromptAllow), findsOneWidget);
      expect(find.text(en.personalisationPromptLater), findsOneWidget);
      expect(find.text('the Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Allow is kept, closes the sheet and is not asked again', (
      tester,
    ) async {
      final cache = FakeLocalCache.neverAsked();
      final container = await page(tester, cache: cache);

      await tester.tap(find.text(en.personalisationPromptAllow));
      await tester.pumpAndSettle();

      expect(find.text(en.personalisationPromptTitle), findsNothing);
      expect(
        container.read(personalizationConsentProvider),
        PersonalizationConsent.allowed,
      );
      expect(cache.readString(kPersonalizationEnabledKey), 'true');

      // the Home opens again (another tab, the next launch): no second question
      await page(tester, cache: cache);
      expect(find.text(en.personalisationPromptTitle), findsNothing);
    });

    testWidgets('Not now is kept as a no, closes the sheet and is not asked '
        'again', (tester) async {
      final cache = FakeLocalCache.neverAsked();
      final container = await page(tester, cache: cache);

      await tester.tap(find.text(en.personalisationPromptLater));
      await tester.pumpAndSettle();

      expect(find.text(en.personalisationPromptTitle), findsNothing);
      expect(
        container.read(personalizationConsentProvider),
        PersonalizationConsent.declined,
      );
      expect(container.read(personalizationTokenProvider), isNull);
      expect(cache.readString(kPersonalizationEnabledKey), 'false');

      await page(tester, cache: cache);
      expect(find.text(en.personalisationPromptTitle), findsNothing);
    });

    testWidgets('a tap beside the sheet, a drag on it or the back gesture does '
        'not answer for the shopper', (tester) async {
      final cache = FakeLocalCache.neverAsked();
      final container = await page(tester, cache: cache);

      await tester.tapAt(const Offset(195, 12));
      await tester.pumpAndSettle();
      await tester.drag(
        find.text(en.personalisationPromptTitle),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(en.personalisationPromptTitle), findsOneWidget);
      expect(
        container.read(personalizationConsentProvider),
        PersonalizationConsent.undecided,
      );
      expect(cache.readString(kPersonalizationEnabledKey), isNull);
    });

    testWidgets('is not asked of a shopper who already answered', (tester) async {
      for (final answer in ['true', 'false']) {
        await page(
          tester,
          cache: FakeLocalCache.neverAsked()
            ..writeString(kPersonalizationEnabledKey, answer),
        );
        expect(
          find.text(en.personalisationPromptTitle),
          findsNothing,
          reason: answer,
        );
      }
    });

    testWidgets('is not asked over another page: the next time the Home opens '
        'will do', (tester) async {
      final container = ProviderContainer(
        overrides: auditOverrides(
          overrides: [
            localCacheProvider.overrideWithValue(FakeLocalCache.neverAsked()),
          ],
        ),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light('en'),
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // The Home, with a product page already pushed over it.
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute<void>(
                builder: (_) => const PersonalizationConsentPrompt(
                  child: Scaffold(body: Text('the Home')),
                ),
              ),
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('a product')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(en.personalisationPromptTitle), findsNothing);
      expect(
        container.read(personalizationConsentProvider),
        PersonalizationConsent.undecided,
      );
    });

    testWidgets('in Arabic it reads right to left, in Arabic', (tester) async {
      await page(tester, locale: 'ar');

      expect(find.text(ar.personalisationPromptTitle), findsOneWidget);
      expect(find.text(ar.personalisationPromptBody), findsOneWidget);
      expect(find.text(ar.personalisationPromptNote), findsOneWidget);
      expect(find.text(ar.personalisationPromptAllow), findsOneWidget);
      expect(find.text(ar.personalisationPromptLater), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(ar.personalisationPromptTitle))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    // A visual record of the sheet over a page, as a 360 dp phone draws it
    // (build/test_screens/personalisation_prompt_{en,ar}.png).
    for (final locale in ['en', 'ar']) {
      testWidgets('draws on a 360 dp phone ($locale)', (tester) async {
        final key = GlobalKey();
        await pumpAudit(
          tester,
          locale: locale,
          pushed: false,
          boundary: key,
          screen: const PersonalizationConsentPrompt(
            child: Scaffold(body: Center(child: Text('the Home'))),
          ),
          overrides: [
            localCacheProvider.overrideWithValue(FakeLocalCache.neverAsked()),
          ],
        );
        tester.view.physicalSize = const Size(360, 780);
        await tester.pumpAndSettle();

        await withRealShadows(
          () => captureScreen(tester, key, 'personalisation_prompt_$locale'),
        );
        expect(tester.takeException(), isNull);
        final l10n = locale == 'ar' ? ar : en;
        // Both buttons are full width and 52 high, inside the 24 dp sides.
        for (final label in [
          l10n.personalisationPromptAllow,
          l10n.personalisationPromptLater,
        ]) {
          final size = tester.getSize(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          );
          expect(size, const Size(312, 52), reason: label);
        }
      });
    }

    for (final locale in ['en', 'ar']) {
      testWidgets('fits a 360 dp phone at twice the text size and scrolls to '
          'its buttons ($locale)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final cache = FakeLocalCache.neverAsked();
        final container = await page(tester, locale: locale, cache: cache);
        tester.view.physicalSize = const Size(360, 640);
        await tester.pumpAndSettle();

        final l10n = locale == 'ar' ? ar : en;
        expect(find.text(l10n.personalisationPromptTitle), findsOneWidget);
        await tester.ensureVisible(find.text(l10n.personalisationPromptAllow));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.personalisationPromptAllow));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          container.read(personalizationConsentProvider),
          PersonalizationConsent.allowed,
        );
      });
    }
  });

  group('on the Home', () {
    Widget app(String locale, FakeLocalCache cache) {
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
          ])
            GoRoute(path: p, builder: (_, __) => const Scaffold()),
        ],
      );
      return ProviderScope(
        overrides: [
          localCacheProvider.overrideWithValue(cache),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
          hubAppOverride(const HubAppState.unavailable()),
          homeCmsBlocksProvider.overrideWith(
            (ref) async => const <String, String>{},
          ),
          homeCategoriesProvider.overrideWith((ref) async => const []),
        ],
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

    Future<void> open(WidgetTester tester, String locale, FakeLocalCache cache) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(locale, cache));
      await tester.pumpAndSettle();
    }

    testWidgets('a phone that was never asked is asked over the Home, and Not '
        'now leaves the Home as it was', (tester) async {
      final cache = FakeLocalCache.neverAsked();
      await open(tester, 'en', cache);

      expect(find.byType(HubHomeScreen), findsOneWidget);
      expect(find.text(en.personalisationPromptTitle), findsOneWidget);

      await tester.tap(find.text(en.personalisationPromptLater));
      await tester.pumpAndSettle();

      expect(find.text(en.personalisationPromptTitle), findsNothing);
      expect(find.byType(HubHomeScreen), findsOneWidget);
      expect(cache.readString(kPersonalizationEnabledKey), 'false');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Allow on the Home turns personalisation on', (tester) async {
      final cache = FakeLocalCache.neverAsked();
      await open(tester, 'ar', cache);

      await tester.tap(find.text(ar.personalisationPromptAllow));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HubHomeScreen)),
      );
      expect(container.read(personalizationEnabledProvider), isTrue);
      expect(cache.readString(kPersonalizationEnabledKey), 'true');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone that answered is not asked', (tester) async {
      await open(tester, 'en', FakeLocalCache());
      expect(find.text(en.personalisationPromptTitle), findsNothing);
    });
  });
}
