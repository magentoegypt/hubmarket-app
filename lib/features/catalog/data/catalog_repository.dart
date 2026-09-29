import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/util/media.dart';
import '../domain/aggregation.dart';
import '../domain/category.dart';
import '../domain/product.dart';
import '../domain/product_detail.dart';
import '../domain/product_page.dart';
import 'catalog_queries.dart';
import 'product_mapper.dart';

// Hub Market's ProductAttributeSortInput exposes only color / name / position /
// price / relevance — there is NO created_at / newest sort, so the website's
// "Newest First" sort can't be issued via GraphQL. The Sort panel shows it
// disabled (see kNewestSortSupported) until the backend adds such a field.
enum ProductSortField { relevance, priceAsc, priceDesc, nameAsc }

/// The live GraphQL `ProductAttributeSortInput` has no newest/date sort field,
/// so the website's "Newest First" option can't be requested yet. The Sort panel
/// renders it disabled; flip this to `true` (and add a `ProductSortField.newest`
/// mapping) once the backend exposes a sortable date attribute.
const bool kNewestSortSupported = false;

/// Hub Market's `ProductAttributeFilterInput` has no `discount` or `rating`
/// field (both were Zoonze theme attributes), and Magento rejects the whole
/// query when one is sent. Until the backend exposes filterable attributes for
/// them, the filter sheet hides the "N% or more" / "N★ & above" sections and
/// [CatalogRepository.fetchProducts] never sends the thresholds.
const bool kDiscountFilterSupported = false;

/// See [kDiscountFilterSupported].
const bool kRatingFilterSupported = false;

/// Reads catalogue data via GraphQL and returns domain entities (or throws a
/// [Failure]). Presentation never sees a raw GraphQL map.
class CatalogRepository {
  CatalogRepository(this._client);

  final GraphQLClient _client;

