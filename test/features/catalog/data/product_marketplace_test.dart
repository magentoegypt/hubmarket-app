import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/data/product_marketplace_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import '../../../support/bundle_fixtures.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/marketplace_fakes.dart';

void main() {
  group('productMarketplaceFromJson', () {
    test('reads the seller and a bundle', () {
      final marketplace = marketplaceOf(fitnessPackJson());

      expect(marketplace.seller!.name, 'Test 1');
      expect(marketplace.seller!.code, 'test-1');
      final bundle = marketplace.bundle!;
      expect(bundle.dynamicPrice, isTrue);
      expect(bundle.options, hasLength(4));
      expect(bundle.minFinal, const Money(amount: 60.56, currency: 'AED'));
      expect(bundle.hasSinglePrice, isTrue);
      final brick = bundle.options[2].selections.single.child!;
      expect(brick.finalPrice, const Money(amount: 4.25, currency: 'AED'));
      expect(brick.regularPrice, const Money(amount: 5, currency: 'AED'));
    });

    test('a product that is not a bundle has no bundle', () {
      final marketplace = productMarketplaceFromJson({
        '__typename': 'SimpleProduct',
        'sku': 'DRESS',
        'hm_seller': sellerJson('loly', 'loly store', rating: 4.3),
      });

      expect(marketplace.bundle, isNull);
      expect(marketplace.seller!.rating, 4.3);
    });

    test('an unapproved seller comes back as no seller', () {
      final json = fitnessPackJson(sellerCode: null);
      expect(marketplaceOf(json).seller, isNull);
    });

    test('a configurable child keeps its sizes and variant prices', () {
      final top = bundleOf(kitBuilderJson()).options.first.selections.first;
      final child = top.child!;

      expect(child.options.single.values.map((v) => v.label), ['S', 'M']);
      expect(child.variantFor({'size': 168})!.finalPrice!.amount, 34);
      expect(child.optionUidsFor({'size': 167}), ['Y29uZmlndXJhYmxlLzE0NC8xNjc=']);
      expect(child.optionUidsFor(const {}), isNull);
    });
  });

  test('the GET request stays well inside the URL limit', () {
    // It goes as GET, in the query string (nginx: 8 KB request line); the
    // client adds a __typename per selection set on top.
    final compact = compactGraphQLDocument(ProductMarketplaceQueries.document);
    final encoded = Uri.encodeQueryComponent(compact);
    expect(encoded.length, lessThan(4500), reason: encoded);
  });

  group('ProductMarketplaceRepository', () {
    test('asks the public client for sellers and bundle options', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': {
          'products': {
            'items': [fitnessPackJson()],
          },
        },
      });

      final result = await ProductMarketplaceRepository(
        server,
      ).fetch('home-fitness-starter-pack');

      final request = server.requests.single;
      expect(request.variables, {'urlKey': 'home-fitness-starter-pack'});
      expect(result!.bundle!.options, hasLength(4));
    });

    test('a server without hm_seller is HubAppMissing', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': hubAppMissingResponse(
          'hm_seller',
          type: 'ProductInterface',
        ),
      });

      await expectLater(
        ProductMarketplaceRepository(server).fetch('dress'),
        throwsA(isA<HubAppMissing>()),
      );
    });
  });
}
