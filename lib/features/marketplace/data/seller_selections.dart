import 'package:gql/ast.dart';
import 'package:gql/language.dart';

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

  static String _compose(
    String document,
    String anchor,
    String spread,
    String fragments,
  ) {
    final transformed = transform(parseString(document), [
      _SpreadBeside(anchor, spread),
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
