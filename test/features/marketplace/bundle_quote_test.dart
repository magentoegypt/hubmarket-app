import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/cart/domain/bundle_cart_request.dart';
import 'package:hubmarket_app/features/catalog/data/bundle_quote_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/bundle_product_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/bundle_fixtures.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import 'marketplace_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// The fitness pack of Figma 14b.
ProductDetail _pack() => ProductDetail(
  sku: 'HM-DEMO-BUNDLE-FITNESS',
  name: 'Home Fitness Starter Pack',
  urlKey: 'home-fitness-starter-pack',
  typeId: 'bundle',
  shortDescription:
      'Everything you need to start training at home — four essentials '
      'from one seller, bundled at a saving over buying them one by one.',
  regularPrice: aed(72),
  finalPrice: aed(60.56),
);

ProductDetail _kit() => const ProductDetail(
  sku: 'KIT-BUILDER',
  name: 'Kit Builder',
  urlKey: 'kit-builder',
  typeId: 'bundle',
);

Map<String, dynamic> _money(double value) => {
  'value': value,
  'currency': 'AED',
};

/// hmBundleQuote's answer: the cart's figure, or its refusal.
Map<String, dynamic> _quote({
  double? price,
  double? regular,
  String? message,
}) => {
  'hmBundleQuote': {
    'available': price != null,
    'message': message,
    'price': price == null ? null : _money(price),
    'regular_total': regular == null ? null : _money(regular),
    'saving': price == null || regular == null ? null : _money(regular - price),
    'discount_percent': price == null || regular == null
        ? 0
        : ((regular - price) * 100 / regular).round(),
  },
};

Map<String, Object> _answers(
  Map<String, dynamic> bundle, {
  Map<String, dynamic>? quote,
}) => {
  'HmProductMarketplace': {
    'products': {
      'items': [bundle],
    },
  },
  'HmBundleQuote': ?quote,
};

List<Request> _quotes(FakeHubAppClient client) => [
  for (final r in client.requests)
    if (operationNameOf(r) == 'HmBundleQuote') r,
];

