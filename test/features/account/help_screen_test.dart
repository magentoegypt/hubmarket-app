import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_topic_screen.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/faq.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

/// What Hub Market publishes today: a WhatsApp link (from the footer CMS
/// block) and nothing else.
const _whatsappOnly = StoreContact(
  website: 'https://hub-market.magento2.click',
  whatsapp: 'https://wa.me/971500000000',
);

const _allChannels = StoreContact(
  website: 'https://hub-market.magento2.click',
  whatsapp: 'https://wa.me/971500000000',
  phone: '+971500000000',
  phoneDisplay: '+971 50 000 0000',
  email: 'care@example.com',
);

Future<void> _pump(
  WidgetTester tester, {
  String locale = 'en',
  StoreContact contact = _whatsappOnly,
  bool contactEnabled = true,
  Map<String, String> blocks = const {'hm_footer_legal': kLegalLinksBlock},
  FakeAccountRepository? account,
}) async {
  await tester.binding.setSurfaceSize(const Size(450, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: AppRoutes.help,
    routes: [
      GoRoute(path: AppRoutes.help, builder: (_, __) => const HelpScreen()),
      GoRoute(
        path: AppRoutes.helpTopic,
        builder: (_, s) => HelpTopicScreen(topic: s.extra! as FaqTopic),
      ),
      GoRoute(
        path: AppRoutes.cmsPage,
        builder: (_, s) => Text('PAGE ${s.uri.query}'),
      ),
      GoRoute(path: AppRoutes.about, builder: (_, __) => const Text('ABOUT')),
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
        storeFeaturesProvider.overrideWith(
          (ref) async => StoreFeatures(contactEnabled: contactEnabled),
        ),
        cmsRepositoryProvider.overrideWithValue(
          FakeCmsRepository(blocks: blocks),
        ),
        accountRepositoryProvider.overrideWithValue(
          account ?? FakeAccountRepository(),
        ),
        appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
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
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('shows channels, bundled topics, the form and legal pages', (
    tester,
  ) async {
    await _pump(tester, contact: _allChannels);

    expect(find.text(en.helpCentreTitle), findsOneWidget);
    expect(find.text(en.helpWhatsApp), findsOneWidget);
    expect(find.text(en.helpWhatsAppCaption), findsOneWidget);
    expect(find.text(en.helpCallUs), findsOneWidget);
    expect(find.text('+971 50 000 0000'), findsOneWidget);
    expect(find.text(en.helpEmailUs), findsOneWidget);

    // The bundled FAQ is used while the store has no `hm_app_faq` block.
    for (final topic in [
      en.helpTopicOrders,
      en.helpTopicReturns,
      en.helpTopicPayments,
      en.helpTopicAccount,
      en.helpTopicSelling,
    ]) {
      expect(find.text(topic), findsOneWidget);
    }

    expect(find.text(en.helpMessageTitle), findsOneWidget);
    // About + the footer's legal links, labelled as the admin wrote them.
    expect(find.text(en.accountAbout), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Cookies'), findsOneWidget);
    expect(find.text(en.helpAppVersion('1.0.0 (1)')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers only the channels the store publishes', (tester) async {
    await _pump(tester);
    expect(find.text(en.helpWhatsApp), findsOneWidget);
    expect(find.text(en.helpCallUs), findsNothing);
    expect(find.text(en.helpEmailUs), findsNothing);
  });

  testWidgets('the bundled FAQ makes no claims the app cannot keep', (
    tester,
  ) async {
    final faq = [
      en.helpA1, en.helpA2, en.helpA4, en.helpA5, en.helpA7, en.helpACancel,
      en.helpA8, en.helpAPayments, en.helpAGuest, en.helpADeleteAccount,
      en.helpASell,
    ].join(' ').toLowerCase();
    for (final claim in [
      'network international', 'tabby', 'tamara', 'visa', 'mastercard',
      'store page', 'badge', 'verified', '14 days', '24/7',
    ]) {
      expect(faq, isNot(contains(claim)), reason: claim);
    }
  });

  testWidgets('a topic opens its questions', (tester) async {
    await _pump(tester);
    await tester.tap(find.text(en.helpTopicOrders));
    await tester.pumpAndSettle();

    expect(find.text(en.helpQ4), findsOneWidget);
    // The first answer is open; the others expand on tap.
    expect(find.text(en.helpA4), findsOneWidget);
    expect(find.text(en.helpA7), findsNothing);
    await tester.tap(find.text(en.helpQ7));
    await tester.pumpAndSettle();
    expect(find.text(en.helpA7), findsOneWidget);
  });

  testWidgets('search lists matching answers across topics', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'guest');
    await tester.pumpAndSettle();

    expect(find.text(en.helpQGuest), findsOneWidget);
    expect(find.text(en.helpQ7), findsOneWidget); // its answer mentions guests
    expect(find.text(en.helpTopicOrders), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text(en.helpNoResults), findsOneWidget);
  });

  testWidgets('the FAQ comes from the hm_app_faq block when it exists', (
    tester,
  ) async {
    await _pump(
      tester,
      blocks: const {
        'hm_footer_legal': kLegalLinksBlock,
        'hm_app_faq':
            '<h2 data-icon="delivery">Delivery</h2>'
            '<h3>Do you deliver on Fridays?</h3><p>Yes.</p>',
      },
    );
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text(en.helpTopicOrders), findsNothing);
  });

  testWidgets('sends the contact form through contactUs', (tester) async {
    final account = FakeAccountRepository();
    await _pump(tester, account: account);

    final send = find.text(en.helpMessageSend);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    // Empty required fields block the send.
    expect(account.contactMessages, isEmpty);
    expect(find.text(en.validationRequired), findsWidgets);

    Finder field(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(field(en.helpMessageName), 'Sara Ahmed');
    await tester.enterText(field(en.helpMessageEmail), 'sara@example.com');
    await tester.enterText(field(en.helpMessageBody), 'Where is my order?');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(account.contactMessages.single, {
      'name': 'Sara Ahmed',
      'email': 'sara@example.com',
      'telephone': '',
      'comment': 'Where is my order?',
    });
    expect(find.text(en.helpMessageSent), findsWidgets);
  });

  testWidgets('no form when the store switched the contact form off', (
    tester,
  ) async {
    await _pump(tester, contactEnabled: false);
    expect(find.text(en.helpMessageTitle), findsNothing);
  });

  testWidgets('a legal row opens the CMS page natively', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'PAGE url=privacy-policy-cookie-restriction-mode&title=Privacy',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.text(ar.helpTopicOrders), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(ar.helpTopicOrders))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