  Future<List<Category>> fetchCategoryTree() async {
    final data = await _query(CatalogQueries.categoryTree, const {});
    final roots = (data['categoryList'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseCategory)
        .toList();
    // categoryList returns the root category(ies); the browsable set is the
    // root's children when present. Hide categories flagged out of navigation.
    final source = (roots.isNotEmpty && roots.first.children.isNotEmpty)
        ? roots.first.children
        : roots;
    return source.where((c) => c.includeInMenu).toList(growable: false);
  }

  /// Stand-in thumbnails for categories with no `image` of their own: the first
  /// product inside each, in a single aliased round trip. Mirrors what the
  /// storefront does for its sub-category rail.
  ///
  /// Keyed by category uid, and **sparse** — a uid whose category holds no
  /// products is simply absent, so the caller can tell "nothing to show" from
  /// "not fetched yet" and fall back to the neutral placeholder rather than
  /// inventing an image.
  Future<Map<String, String>> fetchCategoryThumbnails(
    List<String> categoryUids,
  ) async {
    // Distinct + capped: this is one query whose size grows with the list, and
    // no surface shows more categories at once than this.
    final uids = categoryUids
        .where((u) => u.isNotEmpty)
        .toSet()
        .take(_thumbnailBatchLimit)
        .toList(growable: false);
    if (uids.isEmpty) return const <String, String>{};

    final data = await _query(
      CatalogQueries.categoryThumbnails(uids.length),
      <String, dynamic>{
        for (var i = 0; i < uids.length; i++) 'u$i': uids[i],
      },
    );

    final thumbnails = <String, String>{};
    for (var i = 0; i < uids.length; i++) {
      final items = (data['c$i'] as Map<String, dynamic>?)?['items'];
      final first = (items as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .firstOrNull;
      final url = httpsMediaUrl(
        (first?['image'] as Map<String, dynamic>?)?['url'] as String?,
      );
      if (url != null && url.isNotEmpty) thumbnails[uids[i]] = url;
    }
    return thumbnails;
  }

  /// Ceiling on one [fetchCategoryThumbnails] batch — no category level on
  /// Hub Market has more children than this (27 at most, 2026-09-29).
  static const int _thumbnailBatchLimit = 40;

  /// Resolves a storefront URL (e.g. a hero CTA's friendly `.html` category or
  /// product URL) to its entity via Magento's `urlResolver`, so the app opens
  /// the right in-app screen instead of guessing from the path. `uid` is the
  /// entity uid (used for a CATEGORY PLP); for a PRODUCT, `urlKey` carries the
  /// PDP key. Null when it can't be resolved.
  Future<({String type, String uid, String? urlKey})?> resolveUrl(
    String storeUrl,
  ) async {
    final path = _storeRelativePath(storeUrl);
    if (path.isEmpty) return null;
    try {
      final data = await _query(CatalogQueries.urlResolve, {'url': path});
      final r = data['urlResolver'] as Map<String, dynamic>?;
      if (r == null) return null;
      final relative = (r['relative_url'] as String?) ?? path;
      final segs = relative.split('/').where((s) => s.isNotEmpty).toList();
      final last = segs.isEmpty ? '' : segs.last;
      final urlKey = last.toLowerCase().endsWith('.html')
          ? last.substring(0, last.length - 5)
          : last;
      return (
        type: (r['type'] as String?) ?? '',
        uid: (r['entity_uid'] as String?) ?? '',
        urlKey: urlKey.isEmpty ? null : urlKey,
      );
    } on Object {
      return null;
    }
  }

  /// Strips the scheme/host and a leading store-code segment from a storefront
  /// URL, leaving the store-relative path that `urlResolver` expects — it is
  /// scoped by the Store header and returns null for `en/<key>.html`. Hub
  /// Market's segments are `en` / `ar` (its `base_link_url`s); `uae-en`-style
  /// codes are still accepted.
  String _storeRelativePath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    var segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length > 1 &&
        RegExp(r'^(?:[a-z]{2}|[a-z]{2,4}[-_][a-z]{2})$').hasMatch(segs.first)) {
      segs = segs.sublist(1);
    }
    return segs.join('/');
  }

  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? manufacturerId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    assert(
      (search != null && search.isNotEmpty) ||
          categoryUid != null ||
          manufacturerId != null,
      'products query requires a search, a categoryUid, or a manufacturerId',
    );
    final sortInput = _sortInput(sort);
    final filter = <String, dynamic>{};
    if (categoryUid != null) {
      filter['category_uid'] = <String, dynamic>{'eq': categoryUid};
    }
    // Brand landing: filter by the brand attribute's option id (the true
    // "Shop by Brand" product set), NOT a text search on the brand name — a
    // name search returns cross-brand matches. `Brand.optionId` supplies this.
    // Hub Market's brand attribute is `mgs_brand` (label "Brand"); core
    // `manufacturer` is not filterable here, so sending it fails the query.
    // The parameter keeps its old name for the existing callers.
    if (manufacturerId != null) {
      filter[kBrandAttributeCode] = <String, dynamic>{
        'eq': manufacturerId.toString(),
      };
    }
    attributeFilters.forEach((code, values) {
      // 'price' uses a range input (handled below); apply equal-type filters
      // for the rest as `{in: [...]}`.
      if (code != 'price' && values.isNotEmpty) {
        filter[code] = <String, dynamic>{'in': values.toList()};
      }
    });
    // Magento's ProductAttributeFilterInput.price is a FilterRangeTypeInput
    // ({from, to} as strings). Send whichever bound is set.
    if (priceFrom != null || priceTo != null) {
      filter['price'] = <String, dynamic>{
        if (priceFrom != null) 'from': priceFrom.toStringAsFixed(2),
        if (priceTo != null) 'to': priceTo.toStringAsFixed(2),
      };
    }
    // Lower-bound "N% or more" / "N★ & above" thresholds, only where the store
    // has matching range attributes — Hub Market has neither, and an unknown
    // filter field fails the whole query (see kDiscountFilterSupported).
    if (kDiscountFilterSupported && minDiscount != null) {
      filter['discount'] = <String, dynamic>{'from': minDiscount.toString()};
    }
    if (kRatingFilterSupported && minRating != null) {
      filter['rating'] = <String, dynamic>{'from': minRating.toString()};
    }
    final variables = <String, dynamic>{
      'pageSize': pageSize,
      'currentPage': currentPage,
      if (search != null && search.isNotEmpty) 'search': search,
      if (filter.isNotEmpty) 'filter': filter,
      if (sortInput != null) 'sort': sortInput,
    };
    final data = await _query(CatalogQueries.products, variables);
    final products = data['products'] as Map<String, dynamic>?;
    return products == null ? ProductPage.empty : _parseProductPage(products);
  }

  /// Single product by url_key (PDP). Returns null when not found.
  Future<ProductDetail?> fetchProductDetail(String urlKey) async {
    final data = await _query(CatalogQueries.productDetail, <String, dynamic>{
      'urlKey': urlKey,
    });
    final items =
        (data['products'] as Map<String, dynamic>?)?['items'] as List<dynamic>?;
    if (items == null || items.isEmpty) return null;
    final first = items.first;
    if (first is! Map<String, dynamic>) return null;
    return productDetailFromJson(first);
  }

  Future<List<ReviewRatingMetadata>> fetchReviewRatingsMetadata() async {
    final data = await _query(CatalogQueries.reviewRatingsMetadata, const {});
    final items =
        (data['productReviewRatingsMetadata']
                as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    return (items ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => ReviewRatingMetadata(
            id: m['id']?.toString() ?? '',
            name: (m['name'] as String?) ?? '',
            values: (m['values'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(
                  (v) => ReviewRatingValue(
                    valueId: v['value_id']?.toString() ?? '',
                    // Magento returns `value` as a String ("5"); a raw
                    // `as num?` cast throws TypeError on a String and blanked
                    // the whole "Write a Review" screen. Parse tolerantly.
                    value: int.tryParse('${v['value']}') ?? 0,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  /// Submits a review with one value per rating dimension that
  /// `productReviewRatingsMetadata` lists (Hub Market has a single "Rating"),
  /// so the review saves with the same shape the website produces. [ratings]
  /// is `(id, value_id)` per dimension.
  Future<void> createReview({
    required String sku,
    required String nickname,
    required String summary,
    required String text,
    required List<({String id, String valueId})> ratings,
  }) async {
    await _mutate(CatalogQueries.createReview, {
      'input': <String, dynamic>{
        'sku': sku,
        'nickname': nickname,
        'summary': summary,
        'text': text,
        'ratings': [
          for (final r in ratings) {'id': r.id, 'value_id': r.valueId},
        ],
      },
    });
  }

  Future<Map<String, dynamic>> _mutate(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }

  Map<String, dynamic>? _sortInput(ProductSortField sort) {
    switch (sort) {
      case ProductSortField.relevance:
        return null;
      case ProductSortField.priceAsc:
        return <String, dynamic>{'price': 'ASC'};
      case ProductSortField.priceDesc:
        return <String, dynamic>{'price': 'DESC'};
      case ProductSortField.nameAsc:
        return <String, dynamic>{'name': 'ASC'};
    }
  }

  Future<Map<String, dynamic>> _query(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }

  Category _parseCategory(Map<String, dynamic> json) {
    final children = (json['children'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseCategory)
        .toList();
    return Category(
      uid: (json['uid'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      urlKey: (json['url_key'] as String?) ?? '',
      image: httpsMediaUrl(json['image'] as String?),
      productCount: (json['product_count'] as int?) ?? 0,
      // Magento returns include_in_menu as an Int (0/1), not a Boolean —
      // casting it `as bool` throws on real data. Accept int or bool.
      includeInMenu: _asBool(json['include_in_menu'], orElse: true),
      children: children,
    );
  }

  /// Coerces a GraphQL value to bool, tolerating Magento's Int (0/1) flags.
  bool _asBool(Object? value, {required bool orElse}) => switch (value) {
    final bool b => b,
    final num n => n != 0,
    _ => orElse,
  };

  ProductPage _parseProductPage(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseProduct)
        .toList();
    final pageInfo = json['page_info'] as Map<String, dynamic>?;
    return ProductPage(
      items: items,
      totalCount: (json['total_count'] as int?) ?? items.length,
      currentPage: (pageInfo?['current_page'] as int?) ?? 1,
      totalPages: (pageInfo?['total_pages'] as int?) ?? 1,
      aggregations: _parseAggregations(json['aggregations'] as List<dynamic>?),
    );
  }

  Product _parseProduct(Map<String, dynamic> json) => productFromJson(json);

  List<Aggregation> _parseAggregations(List<dynamic>? json) {
    if (json == null) return const [];
    return json.whereType<Map<String, dynamic>>().map((agg) {
      final options = (agg['options'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (o) => AggregationOption(
              label: (o['label'] as String?) ?? '',
              value: (o['value'] as String?) ?? '',
              count: (o['count'] as int?) ?? 0,
            ),
          )
          .toList();
      return Aggregation(
        attributeCode: (agg['attribute_code'] as String?) ?? '',
        label: (agg['label'] as String?) ?? '',
        options: options,
      );
    }).toList();
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(graphqlClientProvider)),
);
