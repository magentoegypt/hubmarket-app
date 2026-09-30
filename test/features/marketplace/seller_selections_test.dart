import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/cart/data/cart_queries.dart';
import 'package:hubmarket_app/features/catalog/data/best_sellers_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_queries.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/marketplace/data/seller_selections.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_queries.dart';

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
        final liveOp = parseString(
          live,
        ).definitions.whereType<OperationDefinitionNode>().single;
        final twinOp = parseString(
          twin,
        ).definitions.whereType<OperationDefinitionNode>().single;
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

  group('listing documents (the card seller line)', () {
    final listings = <String, String>{
      'products (PLP, brand and store pages)': CatalogQueries.products,
      'search fallback': CatalogQueries.searchProducts,
      'hmBestSellers': BestSellersRepository.query,
      'hmAppHome rails': HmHomeRepository.documentFor(HmAudience.guest),
      'wishlist': WishlistQueries.getWishlist,
      'wishlist add': WishlistQueries.addToWishlist,
    };

    for (final MapEntry(key: name, value: live) in listings.entries) {
      test('$name: the live document asks for no seller', () {
        expect(live, isNot(contains('hm_seller')));
        expect(live, isNot(contains('HmCardSeller')));
      });

      test('$name: the twin adds the seller to each card, and nothing else', () {
        final twin = SellerSelections.withCardSellers(live);
        final fragments = _fragments(twin);

        expect(twin, contains('hm_seller'));
        expect(
          fragments.spreads,
          containsAll(['HmCardSeller', 'HmSellerFields', 'HmLinkFields']),
        );
        expect(fragments.defined.toSet(), containsAll(fragments.spreads));
        expect(fragments.defined.toSet(), hasLength(fragments.defined.length));
        // One card selection gains one spread.
        expect(RegExp(r'\.\.\.HmCardSeller\b').allMatches(twin), hasLength(1));
        String normalized(String document) => printNode(parseString(document))
            .replaceAll('...HmCardSeller', '')
            .replaceAll(RegExp(r'\s+'), ' ');
        final liveOp = normalized(live);
        final twinOp = normalized(twin);
        expect(twinOp.startsWith(liveOp.trim()), isTrue);
      });
    }

    test('a document without a card selection is left as it is', () {
      final twin = SellerSelections.withCardSellers(CatalogQueries.categoryTree);
      expect(twin, isNot(contains('...HmCardSeller')));
    });

    test('the twin is built once per document', () {
      expect(
        identical(
          SellerSelections.withCardSellers(CatalogQueries.products),
          SellerSelections.withCardSellers(CatalogQueries.products),
        ),
        isTrue,
      );
    });
  });

  group('SellerSelections.beside', () {
    // Valid on the live schema too: tool/validate_ops.py reads these.
    const document = r'''
query SellerSelectionsTwo($a: String!) {
  first: cart(cart_id: $a) {
    ...SellerSelectionsAnchor
  }
  second: cart(cart_id: $a) {
    ...SellerSelectionsAnchor
    ...SellerSelectionsExtra
  }
}
''';
    const anchor = r'''
fragment SellerSelectionsAnchor on Cart {
  id
}
''';
    const extra = r'''
fragment SellerSelectionsExtra on Cart {
  total_quantity
}
''';

    test('adds the spread beside every anchor, once', () {
      final twin = SellerSelections.beside(
        '$document\n$anchor',
        anchor: 'SellerSelectionsAnchor',
        spread: 'SellerSelectionsExtra',
        fragments: extra,
      );

      expect(
        RegExp(r'\.\.\.SellerSelectionsExtra').allMatches(twin),
        hasLength(2),
      );
      expect(
        RegExp('fragment SellerSelectionsExtra on Cart').allMatches(twin),
        hasLength(1),
      );
    });

    test("doesn't define a fragment the document already has", () {
      final twin = SellerSelections.beside(
        '$document\n$anchor\n$extra',
        anchor: 'SellerSelectionsAnchor',
        spread: 'SellerSelectionsExtra',
        fragments: extra,
      );

      expect(_fragments(twin).defined, [
        'SellerSelectionsAnchor',
        'SellerSelectionsExtra',
      ]);
    });
  });
}
