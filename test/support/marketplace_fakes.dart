import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

/// Test doubles for the P3 marketplace work (sellers on lines, bundles).

/// A [MarketplaceGate] with settable [features] that records what the
/// repositories report — and, like the real one, stops asking for what was
/// reported missing.
class RecordingMarketplaceGate implements MarketplaceGate {
  RecordingMarketplaceGate([this.features = MarketplaceFeatures.all]);

  @override
  MarketplaceFeatures features;

  int sellersMissingCalls = 0;
  int bundlesMissingCalls = 0;
  int packagesMissingCalls = 0;

  @override
  void sellersMissing() {
    sellersMissingCalls++;
    features = MarketplaceFeatures(
      sellers: false,
      bundles: features.bundles,
      packages: features.packages,
    );
  }

  @override
  void bundlesMissing() {
    bundlesMissingCalls++;
    features = MarketplaceFeatures(
      sellers: features.sellers,
      bundles: false,
      packages: features.packages,
    );
  }

  @override
  void packagesMissing() {
    packagesMissingCalls++;
    features = MarketplaceFeatures(
      sellers: features.sellers,
      bundles: features.bundles,
      packages: false,
    );
  }
}

/// A client that records every request and answers with whatever [answer]
/// returns for it: a `Map` is the response `data`, a [Response] goes back as
/// is, an [Exception] fails the request.
class RecordingGraphQLClient {
  RecordingGraphQLClient(this.answer);

  final Object Function(Request request, String document) answer;
  final List<Request> requests = <Request>[];

  /// The documents sent, printed.
  List<String> get documents => [
    for (final request in requests) printNode(request.operation.document),
  ];

  late final GraphQLClient client = GraphQLClient(
    link: Link.function((request, [forward]) {
      requests.add(request);
      final reply = answer(request, printNode(request.operation.document));
      if (reply is Response) return Stream.value(reply);
      if (reply is Exception) return Stream.error(reply);
      return Stream.value(
        Response(
          data: reply as Map<String, dynamic>,
          response: const <String, dynamic>{},
        ),
      );
    }),
    // Canned data may leave out fields and `__typename`s.
    cache: GraphQLCache(partialDataPolicy: PartialDataCachePolicy.accept),
  );
}

/// The first root field [request] asks for, e.g. `addProductsToCart`.
String rootFieldOf(Request request) {
  final operation = request.operation.document.definitions
      .whereType<OperationDefinitionNode>()
      .first;
  // The client adds a `__typename` to every selection set.
  return operation.selectionSet.selections
      .whereType<FieldNode>()
      .map((field) => field.name.value)
      .firstWhere((name) => name != '__typename');
}

/// Magento's answer to a document naming a field the server doesn't have.
Response missingFieldResponse(String field, String type) => Response(
  errors: [
    GraphQLError(message: 'Cannot query field "$field" on type "$type".'),
  ],
  response: const <String, dynamic>{},
);

/// An `HmSellerSummary` as the backend serves it.
Map<String, dynamic> sellerJson(
  String? code,
  String name, {
  bool marketplace = false,
  double? rating,
  String? logo,
}) => {
  '__typename': 'HmSellerSummary',
  'code': code,
  'vendor_entity_id': code?.length,
  'name': name,
  'logo_url': logo,
  'rating': rating,
  'review_count': rating == null ? 0 : 27,
  'product_count': 12,
  'is_marketplace': marketplace,
  'link': code == null
      ? null
      : {
          '__typename': 'HmLink',
          'type': 'STORE',
          'url': 'https://hub-market.magento2.click/en/shop/$code',
          'path': 'shop/$code',
          'uid': null,
          'code': code,
        },
};

/// The same seller as a domain object.
HmSellerSummary seller(
  String? code,
  String name, {
  bool marketplace = false,
  double? rating,
}) => HmSellerSummary.fromJson(
  sellerJson(code, name, marketplace: marketplace, rating: rating),
)!;
