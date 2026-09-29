import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:hubmarket_app/features/cart/data/cart_queries.dart';
import 'package:hubmarket_app/features/marketplace/data/seller_selections.dart';

/// Names of the fragments [document] spreads and defines.
({Set<String> spreads, List<String> defined}) _fragments(String document) {
  final ast = parseString(document);
  final spreads = <String>{};
  void walk(SelectionSetNode? set) {
    for (final selection in set?.selections ?? const <SelectionNode>[]) {
      switch (selection) {
        case FragmentSpreadNode(:final name):
          spreads.add(name.value);
        case FieldNode(:final selectionSet):
          walk(selectionSet);
        case InlineFragmentNode(:final selectionSet):
          walk(selectionSet);
      }
    }
  }

  final defined = <String>[];
  for (final definition in ast.definitions) {
    switch (definition) {
      case OperationDefinitionNode(:final selectionSet):
        walk(selectionSet);
      case FragmentDefinitionNode(:final name, :final selectionSet):
        defined.add(name.value);
        walk(selectionSet);
    }
  }
  return (spreads: spreads, defined: defined);
}

void main() {
  final cartDocuments = <String, String>{
    'getCart': CartQueries.getCart,
    'addProducts': CartQueries.addProducts,
    'addBundle': CartQueries.addBundle,
    'updateItems': CartQueries.updateItems,
    'removeItem': CartQueries.removeItem,
    'applyCoupon': CartQueries.applyCoupon,
    'removeCoupon': CartQueries.removeCoupon,
    'mergeCarts': CartQueries.mergeCarts,
  };

  group('cart documents', () {
    for (final MapEntry(key: name, value: live) in cartDocuments.entries) {
      test('$name: the live document asks for no HubApp field', () {
        if (name == 'addBundle') return; // HubApp-only by definition.
        expect(live, isNot(contains('hm_')));
        expect(live, isNot(contains('Hm')));
      });

      test('$name: the HubApp twin adds the sellers and nothing else', () {
        final twin = CartQueries.withSellers(live);
        final fragments = _fragments(twin);

        expect(twin, contains('hm_seller'));
        expect(
          fragments.spreads,
          containsAll(['CartFields', 'HmCartSellers', 'HmSellerFields']),
        );
        // Every spread is defined, exactly once.
        expect(fragments.defined.toSet(), containsAll(fragments.spreads));
        expect(fragments.defined.toSet(), hasLength(fragments.defined.length));
        // The operation itself is untouched: same fields, plus one spread.
        final liveOp = parseString(live).definitions
            .whereType<OperationDefinitionNode>()
            .single;
        final twinOp = parseString(twin).definitions
            .whereType<OperationDefinitionNode>()
            .single;
        String normalized(Node node) => printNode(
          node,
        ).replaceAll('...HmCartSellers', '').replaceAll(RegExp(r'\s+'), ' ');
        expect(twinOp.name?.value, liveOp.name?.value);
        expect(normalized(twinOp), normalized(liveOp));
      });
    }

    test('the twin is built once per document', () {
      expect(
        identical(
          CartQueries.withSellers(CartQueries.getCart),
          CartQueries.withSellers(CartQueries.getCart),
        ),
        isTrue,
      );
    });
  });

  group('SellerSelections.beside', () {
    test('adds the spread beside every anchor, once', () {
      const document = r'''
query Two($a: String!) {
  first: cart(cart_id: $a) { ...CartFields }
  second: cart(cart_id: $a) { ...CartFields ...Extra }
}
fragment CartFields on Cart { id }
''';
      final twin = SellerSelections.beside(
        document,
        anchor: 'CartFields',
        spread: 'Extra',
        fragments: 'fragment Extra on Cart { total_quantity }',
      );

      expect(RegExp(r'\.\.\.Extra').allMatches(twin), hasLength(2));
      expect(
        RegExp('fragment Extra on Cart').allMatches(twin),
        hasLength(1),
      );
    });

    test("doesn't define a fragment the document already has", () {
      const document =
          'query Q { cart(cart_id: "x") { ...CartFields } } '
          'fragment CartFields on Cart { id } '
          'fragment Shared on Cart { id }';
      final twin = SellerSelections.beside(
        document,
        anchor: 'CartFields',
        spread: 'Shared',
        fragments: 'fragment Shared on Cart { email }',
      );

      expect(_fragments(twin).defined, ['CartFields', 'Shared']);
    });
  });
}
