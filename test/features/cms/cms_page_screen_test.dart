import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/widgets/web_view_screen.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/cms_page.dart';
import 'package:hubmarket_app/features/cms/presentation/cms_page_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

final _privacy = CmsPage(
  identifier: 'privacy-policy-cookie-restriction-mode',
  title: 'Privacy Policy',
  urlKey: 'privacy-policy-cookie-restriction-mode',
  content:
      '<div class="privacy-policy cms-content">'
      '<p>This policy explains what we collect.</p>'
      '<h2 id="t1">What we collect</h2><p>Your name and address.</p>'
      '<h2 id="t2">How we use it</h2><p>To deliver your orders.</p>'
      '<h2 id="t3">Your choices</h2>'
      '<p>See <a href="#t1">what we collect</a> or our '
      '<a href="https://hub-market.magento2.click/en/customer-service/">customer service page</a>.</p>'
      '<ul><li>Delete your account from Privacy &amp; data.</li>'
      '<li>Switch marketing messages off in Notifications.</li>'
      '<li>Ask us for a copy of what we hold about you.</li>'
      '<li>Ask us to correct anything that is wrong.</li></ul>'
      '</div>',
);

final _customerService = CmsPage(
  identifier: 'customer-service',
  title: 'Customer Service',
  urlKey: 'customer-service',
  content: '<h2>Shipping and Delivery</h2><p>Delivery details.</p>',
);

FakeCmsRepository _cms() => FakeCmsRepository(
  pages: {'about-us': _customerService},
  pagesByUrl: {
    'privacy-policy-cookie-restriction-mode': _privacy,
    'customer-service': _customerService,
  },
);

Future<void> _pump(
  WidgetTester tester,
  String location, {
  String locale = 'en',
  FakeCmsRepository? cms,
  FakeCatalogRepository? catalog,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.cmsPage,
        builder: (context, state) => CmsPageScreen(
          identifier: state.uri.queryParameters['id'],
          url: state.uri.queryParameters['url'],
          title: state.uri.queryParameters['title'],
        ),
      ),
      for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
      GoRoute(
        path: AppRoutes.webview,
        builder: (_, s) =>
            Scaffold(body: Text('WEB ${(s.extra! as WebViewArgs).url}')),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      cmsRepositoryProvider.overrideWithValue(cms ?? _cms()),
      catalogRepositoryProvider.overrideWithValue(
        catalog ?? FakeCatalogRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(storeControllerProvider.notifier).loadStores();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
}

/// Fires the link run whose text is [label], as a tap on it would.
void _tapLink(WidgetTester tester, String label) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    TextSpan? hit;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == label && span.recognizer != null) {
        hit = span;
        return false;
      }
      return true;
    });
    if (hit != null) {
      (hit!.recognizer! as TapGestureRecognizer).onTap!();
      return;
    }
  }
  fail('no link "$label"');
}

void main() {
  testWidgets('renders a CMS page natively with section chips', (tester) async {
    await _pump(
      tester,
      AppRoutes.cmsPageByUrl('privacy-policy-cookie-restriction-mode'),
    );

    // Title from the page, content as native text, one chip per <h2>.
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('This policy explains what we collect.'), findsOneWidget);
    expect(find.text('What we collect'), findsNWidgets(2)); // chip + heading
    expect(find.text('How we use it'), findsNWidgets(2));
    expect(find.byIcon(HubIcons.share2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chip scrolls its section into view', (tester) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      AppRoutes.cmsPageByUrl('privacy-policy-cookie-restriction-mode'),
    );

    final chip = find.text('Your choices').first;
    final heading = find.text('Your choices').last;
    // The third chip sits past the screen edge; bring it into the row's view.
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(heading).dy;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(heading).dy, lessThan(before));
  });

  testWidgets('a same-site link to another CMS page opens it in the app', (
    tester,
  ) async {
    final cms = _cms();
    await _pump(
      tester,
      AppRoutes.cmsPageByUrl('privacy-policy-cookie-restriction-mode'),
      cms: cms,
      catalog: FakeCatalogRepository(
        resolved: (type: 'CMS_PAGE', uid: 'Mg==', urlKey: 'customer-service'),
      ),
    );

    _tapLink(tester, 'customer service page');
    await tester.pumpAndSettle();

    expect(cms.requestedUrls.last, 'customer-service');
    expect(find.text('Customer Service'), findsOneWidget);
    expect(find.text('Delivery details.'), findsOneWidget);
    expect(find.textContaining('WEB '), findsNothing);
  });

  testWidgets('an unknown page offers the storefront page instead', (
    tester,
  ) async {
    await _pump(tester, AppRoutes.cmsPageByUrl('no-such-page'));

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.linkNotFoundTitle), findsOneWidget);
    await tester.tap(find.text(l10n.webviewOpenInBrowser));
    await tester.pumpAndSettle();
    expect(
      find.text('WEB https://hub-market.magento2.click/uae-en/no-such-page'),
      findsOneWidget,
    );
  });

  testWidgets('opens a page by identifier and lays out right-to-left', (
    tester,
  ) async {
    await _pump(tester, AppRoutes.cmsPageById('about-us'), locale: 'ar');
    expect(find.text('Delivery details.'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Delivery details.'))),
      TextDirection.rtl,
    );
  });
}
