import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/util/media.dart';
import '../../marketplace/domain/product_offer.dart';
import '../domain/bundle_product.dart';
import '../domain/product_marketplace.dart';
import 'product_mapper.dart';

/// The HubApp read of a product page (P3, contract §2.3 "PDP"): who sells the
/// product and, for a bundle, its options with their children — configurable
/// children with their attributes — so Figma 14's "Sold by" row and 14b's
/// bundle page can be built.
///
/// A second, public query beside the page's own `ProductDetail`, which stays
/// exactly what today's server gets: this one goes out only when HubApp is
/// available, as a GET the full-page cache can serve.
abstract final class ProductMarketplaceQueries {
  /// The page by its url_key, with other sellers' offers (HubAppVendors
  /// P3.1): what the current backend answers.
  static const String productMarketplace = r'''
query HmProductMarketplace($urlKey: String!) {
  products(filter: { url_key: { eq: $urlKey } }, pageSize: 1) {
    items {
      ...HmProductMarketplaceFields
      ...HmProductOfferFields
    }
  }
}
''';

  /// [productMarketplace] for a backend whose HubAppVendors doesn't list
  /// offers yet (P2): the seller and a bundle's options only.
  static const String productMarketplaceSellers = r'''
query HmProductMarketplaceSellers($urlKey: String!) {
  products(filter: { url_key: { eq: $urlKey } }, pageSize: 1) {
    items {
      ...HmProductMarketplaceFields
    }
  }
}
''';

  /// Another seller's offer, opened from the sheet. Product search leaves
  /// offers out, so `products(filter: {url_key})` finds none; `route` reads
  /// it by its URL (url_key and the product URL suffix).
  static const String productMarketplaceByRoute = r'''
query HmProductMarketplaceByRoute($url: String!) {
  route(url: $url) {
    ...HmProductMarketplaceFields
    ...HmProductOfferFields
  }
}
''';

  /// Who sells the product, and a bundle's options with their children.
  static const String fields = r'''
fragment HmProductMarketplaceFields on ProductInterface {
  sku
  hm_seller {
    ...HmSellerFields
  }
  ... on BundleProduct {
    dynamic_price
    price_range {
      minimum_price {
        regular_price { value currency }
        final_price { value currency }
      }
      maximum_price {
        regular_price { value currency }
        final_price { value currency }
      }
    }
    items {
      uid
      title
      required
      type
      position
      options {
        uid
        label
        quantity
        can_change_quantity
        is_default
        position
        price
        price_type
        product {
          sku
          name
          url_key
          stock_status
          image { url }
          price_range {
            minimum_price {
              regular_price { value currency }
              final_price { value currency }
            }
          }
          ... on ConfigurableProduct {
            configurable_options {
              attribute_code
              label
              values {
                uid
                value_index
                label
                swatch_data { value }
              }
            }
            variants {
              attributes { code value_index }
              product {
                sku
                stock_status
                image { url }
                price_range {
                  minimum_price {
                    regular_price { value currency }
                    final_price { value currency }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
''';

  /// Other sellers' offers, cheapest first: the website's "Sold by N other
  /// sellers". The backend's most, 50: the sheet lists every one.
  static const String offerFields = r'''
fragment HmProductOfferFields on ProductInterface {
  hm_offer_count
  hm_other_offers(pageSize: 50) {
    uid
    sku
    url_key
    type_id
    seller {
      ...HmSellerFields
    }
    price { value currency }
    regular_price { value currency }
    stock_status
    dispatch_time { code label source }
  }
}
''';

  /// [productMarketplace] with the fragments it spreads.
  static const String document =
      '$productMarketplace\n$fields\n$offerFields\n'
      '${HmFragments.seller}\n${HmFragments.link}';

  /// [productMarketplaceSellers] with the fragments it spreads.
  static const String sellersDocument =
      '$productMarketplaceSellers\n$fields\n'
      '${HmFragments.seller}\n${HmFragments.link}';

  /// [productMarketplaceByRoute] with the fragments it spreads.
  static const String routeDocument =
      '$productMarketplaceByRoute\n$fields\n$offerFields\n'
      '${HmFragments.seller}\n${HmFragments.link}';
}

class ProductMarketplaceRepository {
  ProductMarketplaceRepository(this._client);

