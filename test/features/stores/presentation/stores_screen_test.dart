import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/stores/presentation/widgets/store_widgets.dart';

import '../../../support/hubapp_fakes.dart';
import '../../../support/store_fixtures.dart';
import '../stores_harness.dart';

/// The list requests (not the featured banner's).
List<RecordedRequest> _lists(FakeStoresBackend backend) => [
  for (final r in backend.of('HmStores'))
    if (r.variables['featured'] != true) r,
];

void main() {
  testWidgets('Figma 12: search, chips, the featured seller and every seller', (
    tester,
  ) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stores'), findsOneWidget);
    expect(find.text('Search stores'), findsOneWidget);
    // All, then Home's top-level categories that hold products.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Furniture'), findsOneWidget);
    expect(find.text('Fashion'), findsOneWidget);
    expect(find.text('Promotions'), findsNothing);

    expect(find.text('FEATURED STORE'), findsOneWidget);
    expect(find.text('Visit'), findsOneWidget);
    // The star is an icon: Tajawal and DM Sans have no ★ glyph.
    expect(find.text('\uFFFC 4.8 · 38 products'), findsOneWidget);

    expect(find.text('All stores'), findsOneWidget);
    expect(find.text('Top rated'), findsOneWidget);
    expect(find.byType(StoreListTile), findsNWidgets(5));
    expect(find.text('loly store'), findsOneWidget);
    expect(find.text('64 products'), findsOneWidget);
    expect(find.text('(88 reviews)'), findsOneWidget);
    // An unrated seller says so rather than showing a zero.
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsNWidgets(6));

    final list = _lists(backend).single;
    expect(list.document, contains('sort: TOP_RATED'));
    expect(list.variables['pageSize'], 20);
    final featured = backend
        .of('HmStores')
        .firstWhere((r) => r.variables['featured'] == true);
    expect(featured.variables['pageSize'], 1);
    // The banner photo comes from the featured seller's page.
    expect(backend.of('HmStore').single.variables['code'], 'MIA');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category chip narrows the list and the banner', (
    tester,
  ) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();

    expect(_lists(backend).last.variables['categoryId'], 74);
    expect(
      backend.of('HmStores').last.variables,
      containsPair('categoryId', 74),
    );
    expect(
      backend
          .of('HmStores')
          .where((r) => r.variables['featured'] == true)
          .last
          .variables['categoryId'],
      74,
    );
  });

  testWidgets('the sort sheet offers every order the backend has', (
    tester,
  ) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Top rated'));
    await tester.pumpAndSettle();
    for (final label in ['Featured', 'Newest', 'Name: A–Z', 'Most products']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();

    expect(_lists(backend).last.document, contains('sort: NEWEST'));
    expect(find.text('Newest'), findsOneWidget);
  });

  testWidgets('the store search asks by name and drops the banner', (
    tester,
  ) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'mia ');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_lists(backend).last.variables['name'], 'mia');
    expect(find.text('FEATURED STORE'), findsNothing);
  });

  testWidgets('a seller opens its store page, the banner too', (tester) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers());
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ENARA'));
    await tester.pumpAndSettle();
    expect(backend.of('HmStore').last.variables['code'], 'ENARA');
  });

  testWidgets('a search that finds no store says so', (tester) async {
    await phoneSurface(tester);
    final backend = FakeStoresBackend(
      (r) => r.variables['name'] != null
          ? storesData(const [])
          : storesAnswers()(r),
    );
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No stores found'), findsOneWidget);
    expect(find.text('No store matches “\u2068zzz\u2069”.'), findsOneWidget);
  });

  group('fallback', () {
    testWidgets('without the Hub Market App: coming soon, nothing asked', (
      tester,
    ) async {
      await phoneSurface(tester);
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(
          location: '/stores',
          backend: backend,
          hubApp: const HubAppState.unavailable(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('All stores'), findsNothing);
      expect(backend.requests, isEmpty);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Home'));
      await tester.pumpAndSettle();
      expect(find.text('/home'), findsOneWidget);
    });

    testWidgets('while the probe can\'t tell, the same', (tester) async {
      await phoneSurface(tester);
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(
          location: '/stores',
          backend: backend,
          hubApp: const HubAppState.unknown(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coming soon'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('a server without the seller API: coming soon', (tester) async {
      await phoneSurface(tester);
      final backend = FakeStoresBackend(
        (_) => hubAppMissingResponse('hmStores'),
      );
      await tester.pumpWidget(
        storesHarness(location: '/stores', backend: backend),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('FEATURED STORE'), findsNothing);
    });
  });

  testWidgets('Arabic: the list reads right to left', (tester) async {
    await phoneSurface(tester, height: 1400);
    final backend = FakeStoresBackend(storesAnswers(store: 'ar'));
    await tester.pumpWidget(
      storesHarness(location: '/stores', backend: backend, locale: 'ar'),
    );
    await tester.pumpAndSettle();

    expect(find.text('المتاجر'), findsOneWidget);
    expect(find.text('متجر مميز'), findsOneWidget);
    expect(find.text('كل المتاجر'), findsOneWidget);
    expect(find.text('الأعلى تقييمًا'), findsOneWidget);
    expect(find.text('متجر لولي'), findsOneWidget);
    // The name sits at the right edge of its card.
    final tile = tester.getRect(find.byType(StoreListTile).at(1));
    final name = tester.getRect(find.text('متجر لولي'));
    expect(name.right, greaterThan(tile.center.dx));
    expect(tester.takeException(), isNull);
  });

  group('with the P3.1 seller fields (the server lists vendors)', () {
    const vendors = HubAppState.available(kVendorsHmAppConfig);

    testWidgets('12: chips with their seller counts, cards with a category', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1400);
      final semantics = tester.ensureSemantics();
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(location: '/stores', backend: backend, hubApp: vendors),
      );
      await tester.pumpAndSettle();

      expect(backend.of('HmStoreCategories'), hasLength(1));
      // The seller API's chips, in menu order, each with its count.
      final chips = find.byType(StorePill);
      expect(
        find.descendant(of: chips.first, matching: find.text('All')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips.first, matching: find.text('5')),
        findsOneWidget,
      );
      expect(find.text('Grocery'), findsOneWidget);
      expect(find.bySemanticsLabel('Grocery, 1 store'), findsOneWidget);
      // Every card names the seller's category before its products.
      expect(find.text('Fashion · 64 products'), findsOneWidget);
      expect(find.text('Lighting · 19 products'), findsOneWidget);
      // The banner too.
      expect(
        find.text('Furniture · ￼ 4.8 · 38 products'),
        findsOneWidget,
      );
      expect(
        _lists(backend).single.document,
        contains('...HmStoreCardExtras'),
      );
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chip from the seller API narrows the list by its id', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1400);
      final backend = FakeStoresBackend(storesAnswers());
      await tester.pumpWidget(
        storesHarness(location: '/stores', backend: backend, hubApp: vendors),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grocery'));
      await tester.pumpAndSettle();

      expect(_lists(backend).last.variables['categoryId'], 38);
    });

    testWidgets('the chips failing to load: Home\'s categories, no counts', (
      tester,
    ) async {
      await phoneSurface(tester, height: 1400);
      final backend = FakeStoresBackend(
        (r) => r.operation == 'HmStoreCategories'
            ? Exception('offline (test)')
            : storesAnswers()(r),
      );
      await tester.pumpWidget(
        storesHarness(location: '/stores', backend: backend, hubApp: vendors),
      );
      await tester.pumpAndSettle();

      expect(find.text('Furniture'), findsWidgets);
      expect(find.text('Promotions'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StorePill).first,
          matching: find.text('5'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
