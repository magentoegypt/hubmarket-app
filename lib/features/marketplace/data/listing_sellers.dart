import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/hubapp/hubapp.dart';
import '../marketplace_features.dart';
import 'seller_selections.dart';

/// Sends a product listing [document] through [run] — with each card's seller
/// (`SellerSelections.withCardSellers`) while [gate] allows it
/// ([MarketplaceFeatures.listingSellers]: the server lists HubAppVendors),
/// exactly as written otherwise.
///
/// [run] gets the document and whether it is the twin; for the twin it must
/// throw [HubAppMissing] for a "Cannot query field" answer (see
/// [missingOrNull]). A server that turns `hm_seller` down ran nothing —
/// validation comes first, so this holds for a mutation's twin too — so the
/// plain [document] goes out instead and the gate stops asking. Any other
/// [HubAppMissing] (the listing's own field) is rethrown as is.
Future<T> sendListing<T>(
  MarketplaceGate gate,
  String document,
  Future<T> Function(String document, bool twin) run,
) async {
  if (!gate.features.listingSellers) return run(document, false);
  try {
    return await run(SellerSelections.withCardSellers(document), true);
  } on HubAppMissing catch (missing) {
    if (!missing.message.contains('"hm_seller"')) rethrow;
    gate.sellersMissing();
    return run(document, false);
  }
}

/// [exception] as a [HubAppMissing] when it only says the server lacks what
/// the document asked for ([isHubAppMissing]); null otherwise.
HubAppMissing? missingOrNull(OperationException exception) {
  if (!isHubAppMissing(exception)) return null;
  final errors = [
    ...exception.graphqlErrors,
    if (exception.linkException case final ServerException server)
      ...?server.parsedResponse?.errors,
  ];
  return HubAppMissing(errors.isEmpty ? '' : errors.first.message);
}
