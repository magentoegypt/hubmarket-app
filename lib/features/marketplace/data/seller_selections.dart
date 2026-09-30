import 'package:gql/ast.dart';
import 'package:gql/language.dart';

import '../../../core/hubapp/hubapp_models.dart';

/// Builds the HubApp twin of a cart or order document: the same document with
/// the `hm_seller` selections added.
///
/// `hm_seller` (contract `HmSellerSummary`) is only on servers with HubApp, and
/// Magento rejects a whole document that names a field it doesn't know. So a
/// cart or order document exists twice at run time: the live one exactly as
/// written — what today's server gets — and a twin built here by adding one
/// fragment spread beside an existing one (`...CartFields` gains
/// `...HmCartSellers`) and appending that fragment's definitions. Nothing else
/// changes, so the two can't drift apart, and GraphQL merges the twin's
/// `items` selections into one list.
///
/// The added fragments are plain string constants next to the documents they
/// extend, which keeps them visible to `tool/validate_ops.py`.
abstract final class SellerSelections {
  static final Map<String, String> _built = <String, String>{};

  /// [document] with `...[spread]` added to every selection set that already
  /// spreads [anchor], and the fragment definitions in [fragments] appended
  /// (skipping any the document already defines). Built once per input.
  static String beside(
    String document, {
    required String anchor,
    required String spread,
    required String fragments,
  }) => _built.putIfAbsent(
    '$anchor|$spread|$fragments|$document',
    () => _compose(document, anchor, spread, fragments),
  );

  /// The twin of a product listing [document] (PLP, search, deals, best
  /// sellers, a brand's or store's products, Home rails, wishlist): every
  /// product card selection — a selection set asking for both `url_key` and
  /// `price_range` — gains `...HmCardSeller` (`hm_seller`, the card's seller
  /// line), and the fragments it needs are appended. Sent only while the
  /// server lists the `vendors` capability (`MarketplaceFeatures
  /// .listingSellers`); everything else goes out as written.
  static String withCardSellers(String document) => _built.putIfAbsent(
    'cards|$document',
    () => _compose(
      document,
      null,
      'HmCardSeller',
      '${HmFragments.cardSeller}\n${HmFragments.seller}\n${HmFragments.link}',
      visitor: const _CardSellers(),
    ),
  );

  static String _compose(
    String document,
    String? anchor,
    String spread,
    String fragments, {
    TransformingVisitor? visitor,
  }) {
    final transformed = transform(parseString(document), [
      visitor ?? _SpreadBeside(anchor!, spread),
    ]);
    final defined = {
      for (final definition
          in transformed.definitions.whereType<FragmentDefinitionNode>())
        definition.name.value,
    };
    final added = [
      for (final definition in parseString(
        fragments,
      ).definitions.whereType<FragmentDefinitionNode>())
        if (defined.add(definition.name.value)) definition,
    ];
    return printNode(
      DocumentNode(definitions: [...transformed.definitions, ...added]),
    );
  }
}

/// Adds `...HmCardSeller` to every selection set that selects a listing
/// card: `url_key` and `price_range` side by side, directly (a fragment's own
/// selection set included, so `HmCardProduct` gains it once for every list
/// that spreads it).
class _CardSellers extends TransformingVisitor {
  const _CardSellers();

  static const String _spread = 'HmCardSeller';

  bool _selects(SelectionSetNode node, String field) => node.selections.any(
    (selection) => selection is FieldNode && selection.name.value == field,
  );

  @override
  SelectionSetNode visitSelectionSetNode(SelectionSetNode node) {
    final isCard = _selects(node, 'url_key') && _selects(node, 'price_range');
    final has = node.selections.any(
      (selection) =>
          selection is FragmentSpreadNode && selection.name.value == _spread,
    );
    return isCard && !has
        ? SelectionSetNode(
            selections: [
              ...node.selections,
              FragmentSpreadNode(name: NameNode(value: _spread)),
            ],
          )
        : node;
  }
}

class _SpreadBeside extends TransformingVisitor {
  const _SpreadBeside(this.anchor, this.spread);

  final String anchor;
  final String spread;

  bool _spreads(SelectionSetNode node, String name) => node.selections.any(
    (selection) =>
        selection is FragmentSpreadNode && selection.name.value == name,
  );

  @override
  SelectionSetNode visitSelectionSetNode(SelectionSetNode node) =>
      _spreads(node, anchor) && !_spreads(node, spread)
      ? SelectionSetNode(
          selections: [
            ...node.selections,
            FragmentSpreadNode(name: NameNode(value: spread)),
          ],
        )
      : node;
}