void main() {
  setUpAll(loadAppFonts);

  group('hmBundleQuote', () {
    test(
      'the selections go inline with scalar variables, never an Hm type',
      () async {
        final client = fakeHubAppClient({
          'HmBundleQuote': _quote(price: 61, regular: 72),
        });
        final answer = await BundleQuoteRepository(client).quote(
          const BundleCartRequest(
            sku: 'KIT-BUILDER',
            quantity: 2,
            selections: [
              BundleSelectionInput(
                selectionUid: 'c2VsL3RvcA==',
                configurableOptionUids: ['Y29uZmlndXJhYmxlLzE0NC8xNjg='],
              ),
              BundleSelectionInput(selectionUid: 'c2VsL2JvdA==', quantity: 3),
            ],
          ),
        );

        final request = client.requests.single;
        expect(request.variables, {
          'sku': 'KIT-BUILDER',
          'quantity': 2.0,
          's0': 'c2VsL3RvcA==',
          'c0': ['Y29uZmlndXJhYmxlLzE0NC8xNjg='],
          's1': 'c2VsL2JvdA==',
          'q1': 3.0,
        });
        final printed = printNode(request.operation.document);
        expect(printed, isNot(contains('HmBundleSelectionInput')));
        expect(printed, contains(r'selection_uid: $s0'));
        expect(printed, contains(r'configurable_option_uids: $c0'));
        expect(printed, contains(r'quantity: $q1'));

        expect(answer.available, isTrue);
        expect(answer.quote!.total, aed(61));
        expect(answer.quote!.regular, aed(72));
        expect(answer.quote!.saving, aed(11));
        expect(answer.quote!.exact, isTrue);
      },
    );

    test('a package the cart would refuse comes back with the reason', () {
      final answer = bundleServerQuoteFromJson(
        _quote(
          message: 'The options you selected are not available.',
        )['hmBundleQuote'],
      );
      expect(answer.available, isFalse);
      expect(answer.message, 'The options you selected are not available.');
      expect(answer.quote, isNull);
    });
  });

  group('Figma 14b — the package priced by the server', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('the opening package is priced at once ($locale)', (
        tester,
      ) async {
        phoneView(tester, height: 1600);
        final key = GlobalKey();
        final public = fakeHubAppClient(
          _answers(fitnessPackJson(), quote: _quote(price: 61, regular: 72)),
        );
        await tester.pumpWidget(
          marketplaceHarness(
            locale: locale,
            location: AppRoutes.product('home-fitness-starter-pack'),
            catalogRepository: DetailRepository(_pack()),
            publicClient: public,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'bundle_quote_$locale');

        final l10n = lookupAppLocalizations(Locale(locale));
        final quotes = _quotes(public);
        expect(quotes, hasLength(1));
        expect(quotes.single.variables['sku'], 'HM-DEMO-BUNDLE-FITNESS');
        expect(
          quotes.single.variables.keys,
          containsAll(['s0', 's1', 's2', 's3']),
        );
        // The cart's figure, not price_range's 60.56.
        expect(find.text('AED 61'), findsNWidgets(2)); // price + total
        expect(find.text(l10n.bundleYouSave('AED 11')), findsOneWidget);
        expect(find.text(l10n.bundleDiscountBadge(15)), findsOneWidget);
        expect(find.text(l10n.bundleEstimateNote), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a changed package is priced once it settles, and the estimate '
        'note goes', (tester) async {
      phoneView(tester, height: 1800);
      final answers = _answers(kitBuilderJson());
      final public = fakeHubAppClient(answers);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('kit-builder'),
          catalogRepository: DetailRepository(_kit()),
          publicClient: public,
        ),
      );
      await tester.pumpAndSettle();
      // Incomplete (no size, no mat): nothing to price.
      expect(_quotes(public), isEmpty);

      await tester.tap(find.text(_en.bundleMoreItems(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.bundleChoose('Mat')));
      await tester.pumpAndSettle();
      answers['HmBundleQuote'] = _quote(price: 67.5, regular: 72);
      // Not the cheapest package: price_range can't price it.
      await tester.tap(find.text('Pro Mat'));
      await tester.pump();
      await tester.pump();

      // The estimate first, while the package settles.
      expect(find.text(_en.bundleEstimateNote), findsOneWidget);
      expect(_quotes(public), isEmpty);

      await tester.pump(BundleProductScreen.quoteDelay);
      await tester.pumpAndSettle();

      final quote = _quotes(public).single;
      expect(quote.variables['s0'], 'c2VsL3RvcA==');
      expect(quote.variables['c0'], ['Y29uZmlndXJhYmxlLzE0NC8xNjc=']);
      expect(quote.variables['s1'], 'c2VsL3Bybw==');
      expect(find.text('AED 67.50'), findsNWidgets(2));
      expect(find.text(_en.bundleEstimateNote), findsNothing);

      // Two quick changes: one request, for the last package.
      final bottleRow = find
          .ancestor(of: find.text('Water Bottle'), matching: find.byType(Row))
          .first;
      answers['HmBundleQuote'] = _quote(price: 70.2, regular: 75);
      await tester.tap(
        find.descendant(of: bottleRow, matching: find.byIcon(HubIcons.plus)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.descendant(of: bottleRow, matching: find.byIcon(HubIcons.plus)),
      );
      await tester.pump(BundleProductScreen.quoteDelay);
      await tester.pumpAndSettle();

      expect(_quotes(public), hasLength(2));
      expect(_quotes(public).last.variables['q2'], 4.0);
      expect(find.text('AED 70.20'), findsNWidgets(2));
    });

    testWidgets('a package the cart would refuse keeps the estimate and says '
        'why', (tester) async {
      phoneView(tester, height: 1300);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('home-fitness-starter-pack'),
          catalogRepository: DetailRepository(_pack()),
          publicAnswers: _answers(
            fitnessPackJson(),
            quote: _quote(message: 'Sprite Stasis Ball 55 cm is out of stock.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sprite Stasis Ball 55 cm is out of stock.'),
        findsOneWidget,
      );
      // price_range's own figure for the cheapest package.
      expect(find.text('AED 60.56'), findsNWidgets(2));
    });

    testWidgets('a HubApp without the quote: the estimate, as before', (
      tester,
    ) async {
      phoneView(tester, height: 1300);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('home-fitness-starter-pack'),
          catalogRepository: DetailRepository(_pack()),
          publicAnswers: {
            ..._answers(fitnessPackJson()),
            'HmBundleQuote': hubAppMissingResponse('hmBundleQuote'),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AED 60.56'), findsNWidgets(2));
      expect(find.text(_en.bundleYouSave('AED 11.44')), findsOneWidget);
    });

    testWidgets('the quantity is priced too (tier prices)', (tester) async {
      phoneView(tester, height: 1300);
      final answers = _answers(
        fitnessPackJson(),
        quote: _quote(price: 61, regular: 72),
      );
      final public = fakeHubAppClient(answers);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('home-fitness-starter-pack'),
          catalogRepository: DetailRepository(_pack()),
          publicClient: public,
        ),
      );
      await tester.pumpAndSettle();

      answers['HmBundleQuote'] = _quote(price: 58, regular: 72);
      await tester.tap(find.byIcon(HubIcons.plus).last);
      await tester.pump(BundleProductScreen.quoteDelay);
      await tester.pumpAndSettle();

      expect(_quotes(public).last.variables['quantity'], 2.0);
      expect(find.text('AED 58'), findsNWidgets(2));
    });
  });
}
