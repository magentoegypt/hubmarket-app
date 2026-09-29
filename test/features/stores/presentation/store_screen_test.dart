import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_card.dart';

import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';
import '../stores_harness.dart';

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
    expect(find.text('Modern furniture for homes and offices'), findsOneWidget);
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
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('June 2023'), findsOneWidget);
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

    await tester.tap(find.byIcon(Icons.tune));
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
    expect(find.text('Modern furniture for homes and offices'), findsNothing);

    page.complete(miaStoreData());
    await tester.pumpAndSettle();
    expect(find.text('Modern furniture for homes and offices'), findsOneWidget);
    expect(find.text('Policies'), findsOneWidget);
  });

  testWidgets('opened first (a deep link), back goes Home', (tester) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/store/MIA', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
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
    expect(find.text('يونيو 2023'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
