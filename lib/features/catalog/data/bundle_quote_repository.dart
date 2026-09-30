import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../cart/data/bundle_cart_mutation.dart';
import '../../cart/domain/bundle_cart_request.dart';
import '../domain/bundle_choice.dart';
import '../domain/money.dart';
import 'product_mapper.dart';

/// A package's price from the server (HubAppBundle `hmBundleQuote`): the buy
/// request `hmAddBundleToCart` would add, priced by the bundle's own price
/// model — what the cart will charge for any package, not only the cheapest.
/// A public read over the GET client, the selections written inline with
/// scalar variables (see [writeBundleSelections]).
class BundleQuoteRepository {
  BundleQuoteRepository(this._client);

  final GraphQLClient _client;

  /// Filled by [writeBundleSelections]; `HmBundleSelectionInput` is never a
  /// variable type.
  static const String template = r'''
query HmBundleQuote($sku: String!, $quantity: Float) {
  hmBundleQuote(sku: $sku, quantity: $quantity, selections: []) {
    available
    message
    price { value currency }
    regular_total { value currency }
    saving { value currency }
    discount_percent
  }
}
''';

  /// The server's price of [request]'s package. Throws [HubAppMissing]
  /// without HubAppBundle's quote, a `Failure` otherwise.
  Future<BundleServerQuote> quote(BundleCartRequest request) async {
    final variables = <String, dynamic>{
      'sku': request.sku,
      'quantity': request.quantity,
    };
    final document = writeBundleSelections(
      template,
      request.selections,
      variables,
    );
    final data = await runHubAppQuery(_client, document, variables: variables);
    return bundleServerQuoteFromJson(data['hmBundleQuote']);
  }
}

/// `HmBundleQuote` → [BundleServerQuote]. A quote without a price is no quote.
BundleServerQuote bundleServerQuoteFromJson(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const BundleServerQuote.unavailable(null);
  }
  Money? money(String key) {
    final value = json[key];
    return value is Map<String, dynamic> ? moneyFromJson(value) : null;
  }

  final price = money('price');
  if (json['available'] != true || price == null) {
    return BundleServerQuote.unavailable(hmString(json['message']));
  }
  return BundleServerQuote.available(
    BundleQuote(regular: money('regular_total'), total: price, exact: true),
  );
}

final bundleQuoteRepositoryProvider = Provider<BundleQuoteRepository>(
  (ref) => BundleQuoteRepository(ref.watch(publicGraphqlClientProvider)),
);

/// The server's price of a package on the bundle page (Figma 14b), or null
/// when it can't be had — Build 1, a HubApp without the quote, offline — and
/// the page keeps its own estimate. Kept while the page shows that package;
/// the quote is the guest's price, a GET the server's page cache can answer
/// when a package is asked again.
final bundleQuoteProvider = FutureProvider.autoDispose
    .family<BundleServerQuote?, BundleCartRequest>((ref, request) async {
      if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) {
        return null;
      }
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      try {
        return await ref.watch(bundleQuoteRepositoryProvider).quote(request);
      } on Object {
        return null;
      }
    });
