import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/hm_link_navigation.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_models.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';

import '../support/fakes.dart';

HmLink _link(
  HmLinkType type, {
  String? uid,
  String? code,
  String url = 'https://hub-market.magento2.click/en/x.html',
}) => HmLink(type: type, url: url, uid: uid, code: code);

void main() {
  group('hmLinkRoute', () {
    test('every link type has its native screen', () {
      expect(
        hmLinkRoute(_link(HmLinkType.category, uid: 'MTQw')),
        '/category/MTQw',
      );
      expect(
        hmLinkRoute(_link(HmLinkType.product, code: 'corner-sofa')),
        '/product/corner-sofa',
      );
      expect(
        hmLinkRoute(_link(HmLinkType.cmsPage, code: 'about-us')),
        '/page?id=about-us',
      );
      expect(hmLinkRoute(_link(HmLinkType.store, code: 'loly')), '/store/loly');
      expect(hmLinkRoute(_link(HmLinkType.stores)), '/stores');
      expect(
        hmLinkRoute(_link(HmLinkType.brand, code: 'samsung')),
        '/brand/samsung',
      );
      expect(hmLinkRoute(_link(HmLinkType.brands)), '/brands');
      expect(hmLinkRoute(_link(HmLinkType.bundles)), '/bundles');
      expect(hmLinkRoute(_link(HmLinkType.deals)), '/deals');
      expect(hmLinkRoute(_link(HmLinkType.search, code: 'rice')), '/search');
    });

    test('no route without the uid/code a type needs, or for EXTERNAL', () {
      expect(hmLinkRoute(_link(HmLinkType.category)), isNull);
      expect(hmLinkRoute(_link(HmLinkType.product, code: ' ')), isNull);
      expect(hmLinkRoute(_link(HmLinkType.store)), isNull);
      expect(hmLinkRoute(_link(HmLinkType.external)), isNull);
      expect(hmLinkRoute(_link(HmLinkType.unknown)), isNull);
    });

    test('codes are URL-safe in the path', () {
      expect(
        hmLinkRoute(_link(HmLinkType.store, code: 'a b/c')),
        '/store/a%20b%2Fc',
      );
    });
  });

  testWidgets('openHmLink pushes the screen, carrying titles and search text', (
    tester,
  ) async {
    final pushed = <(String, Object?)>[];
    Widget stub(BuildContext context, GoRouterState state) {
      pushed.add((state.uri.toString(), state.extra));
      return const Scaffold();
    }

    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              capturedContext = context;
              return const Scaffold();
            },
          ),
        ),
        for (final p in ['/category/:uid', '/search', '/page', '/deals'])
          GoRoute(path: p, builder: stub),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    Future<void> open(HmLink link, {String? title}) async {
      await openHmLink(capturedContext, capturedRef, link, title: title);
      await tester.pumpAndSettle();
      router.go('/');
      await tester.pumpAndSettle();
    }

    await open(_link(HmLinkType.category, uid: 'MTQw'), title: 'Fashion');
    await open(_link(HmLinkType.search, code: 'rice'));
    await open(_link(HmLinkType.cmsPage, code: 'about-us'), title: 'About');
    await open(_link(HmLinkType.deals));

    expect(pushed, [
      ('/category/MTQw', 'Fashion'),
      ('/search', 'rice'),
      ('/page?id=about-us&title=About', null),
      ('/deals', null),
    ]);
  });
}
