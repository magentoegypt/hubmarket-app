import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

const _testContact = StoreContact(
  company: 'Hub Market',
  address: 'Dubai, UAE',
  phone: '+971500000000',
  phoneDisplay: '+971 50 000 0000',
  email: 'info@hub-market.magento2.click',
  hours: '',
  whatsapp: 'https://wa.me/971500000000',
  website: 'https://hub-market.magento2.click',
);

/// What Hub Market publishes today: a WhatsApp link (from the footer CMS block)
/// and nothing else.
const _whatsappOnly = StoreContact(
  website: 'https://hub-market.magento2.click',
  whatsapp: 'https://wa.me/971500000000',
);

Future<void> _pump(
  WidgetTester tester, {
  String locale = 'en',
  StoreContact contact = _testContact,
}) async {
  await tester.binding.setSurfaceSize(const Size(450, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/help',
    routes: [
      GoRoute(path: '/help', builder: (_, __) => const HelpScreen()),
      for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        storeContactProvider.overrideWithValue(contact),
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
}

void main() {
  // FAQ copy is content (ARB) and changes with the brand, so assert against the
  // localizations rather than hardcoded text.
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('renders search, contact actions and FAQ (EN)', (tester) async {
    await _pump(tester);

    // Help search + the three contact cards.
    expect(find.text(en.helpSearchHint), findsOneWidget);
    expect(find.text(en.helpLiveChat), findsOneWidget);
    expect(find.text(en.helpCallUs), findsOneWidget);
    expect(find.text(en.helpEmailLabel), findsOneWidget);

    // First FAQ is expanded by default → its answer is visible.
    expect(find.text(en.helpQ1), findsOneWidget);
    expect(find.text(en.helpA1), findsOneWidget);

    // A collapsed FAQ expands on tap.
    expect(find.text(en.helpA5), findsNothing);
    await tester.tap(find.text(en.helpQ5));
    await tester.pumpAndSettle();
    expect(find.text(en.helpA5), findsOneWidget);
  });

  testWidgets('offers only the channels the store publishes', (tester) async {
    await _pump(tester, contact: _whatsappOnly);

    expect(find.text(en.helpLiveChat), findsOneWidget);
    expect(find.text(en.helpCallUs), findsNothing);
    expect(find.text(en.helpEmailLabel), findsNothing);
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.text(ar.helpQ5), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.helpQ5))),
      TextDirection.rtl,
    );
  });
}
