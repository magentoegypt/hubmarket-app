import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:hubmarket_app/features/account/data/account_queries.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/marketplace_fakes.dart';

/// One order of two lines, each with its seller when [withSellers].
Map<String, dynamic> _order({required bool withSellers}) => {
  '__typename': 'CustomerOrder',
  'id': 'MTI=',
  'number': '000000248',
  'status': 'Processing',
  'order_date': '2026-09-28 10:42:00',
  'items': [
    {
      '__typename': 'OrderItem',
      'product_name': 'Corner Sofa Bed',
      'product_sku': 'SOFA',
      'quantity_ordered': 1,
      if (withSellers) 'hm_seller': sellerJson('mia', 'MIA CO'),
    },
    {
      '__typename': 'OrderItem',
      'product_name': 'Floral Print Corset-Waist Tie Dress',
      'product_sku': 'DRESS',
      'quantity_ordered': 1,
      if (withSellers) 'hm_seller': sellerJson('loly', 'loly store'),
    },
  ],
};

Map<String, dynamic> _orders({required bool withSellers}) => {
  'customer': {
    '__typename': 'Customer',
    'orders': {
      '__typename': 'CustomerOrders',
      'total_count': 1,
      'page_info': {'current_page': 1, 'total_pages': 1},
      'items': [_order(withSellers: withSellers)],
    },
  },
};

void main() {
  test('order documents ask for no HubApp field today', () {
    for (final document in [
      AccountQueries.orders,
      AccountQueries.guestOrderByToken,
      AccountQueries.guestOrder,
      AccountQueries.cancelOrder,
    ]) {
      expect(document, isNot(contains('hm_')));
      final twin = AccountQueries.withSellers(document);
      expect(twin, contains('...HmOrderSellers'));
      expect(twin, contains('hm_seller'));
      // Still one operation, every spread defined once.
      final ast = parseString(twin);
      expect(
        ast.definitions.whereType<OperationDefinitionNode>(),
        hasLength(1),
      );
      final fragments = [
        for (final f in ast.definitions.whereType<FragmentDefinitionNode>())
          f.name.value,
      ];
      expect(fragments.toSet(), hasLength(fragments.length));
      expect(
        fragments,
        containsAll([
          'OrderFields',
          'HmOrderSellers',
          'HmSellerFields',
          'HmLinkFields',
        ]),
      );
      expect(printNode(ast), isNotEmpty);
    }
  });

  test('without HubApp the orders come as today, no sellers', () async {
    final server = RecordingGraphQLClient(
      (_, __) => _orders(withSellers: false),
    );
    final page = await AccountRepository(
      server.client,
      marketplace: const FixedMarketplaceGate(),
    ).fetchOrders();

    expect(server.documents.single, isNot(contains('hm_seller')));
    expect(page.items.single.lines.map((l) => l.seller), everyElement(isNull));
  });

  test('with HubApp each line carries its seller', () async {
    final server = RecordingGraphQLClient(
      (_, __) => _orders(withSellers: true),
    );
    final page = await AccountRepository(
      server.client,
      marketplace: RecordingMarketplaceGate(),
    ).fetchOrders();

    expect(server.documents.single, contains('hm_seller'));
    expect(page.items.single.lines.map((l) => l.seller?.name), [
      'MIA CO',
      'loly store',
    ]);
  });

  test('a server without hm_seller gets today\'s document', () async {
    final server = RecordingGraphQLClient(
      (_, document) => document.contains('hm_seller')
          ? missingFieldResponse('hm_seller', 'OrderItemInterface')
          : _orders(withSellers: false),
    );
    final gate = RecordingMarketplaceGate();
    final page = await AccountRepository(
      server.client,
      marketplace: gate,
    ).fetchOrders();

    expect(page.items.single.lines, hasLength(2));
    expect(gate.sellersMissingCalls, 1);
    expect(server.documents.last, isNot(contains('hm_seller')));
  });
}
