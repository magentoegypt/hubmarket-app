import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/util/launch.dart';
import 'package:hubmarket_app/core/widgets/hub_top_bar.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_card.dart';

import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';
import '../stores_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

Finder _rich(String text) => find.textContaining(text, findRichText: true);

/// Follows the CMS link whose text is [label].
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
  testWidgets('Figma 13: header, figures, tabs and the seller\'s products', (
    tester,
  ) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    expect(backend.of('HmStore').single.variables['code'], 'MIA');
    expect(find.text('MIA CO'), findsWidgets);
    // Figma 13's header has no description line: the About tab carries it.
    expect(find.text('Modern furniture for homes and offices'), findsNothing);
    // The star is an icon: Tajawal and DM Sans have no ★ glyph.
    expect(find.text('4.8 \uFFFC'), findsOneWidget);
    expect(find.text('126 reviews'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('Products'), findsWidgets);
    expect(find.text('2023'), findsOneWidget);
    expect(find.text('Selling since'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Policies'), findsOneWidget);
    // No source in the seller API for these.
    expect(find.text('Reviews'), findsNothing);
    expect(find.text('Contact vendor'), findsNothing);

    expect(find.text('Search MIA CO products'), findsOneWidget);
    expect(find.text('4 products'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.byType(ProductCard), findsNWidgets(4));
    expect(find.text('Corner Sofa Bed'), findsOneWidget);

    // The seller's products: vendor_id, FULL match.
    final products = backend.of('Products').first;
    expect(products.variables['filter'], {
      'vendor_id': {'match': '12', 'match_type': 'FULL'},
    });
    expect(find.byIcon(HubIcons.share2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the header buttons sit below the status bar of an edge-to-edge phone',
    (tester) async {
      // Android 15+ draws under the status bar: 24 logical pixels of it here
      // (48 physical at 2x). The page's zero-size scaffold app bar hides that
      // inset from its body, so the back, search and share buttons used to
      // sit under the clock.
      await phoneSurface(tester, height: 1400);
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: 48);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(location: '/store/MIA', backend: backend),
      );
      await tester.pumpAndSettle();

      final back = find.byIcon(HubIcons.arrowLeft);
      expect(back, findsOneWidget);
      expect(tester.getTopLeft(back).dy, greaterThanOrEqualTo(24));
      expect(
        tester.getTopLeft(find.byIcon(HubIcons.search).first).dy,
        greaterThanOrEqualTo(24),
      );
    },
  );

  testWidgets('13b About: text, figures, policy summaries, categories', (
    tester,
  ) async {
    await phoneSurface(tester, height: 1800);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('About the store'), findsOneWidget);
    expect(_rich('MIA CO designs and sells modern furniture'), findsOneWidget);
    expect(find.text('Products listed'), findsOneWidget);
    expect(find.text('Next day'), findsOneWidget);
    expect(find.text('Typical dispatch'), findsOneWidget);
    expect(find.text('Average rating'), findsOneWidget);
    expect(find.text('Customer reviews'), findsOneWidget);
    // Figma 13b: when the seller started selling is in the store row under
    // the bar, not a tile.
    expect(find.textContaining('Selling since Jun 2023'), findsOneWidget);
    expect(find.text('June 2023'), findsNothing);
    expect(find.text('Store policies'), findsOneWidget);
    expect(find.text('Shipping policy'), findsOneWidget);
    expect(
      find.textContaining('Delivered within 72 hours across the UAE.'),
      findsOneWidget,
    );
    expect(find.text('Refund & exchange policy'), findsOneWidget);
    // The most specific of the seller's menu categories.
    expect(find.text('Categories in this store'), findsOneWidget);
    expect(find.text('Home Furniture'), findsOneWidget);
    expect(find.text('Living Room Sets'), findsOneWidget);
    expect(find.text('Furniture'), findsNothing);
    // Neither the frame's Sales figure nor its Call button has a source.
    expect(find.text('Sales'), findsNothing);
    expect(find.textContaining('Call'), findsNothing);
    expect(tester.takeException(), isNull);

    // A category lists the seller's products in it.
    await tester.tap(find.text('Home Furniture'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductCard), findsWidgets);
    expect(backend.of('Products').last.variables['filter'], {
      'vendor_id': {'match': '12', 'match_type': 'FULL'},
      'category_uid': {
        'in': [kHomeFurnitureUid],
      },
    });
  });

  testWidgets('Figma 13 / 13b: Products is the front page, the other tabs are '
      'the inside pages', (tester) async {
    await phoneSurface(tester, height: 1400);
    await tester.pumpWidget(
      storesHarness(
        location: '/store/MIA',
        backend: FakeStoresBackend(storesAnswers()),
        hubApp: const HubAppState.available(kVendorsHmAppConfig),
      ),
    );
    await tester.pumpAndSettle();

    // The front page: the banner is the header, there is no app bar.
    expect(find.byType(HubTopBar), findsNothing);
    expect(find.text('Contact vendor'), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    // The inside page: the bar names the store, the store row says where it is
    // and since when it sells, with its rating in a pill.
    final bar = find.byType(HubTopBar);
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.text('MIA CO')),
      findsOneWidget,
    );
    expect(
      find.text('Dubai, United Arab Emirates · Selling since Jun 2023'),
      findsOneWidget,
    );
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('Contact vendor'), findsNothing);
    // Four equal columns, the labels centred in them.
    for (final (i, label) in [
      'Products',
      'Reviews',
      'About',
      'Policies',
    ].indexed) {
      expect(
        tester.getCenter(find.text(label)).dx,
        closeTo(390 * (2 * i + 1) / 8, 1),
        reason: label,
      );
    }

    // Products brings the front page back.
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(find.byType(HubTopBar), findsNothing);
    expect(find.text('Contact vendor'), findsOneWidget);
    expect(find.text('Search MIA CO products'), findsOneWidget);
  });

  testWidgets('Policies: the seller\'s HTML drawn natively; links stay in', (
    tester,
  ) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(
        location: '/store/MIA',
        backend: backend,
        resolved: (type: 'CMS_PAGE', uid: '', urlKey: 'return-policy'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Policies'));
    await tester.pumpAndSettle();

    expect(find.text('Shipping policy'), findsOneWidget);
    expect(_rich('free over AED 200'), findsOneWidget);
    expect(find.text('Refund & exchange policy'), findsOneWidget);
    expect(_rich('within 7 days in original condition'), findsOneWidget);

    _tapLink(tester, 'our return policy');
    await tester.pumpAndSettle();
    expect(find.text('CMS return-policy'), findsOneWidget);
  });

  testWidgets('the store search, filters and sort keep to the seller', (
    tester,
  ) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sofa');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    var last = backend.of('Products').last.variables;
    expect(last['search'], 'sofa');
    expect(last['filter'], {
      'vendor_id': {'match': '12', 'match_type': 'FULL'},
    });
    // Searching, the default order is relevance.
    expect(find.text('Relevance'), findsOneWidget);

    await tester.tap(find.text('Relevance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price: High to Low'));
    await tester.pumpAndSettle();
    last = backend.of('Products').last.variables;
    expect(last['sort'], {'price': 'DESC'});
    expect(last['search'], 'sofa');

    await tester.tap(find.byIcon(HubIcons.slidersHorizontal));
    await tester.pumpAndSettle();
    // The seller's own facet is not offered.
    expect(find.text('Vendor Id'), findsNothing);
    expect(find.text('Category'), findsOneWidget);
  });

  testWidgets('a seller without policies has no Policies tab', (tester) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(
      (r) => r.operation == 'HmStore'
          ? miaStoreData(policies: false)
          : storesAnswers()(r),
    );
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    expect(find.text('Policies'), findsNothing);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Store policies'), findsNothing);
  });

  testWidgets('the list\'s card paints the header before the page loads', (
    tester,
  ) async {
    await phoneSurface(tester);
    final page = Completer<Object?>();
    final backend = FakeStoresBackend(
      (r) => r.operation == 'HmStore' ? page.future : storesAnswers()(r),
    );
    await tester.pumpWidget(
      storesHarness(
        location: '/store/MIA',
        backend: backend,
        extra: HmStoreCard.fromJson(miaCard()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('MIA CO'), findsWidgets);
    // The star is an icon: Tajawal and DM Sans have no ★ glyph.
    expect(find.text('4.8 \uFFFC'), findsOneWidget);
    // The products start at once, from the card's seller id.
    expect(backend.of('Products'), isNotEmpty);
    // Only the full profile knows the seller publishes policies.
    expect(find.text('Policies'), findsNothing);

    page.complete(miaStoreData());
    await tester.pumpAndSettle();
    expect(find.text('Policies'), findsOneWidget);
  });

  testWidgets('opened first (a deep link), back goes Home', (tester) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(HubIcons.arrowLeft));
    await tester.pumpAndSettle();
    expect(find.text('/home'), findsOneWidget);
  });

  testWidgets('a code that is no approved seller: store not found', (
    tester,
  ) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(
      (r) => r.operation == 'HmStore' ? {'hmStore': null} : storesAnswers()(r),
    );
    await tester.pumpWidget(
      storesHarness(location: '/store/gone', backend: backend),
    );
    await tester.pumpAndSettle();

    expect(find.text('Store not found'), findsOneWidget);
    expect(backend.of('Products'), isEmpty);
  });

  testWidgets('fallback: without the Hub Market App, coming soon', (
    tester,
  ) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(
        location: '/store/MIA',
        backend: backend,
        hubApp: const HubAppState.unavailable(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coming soon'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('a server without the seller API: coming soon', (tester) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend((_) => hubAppMissingResponse('hmStore'));
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('Arabic: the store page reads right to left', (tester) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers(store: 'ar'));
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend, locale: 'ar'),
    );
    await tester.pumpAndSettle();

    expect(find.text('ميا كو'), findsWidgets);
    expect(find.text('المنتجات'), findsOneWidget);
    expect(find.text('عن المتجر'), findsOneWidget);
    expect(find.text('السياسات'), findsOneWidget);
    expect(find.text('ابحث في منتجات ميا كو'), findsOneWidget);
    // The tabs start at the right.
    final products = tester.getRect(find.text('المنتجات'));
    final policies = tester.getRect(find.text('السياسات'));
    expect(products.left, greaterThan(policies.left));

    await tester.tap(find.text('عن المتجر'));
    await tester.pumpAndSettle();
    expect(find.text('مدة التجهيز المعتادة'), findsOneWidget);
    expect(find.textContaining('يبيع منذ يونيو 2023'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('with the P3.1 seller fields (the server lists vendors)', () {
    const vendors = HubAppState.available(kVendorsHmAppConfig);

    /// Records what "Contact vendor" and "Call" would open.
    List<Uri> recordLaunches(List<Override> overrides) {
      final launched = <Uri>[];
      overrides.add(
        externalUriLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return true;
        }),
      );
      return launched;
    }

    testWidgets('13: the location line, Contact vendor and a Reviews tab', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1400);
      final overrides = <Override>[];
      final launched = recordLaunches(overrides);
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(
          location: '/store/MIA',
          backend: backend,
          hubApp: vendors,
          overrides: overrides,
        ),
      );
      await tester.pumpAndSettle();

      expect(backend.of('HmStore').single.document, contains('HmStorePageExtras'));
      // The website's location line, then the seller's category (Figma 13).
      expect(
        find.text('Dubai, United Arab Emirates · Furniture'),
        findsOneWidget,
      );
      expect(find.text('Reviews'), findsOneWidget);
      // Tabs in the frame's order.
      final products = tester.getRect(find.text('Products').last);
      final reviews = tester.getRect(find.text('Reviews'));
      final about = tester.getRect(find.text('About'));
      expect(products.left, lessThan(reviews.left));
      expect(reviews.left, lessThan(about.left));
      // The product cards name the seller, as every listing does now.
      expect(backend.of('Products').last.document, contains('...HmCardSeller'));
      expect(
        find.descendant(
          of: find.byType(ProductCard),
          matching: find.text('MIA CO'),
        ),
        findsNWidgets(4),
      );

      // Contact vendor dials the number the website's button dials.
      await tester.tap(find.text('Contact vendor'));
      await tester.pumpAndSettle();
      expect(launched, [Uri.parse('tel:+971501234567')]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Reviews: the rating, this store view\'s reviews and their products', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1600);
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(location: '/store/MIA', backend: backend, hubApp: vendors),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(backend.of('HmStoreReviews').single.variables, {
        'code': 'MIA',
        'pageSize': 20,
        'currentPage': 1,
      });
      // The seller's figures: every approved review of its products — the
      // store row's pill and the summary card.
      expect(find.text('4.8'), findsNWidgets(2));
      expect(find.text('126 reviews'), findsWidgets);
      expect(find.text('Sara K.'), findsOneWidget);
      expect(find.text('Great sofa'), findsOneWidget);
      expect(
        find.text('Comfortable and well made, delivered on time.'),
        findsOneWidget,
      );
      expect(find.text('20 Sep 2026'), findsOneWidget);
      expect(find.text('Omar'), findsOneWidget);
      expect(find.text('Old Lamp'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A reviewed product the storefront lists opens its page …
      await tester.tap(find.text('Corner Sofa Bed').last);
      await tester.pumpAndSettle();
      expect(find.text('PDP sofabed123'), findsOneWidget);
    });

    testWidgets('a product no longer listed is named, not opened', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1600);
      await tester.pumpWidget(
        storesHarness(
          location: '/store/MIA',
          backend: FakeStoresBackend(storesAnswers()),
          hubApp: vendors,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Old Lamp'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PDP'), findsNothing);
    });

    testWidgets('reviews written only on the other store view: said so', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1400);
      final backend = FakeStoresBackend(
        (r) => r.operation == 'HmStoreReviews'
            ? miaReviewsData(none: true)
            : storesAnswers()(r),
      );
      await tester.pumpWidget(
        storesHarness(location: '/store/MIA', backend: backend, hubApp: vendors),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
      expect(
        find.text("This store's reviews were written in the other language."),
        findsOneWidget,
      );
    });

    testWidgets('13b About: the Sales figure and Call', (tester) async {
      await phoneSurface(tester, height: 2000);
      final overrides = <Override>[];
      final launched = recordLaunches(overrides);
      await tester.pumpWidget(
        storesHarness(
          location: '/store/MIA',
          backend: FakeStoresBackend(storesAnswers()),
          hubApp: vendors,
          overrides: overrides,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      expect(find.text('1,240'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      await tester.tap(find.text('Call MIA CO'));
      await tester.pumpAndSettle();
      expect(launched, [Uri.parse('tel:+971501234567')]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no phone published: no Contact vendor, no Call', (
      tester,
    ) async {
      await phoneSurface(tester, height: 2000);
      final backend = FakeStoresBackend((r) {
        final answer = storesAnswers()(r);
        if (r.operation == 'HmStore') {
          (answer as Map<String, dynamic>)['hmStore']['contact'] = null;
        }
        return answer;
      });
      await tester.pumpWidget(
        storesHarness(location: '/store/MIA', backend: backend, hubApp: vendors),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contact vendor'), findsNothing);
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Call'), findsNothing);
    });

    testWidgets('Arabic: Contact vendor and the Reviews tab read right to left', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1400);
      await tester.pumpWidget(
        storesHarness(
          location: '/store/MIA',
          backend: FakeStoresBackend(storesAnswers(store: 'ar')),
          hubApp: vendors,
          locale: 'ar',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تواصل مع البائع'), findsOneWidget);
      expect(find.text('دبي، الإمارات العربية المتحدة · أثاث'), findsOneWidget);
      final products = tester.getRect(find.text('المنتجات'));
      final reviews = tester.getRect(find.text('التقييمات'));
      expect(products.left, greaterThan(reviews.left));

      await tester.tap(find.text('التقييمات'));
      await tester.pumpAndSettle();
      expect(find.text('سارة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