  /// The public (GET, token-less) client.
  final GraphQLClient _client;

  /// Null when no product has [urlKey]. Throws [HubAppMissing] when the
  /// server has no `hm_seller` — or, [withOffers], no other sellers' offers
  /// ([isOffersMissing]) — and a `Failure` otherwise.
  ///
  /// [withOffers] also reads other sellers' offers, and finds an offer's own
  /// page, which product search leaves out, through `route`.
  Future<ProductMarketplace?> fetch(
    String urlKey, {
    bool withOffers = true,
  }) async {
    final data = await runHubAppQuery(
      _client,
      withOffers
          ? ProductMarketplaceQueries.document
          : ProductMarketplaceQueries.sellersDocument,
      variables: {'urlKey': urlKey},
      // Fragments on ProductInterface: see runHubAppQuery.
      fetchPolicy: FetchPolicy.noCache,
    );
    final items =
        (data['products'] as Map<String, dynamic>?)?['items'] as List<dynamic>?;
    final first = items == null || items.isEmpty ? null : items.first;
    if (first is Map<String, dynamic>) return productMarketplaceFromJson(first);
    if (!withOffers) return null;
    final routed = await runHubAppQuery(
      _client,
      ProductMarketplaceQueries.routeDocument,
      variables: {'url': productRouteUrl(urlKey)},
      fetchPolicy: FetchPolicy.noCache,
    );
    final page = routed['route'];
    // Anything but a product (a CMS page, a category) has no sku here.
    return page is Map<String, dynamic> && hmString(page['sku']) != null
        ? productMarketplaceFromJson(page)
        : null;
  }
}

/// Whether [missing] is about other sellers' offers only: HubAppVendors is
/// there (P2) without `hm_offer_count` / `hm_other_offers` (P3.1). A missing
/// `hm_seller` comes first in the document, so it is never read as this.
bool isOffersMissing(HubAppMissing missing) =>
    missing.message.contains('hm_offer_count') ||
    missing.message.contains('hm_other_offers') ||
    missing.message.contains('HmProductOffer');

final productMarketplaceRepositoryProvider =
    Provider<ProductMarketplaceRepository>(
      (ref) =>
          ProductMarketplaceRepository(ref.watch(publicGraphqlClientProvider)),
    );

/// One `products.items[0]` of [ProductMarketplaceQueries.productMarketplace].
ProductMarketplace productMarketplaceFromJson(Map<String, dynamic> json) {
  final seller = HmSellerSummary.fromJson(json['hm_seller']);
  final items = json['items'];
  BundleProduct? bundle;
  if (items is List) {
    final options = [
      for (final item in items.whereType<Map<String, dynamic>>())
        if (_bundleOption(item) case final option?) option,
    ]..sort((a, b) => a.position.compareTo(b.position));
    if (options.isNotEmpty) {
      final range = json['price_range'] as Map<String, dynamic>?;
      final min = range?['minimum_price'] as Map<String, dynamic>?;
      final max = range?['maximum_price'] as Map<String, dynamic>?;
      bundle = BundleProduct(
        options: List.unmodifiable(options),
        dynamicPrice: json['dynamic_price'] != false,
        minRegular: moneyFromJson(
          min?['regular_price'] as Map<String, dynamic>?,
        ),
        minFinal: moneyFromJson(min?['final_price'] as Map<String, dynamic>?),
        maxRegular: moneyFromJson(
          max?['regular_price'] as Map<String, dynamic>?,
        ),
        maxFinal: moneyFromJson(max?['final_price'] as Map<String, dynamic>?),
      );
    }
  }
  final offers = [
    for (final offer in json['hm_other_offers'] is List
        ? json['hm_other_offers'] as List
        : const [])
      if (productOfferFromJson(offer) case final offer?) offer,
  ];
  return ProductMarketplace(
    seller: seller,
    bundle: bundle,
    // The server's count, but no row at all without an offer to show in
    // its sheet, and never fewer than the offers read.
    offerCount: offers.isEmpty
        ? 0
        : [hmInt(json['hm_offer_count']) ?? 0, offers.length].reduce(
            (a, b) => a > b ? a : b,
          ),
    offers: List.unmodifiable(offers),
  );
}

