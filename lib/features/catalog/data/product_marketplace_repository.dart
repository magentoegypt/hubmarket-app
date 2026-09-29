import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/util/media.dart';
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
  static const String productMarketplace = r'''
query HmProductMarketplace($urlKey: String!) {
  products(filter: { url_key: { eq: $urlKey } }, pageSize: 1) {
    items {
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
  }
}
''';

  /// [productMarketplace] with the fragments it spreads.
  static const String document =
      '$productMarketplace\n${HmFragments.seller}\n${HmFragments.link}';
}

class ProductMarketplaceRepository {
  ProductMarketplaceRepository(this._client);

  /// The public (GET, token-less) client.
  final GraphQLClient _client;

  /// Null when no product has [urlKey]. Throws [HubAppMissing] when the
  /// server has no `hm_seller`, a `Failure` otherwise.
  Future<ProductMarketplace?> fetch(String urlKey) async {
    final data = await runHubAppQuery(
      _client,
      ProductMarketplaceQueries.document,
      variables: {'urlKey': urlKey},
    );
    final items =
        (data['products'] as Map<String, dynamic>?)?['items'] as List<dynamic>?;
    final first = items == null || items.isEmpty ? null : items.first;
    return first is Map<String, dynamic>
        ? productMarketplaceFromJson(first)
        : null;
  }
}

final productMarketplaceRepositoryProvider =
    Provider<ProductMarketplaceRepository>(
      (ref) => ProductMarketplaceRepository(
        ref.watch(publicGraphqlClientProvider),
      ),
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
        minRegular: moneyFromJson(min?['regular_price'] as Map<String, dynamic>?),
        minFinal: moneyFromJson(min?['final_price'] as Map<String, dynamic>?),
        maxRegular: moneyFromJson(max?['regular_price'] as Map<String, dynamic>?),
        maxFinal: moneyFromJson(max?['final_price'] as Map<String, dynamic>?),
      );
    }
  }
  return ProductMarketplace(seller: seller, bundle: bundle);
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
        if (hmString(a['code']) case final code?) code: hmInt(a['value_index']) ?? 0,
    },
    regularPrice: moneyFromJson(min?['regular_price'] as Map<String, dynamic>?),
    finalPrice: moneyFromJson(min?['final_price'] as Map<String, dynamic>?),
    inStock: product?['stock_status'] != 'OUT_OF_STOCK',
    imageUrl: httpsMediaUrl(
      (product?['image'] as Map<String, dynamic>?)?['url'] as String?,
    ),
  );
}
