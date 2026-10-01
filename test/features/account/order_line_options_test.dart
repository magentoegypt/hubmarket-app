import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_queries.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/marketplace_fakes.dart';

/// The options a customer chose (`selected_options`) reach the order's lines
/// as the cart writes them — "Colour: Teal" — for Figma 22's "Teal · Qty 1".
Map<String, dynamic> _orders() => {
  'customer': {
    '__typename': 'Customer',
    'orders': {
      '__typename': 'CustomerOrders',
      'total_count': 1,
      'page_info': {'current_page': 1, 'total_pages': 1},
      'items': [
        {
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
              'selected_options': [
                {'label': 'Colour', 'value': 'Teal'},
                {'label': 'Shape', 'value': ' Corner L-shape '},
                // Nothing chosen, or no label: nothing to say or just the value.
                {'label': 'Fabric', 'value': ''},
                {'label': '', 'value': 'Gift wrapped'},
              ],
            },
            {
              '__typename': 'OrderItem',
              'product_name': 'Tuna',
              'product_sku': 'TUNA',
              'quantity_ordered': 3,
              'selected_options': null,
            },
          ],
        },
      ],
    },
  },
};

void main() {
  test('the orders query asks for each line\'s selected options', () {
    expect(AccountQueries.orders, contains('selected_options { label value }'));
    expect(
      AccountQueries.guestOrderByToken,
      contains('selected_options { label value }'),
    );
  });

  test('a line keeps the options chosen, as "Label: value"', () async {
    final server = RecordingGraphQLClient((_, __) => _orders());
    final page = await AccountRepository(
      server.client,
      marketplace: const FixedMarketplaceGate(),
    ).fetchOrders();

    final lines = page.items.single.lines;
    expect(lines.first.options, [
      'Colour: Teal',
      'Shape: Corner L-shape',
      'Gift wrapped',
    ]);
    // A product with no options has none.
    expect(lines.last.options, isEmpty);
  });
}
