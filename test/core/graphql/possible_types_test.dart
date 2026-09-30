import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/graphql/possible_types.dart';

/// The shape of the product page's "You may also like" read: a list typed
/// `ProductInterface`, selected through a fragment on the interface.
const _document = r'''
query Related($sku: String!) {
  products(filter: { sku: { eq: $sku } }) {
    items {
      sku
      related_products { ...LinkedProductFields }
    }
  }
}
fragment LinkedProductFields on ProductInterface {
  uid
  name
  url_key
}
''';

Map<String, dynamic> _data() => {
  '__typename': 'Query',
  'products': {
    '__typename': 'Products',
    'items': [
      {
        '__typename': 'SimpleProduct',
        'sku': 'MAIN',
        'related_products': [
          {
            '__typename': 'SimpleProduct',
            'uid': 'MQ==',
            'name': 'Dining Chair',
            'url_key': 'dining-chair',
          },
          {
            '__typename': 'ConfigurableProduct',
            'uid': 'Mg==',
            'name': 'Corner Sofa',
            'url_key': 'corner-sofa',
          },
        ],
      },
    ],
  },
};

/// Writes [_data] through [cache] and reads it back, as graphql_flutter does
/// with every network result.
Map<String, dynamic>? _roundTrip(GraphQLCache cache) {
  final request = Request(
    operation: Operation(document: gql(_document)),
    variables: const {'sku': 'MAIN'},
  );
  cache.writeQuery(request, data: _data());
  return cache.readQuery(request);
}

List<Object?> _relatedNames(Map<String, dynamic>? data) {
  final items = (data?['products'] as Map?)?['items'] as List?;
  final related = (items?.first as Map?)?['related_products'] as List?;
  return [for (final product in related ?? const []) (product as Map)['name']];
}

void main() {
  test('a fragment on ProductInterface keeps its fields through the cache', () {
    final data = _roundTrip(
      GraphQLCache(store: InMemoryStore(), possibleTypes: kPossibleTypes),
    );

    expect(_relatedNames(data), ['Dining Chair', 'Corner Sofa']);
  });

  test('without the map the same read loses them (the bug it fixes)', () {
    final data = _roundTrip(GraphQLCache(store: InMemoryStore()));

    expect(_relatedNames(data), isNot(['Dining Chair', 'Corner Sofa']));
  });

  test('every client the app builds gets the map', () {
    final client = buildGraphQLClient(
      config: AppConfig.current,
      storeCode: () => 'en',
    );

    expect(client.cache.possibleTypes, same(kPossibleTypes));
  });

  test('the product types, cart lines and order lines are all listed', () {
    expect(
      kPossibleTypes['ProductInterface'],
      containsAll(<String>[
        'SimpleProduct',
        'ConfigurableProduct',
        'BundleProduct',
        'VirtualProduct',
      ]),
    );
    expect(
      kPossibleTypes['CartItemInterface'],
      containsAll(<String>['SimpleCartItem', 'ConfigurableCartItem']),
    );
    expect(kPossibleTypes['OrderItemInterface'], contains('OrderItem'));
  });
}
