import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_queries.dart';

void main() {
  test('My orders asks for the newest orders first', () {
    // Magento applies no sort by default: without this the first page holds
    // the customer's oldest orders.
    expect(
      AccountQueries.orders,
      contains('sort: { sort_field: CREATED_AT, sort_direction: DESC }'),
    );
  });
}
