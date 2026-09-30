import 'package:gql/ast.dart';
import 'package:gql/language.dart';

import '../domain/bundle_cart_request.dart';
import 'cart_queries.dart';

/// The `hmAddBundleToCart` request (HubAppBundle) for one [BundleCartRequest]:
/// [CartQueries.addBundle] with one inline selection object per chosen
/// selection, and the variables they point at (see [writeBundleSelections]).
class BundleCartMutation {
  const BundleCartMutation._(this.document, this.variables);

  factory BundleCartMutation.build(
    String cartId,
    BundleCartRequest request, {
    bool withSellers = false,
  }) {
    final base = withSellers
        ? CartQueries.withSellers(CartQueries.addBundle)
        : CartQueries.addBundle;
    final variables = <String, dynamic>{
      'cartId': cartId,
      'sku': request.sku,
      'quantity': request.quantity,
    };
    final document = writeBundleSelections(base, request.selections, variables);
    return BundleCartMutation._(document, variables);
  }

  final String document;
  final Map<String, dynamic> variables;
}

/// [template] with its empty `selections: []` — an input field
/// (`hmAddBundleToCart(input: {…, selections: []})`) or an argument
/// (`hmBundleQuote(…, selections: [])`) — filled with one inline
/// `HmBundleSelectionInput` object per selection, and the operation declaring
/// the scalar variables they point at, which are added to [variables].
///
/// Every variable is a scalar (`$s0: ID!`, `$q0: Float!`, `$c0: [ID!]!`, …):
/// while a module is missing Magento answers a variable of an `Hm*` type with
/// HTTP 500 instead of "Cannot query field", so the input type is never named
/// and a server without HubAppBundle turns the request down in a way the app
/// can recognise.
String writeBundleSelections(
  String template,
  List<BundleSelectionInput> selections,
  Map<String, dynamic> variables,
) {
  final definitions = <VariableDefinitionNode>[];
  final objects = <ObjectValueNode>[];
  for (var i = 0; i < selections.length; i++) {
    final selection = selections[i];
    final fields = <ObjectFieldNode>[_field('selection_uid', 's$i')];
    definitions.add(_variable('s$i', _named('ID')));
    variables['s$i'] = selection.selectionUid;
    final quantity = selection.quantity;
    if (quantity != null) {
      fields.add(_field('quantity', 'q$i'));
      definitions.add(_variable('q$i', _named('Float')));
      variables['q$i'] = quantity;
    }
    if (selection.configurableOptionUids.isNotEmpty) {
      fields.add(_field('configurable_option_uids', 'c$i'));
      definitions.add(
        _variable('c$i', ListTypeNode(type: _named('ID'), isNonNull: true)),
      );
      variables['c$i'] = List<String>.of(selection.configurableOptionUids);
    }
    objects.add(ObjectValueNode(fields: fields));
  }
  final document = transform(parseString(template), [
    _WriteSelections(definitions, ListValueNode(values: objects)),
  ]);
  return printNode(document);
}

NamedTypeNode _named(String type) =>
    NamedTypeNode(name: NameNode(value: type), isNonNull: true);

VariableDefinitionNode _variable(String name, TypeNode type) =>
    VariableDefinitionNode(
      variable: VariableNode(name: NameNode(value: name)),
      type: type,
      // The printer expects a node here, as the parser always makes one.
      defaultValue: const DefaultValueNode(value: null),
    );

ObjectFieldNode _field(String name, String variable) => ObjectFieldNode(
  name: NameNode(value: name),
  value: VariableNode(name: NameNode(value: variable)),
);

/// Puts the selection objects into the `selections: []` of the template and
/// declares their variables on the operation.
class _WriteSelections extends TransformingVisitor {
  const _WriteSelections(this.definitions, this.selections);

  final List<VariableDefinitionNode> definitions;
  final ListValueNode selections;

  @override
  OperationDefinitionNode visitOperationDefinitionNode(
    OperationDefinitionNode node,
  ) => OperationDefinitionNode(
    type: node.type,
    name: node.name,
    variableDefinitions: [...node.variableDefinitions, ...definitions],
    directives: node.directives,
    selectionSet: node.selectionSet,
  );

  @override
  ObjectFieldNode visitObjectFieldNode(ObjectFieldNode node) =>
      node.name.value == 'selections'
      ? ObjectFieldNode(name: node.name, value: selections)
      : node;

  @override
  ArgumentNode visitArgumentNode(ArgumentNode node) =>
      node.name.value == 'selections'
      ? ArgumentNode(name: node.name, value: selections)
      : node;
}