/// One `HmProductOffer`; null without a uid, a SKU, a URL key, a seller or a
/// price — never a half-drawn row.
ProductOffer? productOfferFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final uid = hmString(json['uid']);
  final sku = hmString(json['sku']);
  final urlKey = hmString(json['url_key']);
  final seller = HmSellerSummary.fromJson(json['seller']);
  final price = moneyFromJson(json['price'] as Map<String, dynamic>?);
  if (uid == null ||
      sku == null ||
      urlKey == null ||
      seller == null ||
      price == null) {
    return null;
  }
  return ProductOffer(
    uid: uid,
    sku: sku,
    urlKey: urlKey,
    typeId: hmString(json['type_id']) ?? 'simple',
    seller: seller,
    price: price,
    regularPrice: moneyFromJson(json['regular_price'] as Map<String, dynamic>?),
    inStock: json['stock_status'] != 'OUT_OF_STOCK',
    dispatchTime: HmDispatchTime.fromJson(json['dispatch_time']),
  );
}

/// A `BundleItem`; null without a uid or any usable selection.
BundleOption? _bundleOption(Map<String, dynamic> json) {
  final uid = hmString(json['uid']);
  if (uid == null) return null;
  final selections = [
    for (final option
        in (json['options'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>())
      if (_bundleSelection(option) case final selection?) selection,
  ]..sort((a, b) => a.position.compareTo(b.position));
  if (selections.isEmpty) return null;
  return BundleOption(
    uid: uid,
    title: hmString(json['title']) ?? '',
    required: json['required'] != false,
    type: BundleOptionType.parse(json['type']),
    position: hmInt(json['position']) ?? 0,
    selections: List.unmodifiable(selections),
  );
}

/// A `BundleItemOption`; null without a uid.
BundleSelection? _bundleSelection(Map<String, dynamic> json) {
  final uid = hmString(json['uid']);
  if (uid == null) return null;
  final child = _bundleChild(json['product']);
  return BundleSelection(
    uid: uid,
    label: hmString(json['label']) ?? child?.name ?? '',
    quantity: hmDouble(json['quantity']) ?? 1,
    canChangeQuantity: json['can_change_quantity'] == true,
    isDefault: json['is_default'] == true,
    position: hmInt(json['position']) ?? 0,
    price: hmDouble(json['price']),
    priceType: hmString(json['price_type']),
    child: child,
  );
}

BundleChild? _bundleChild(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final sku = hmString(json['sku']);
  if (sku == null) return null;
  final min =
      (json['price_range'] as Map<String, dynamic>?)?['minimum_price']
          as Map<String, dynamic>?;
  return BundleChild(
    sku: sku,
    name: hmString(json['name']) ?? sku,
    urlKey: hmString(json['url_key']),
    imageUrl: httpsMediaUrl(
      (json['image'] as Map<String, dynamic>?)?['url'] as String?,
    ),
    inStock: json['stock_status'] != 'OUT_OF_STOCK',
    regularPrice: moneyFromJson(min?['regular_price'] as Map<String, dynamic>?),
    finalPrice: moneyFromJson(min?['final_price'] as Map<String, dynamic>?),
    options: configurableOptionsFromJson(json['configurable_options']),
    variants: [
      for (final variant
          in (json['variants'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
        _bundleVariant(variant),
    ],
  );
}

BundleVariant _bundleVariant(Map<String, dynamic> json) {
  final product = json['product'] as Map<String, dynamic>?;
  final min =
      (product?['price_range'] as Map<String, dynamic>?)?['minimum_price']
          as Map<String, dynamic>?;
  return BundleVariant(
    sku: hmString(product?['sku']) ?? '',
    attributes: {
      for (final a
          in (json['attributes'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
        if (hmString(a['code']) case final code?)
          code: hmInt(a['value_index']) ?? 0,
    },
    regularPrice: moneyFromJson(min?['regular_price'] as Map<String, dynamic>?),
    finalPrice: moneyFromJson(min?['final_price'] as Map<String, dynamic>?),
    inStock: product?['stock_status'] != 'OUT_OF_STOCK',
    imageUrl: httpsMediaUrl(
      (product?['image'] as Map<String, dynamic>?)?['url'] as String?,
    ),
  );
}
