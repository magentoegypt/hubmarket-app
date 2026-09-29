import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:hubmarket_app/features/cart/data/bundle_cart_mutation.dart';
import 'package:hubmarket_app/features/cart/domain/bundle_cart_request.dart';

const _request = BundleCartRequest(
  sku: 'HM-DEMO-BUNDLE-FITNESS',
  selections: [
    BundleSelectionInput(selectionUid: 'YnVuZGxlLzIwLzYzLzE='),
    BundleSelectionInput(
      selectionUid: 'YnVuZGxlLzIxLzY0LzE=',
      quantity: 2,
      configurableOptionUids: ['Y29uZmlndXJhYmxlLzkzLzUz', 'Y29uZmlndXJhYmxlLzE0NC8xNjc='],
    ),
  ],
);

OperationDefinitionNode _operation(String document) => parseString(
  document,
).definitions.whereType<OperationDefinitionNode>().single;

/// `input: {...}` of `hmAddBundleToCart`, as field name → printed value.
Map<String, String> _input(OperationDefinitionNode operation) {
  final field = operation.selectionSet.selections
      .whereType<FieldNode>()
      .single;
  final input = field.arguments.single.value as ObjectValueNode;
  return {
    for (final f in input.fields) f.name.value: printNode(f.value),
  };
}

void main() {
  test('writes one inline selection object per chosen selection', () {
    final mutation = BundleCartMutation.build('cart-1', _request);
    final operation = _operation(mutation.document);
    final input = _input(operation);

    expect(input['cart_id'], r'$cartId');
    expect(input['sku'], r'$sku');
    expect(input['quantity'], r'$quantity');
    expect(
      input['selections'],
      r'[{selection_uid: $s0}, '
      r'{selection_uid: $s1, quantity: $q1, configurable_option_uids: $c1}]',
    );
  });

  test('declares only scalar variables', () {
    final operation = _operation(
      BundleCartMutation.build('cart-1', _request).document,
    );
    final declared = {
      for (final definition in operation.variableDefinitions)
        definition.variable.name.value: printNode(definition.type),
    };

    expect(declared, {
      'cartId': 'String!',
      'sku': 'String!',
      'quantity': 'Float',
      's0': 'ID!',
      's1': 'ID!',
      'q1': 'Float!',
      'c1': '[ID!]!',
    });
  });

  test('the variables carry the request', () {
    final mutation = BundleCartMutation.build('cart-1', _request);

    expect(mutation.variables, {
      'cartId': 'cart-1',
      'sku': 'HM-DEMO-BUNDLE-FITNESS',
      'quantity': 1.0,
      's0': 'YnVuZGxlLzIwLzYzLzE=',
      's1': 'YnVuZGxlLzIxLzY0LzE=',
      'q1': 2.0,
      'c1': ['Y29uZmlndXJhYmxlLzkzLzUz', 'Y29uZmlndXJhYmxlLzE0NC8xNjc='],
    });
  });

  test('asks for the lines\' sellers only when told to', () {
    expect(
      BundleCartMutation.build('cart-1', _request).document,
      isNot(contains('hm_seller')),
    );
    final withSellers = BundleCartMutation.build(
      'cart-1',
      _request,
      withSellers: true,
    ).document;
    expect(withSellers, contains('hm_seller'));
    // Still a single, valid operation with every fragment defined.
    expect(() => _operation(withSellers), returnsNormally);
    expect(withSellers, contains('fragment HmCartSellers on Cart'));
    expect(withSellers, contains('fragment HmSellerFields on HmSellerSummary'));
    expect(withSellers, contains('fragment HmLinkFields on HmLink'));
  });
}
