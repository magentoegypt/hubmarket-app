import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/util/media.dart';
import '../domain/aggregation.dart';
import '../domain/category.dart';
import '../domain/money.dart';
import '../domain/product.dart';
import '../domain/product_detail.dart';
import '../domain/product_page.dart';
import 'catalog_queries.dart';
import 'product_mapper.dart';

// Magento's ProductAttributeSortInput on this store exposes only manufacturer /
// name / position / price / relevance — there is NO created_at / newest_sort, so
// the website's "Newest First" sort can't be issued via GraphQL. The Sort panel
// shows it disabled (see kNewestSortSupported) until the backend adds the field.
enum ProductSortField { relevance, priceAsc, priceDesc, nameAsc }

/// The live GraphQL `ProductAttributeSortInput` has no newest/date sort field,
/// so the website's "Newest First" option can't be requested yet. The Sort panel
/// renders it disabled until the backend adds `newest_sort`; flip this to `true`
/// (and add a `ProductSortField.newest` → `{newest_sort: DESC}` mapping) then.
/// Tracked in ClickUp 86d3m97au.
const bool kNewestSortSupported = false;

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

  /// Ceiling on one [fetchCategoryThumbnails] batch — the deepest category
  /// level on this store has fewer children than this.
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

  /// Strips the scheme/host and a leading store-code segment (e.g. `uae-en`,
  /// `eg_ar`) from a storefront URL, leaving the store-relative path that
  /// `urlResolver` expects (it's scoped by the active Store header).
  String _storeRelativePath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    var segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty &&
        RegExp(r'^[a-z]{2,4}[-_][a-z]{2}$').hasMatch(segs.first)) {
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
    // Brand landing: filter by the manufacturer attribute option id (the true
    // "Shop by Brand" product set), NOT a text search on the brand name — a
    // name search returns cross-brand matches. `Brand.optionId` supplies this.
    if (manufacturerId != null) {
      filter['manufacturer'] = <String, dynamic>{'eq': manufacturerId.toString()};
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
    // `discount` and `rating` are custom store attributes (added by the beauty
    // theme's layered nav) exposed as FilterRangeTypeInput — a lower-bound
    // threshold, mirroring the website's "N% or more" / "N★ & above" buckets.
    // They are NOT returned in `aggregations`, so the buckets are fixed app-side.
    if (minDiscount != null) {
      filter['discount'] = <String, dynamic>{'from': minDiscount.toString()};
    }
    if (minRating != null) {
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
    return _parseProductDetail(first);
  }

  ProductDetail _parseProductDetail(Map<String, dynamic> json) {
    final minPrice =
        (json['price_range'] as Map<String, dynamic>?)?['minimum_price']
            as Map<String, dynamic>?;

    final gallery = <String>[];
    final mainImage = httpsMediaUrl(
      (json['image'] as Map<String, dynamic>?)?['url'] as String?,
    );
    if (mainImage != null && mainImage.isNotEmpty) gallery.add(mainImage);
    for (final g in (json['media_gallery'] as List<dynamic>? ?? const [])) {
      if (g is Map<String, dynamic> && g['url'] is String) {
        gallery.add(httpsMediaUrl(g['url'] as String)!);
      }
    }

    final options = (json['configurable_options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (o) => ConfigurableOption(
            attributeCode: (o['attribute_code'] as String?) ?? '',
            label: (o['label'] as String?) ?? '',
            values: (o['values'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(
                  (v) => SwatchValue(
                    valueIndex: (v['value_index'] as int?) ?? 0,
                    label: (v['label'] as String?) ?? '',
                    uid: v['uid'] as String?,
                    swatchColor:
                        (v['swatch_data'] as Map<String, dynamic>?)?['value']
                            as String?,
                  ),
                )
                .toList(),
          ),
        )
        .toList();

    final variants = (json['variants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((vt) {
          final attrs = <String, int>{};
          for (final a in (vt['attributes'] as List<dynamic>? ?? const [])) {
            if (a is Map<String, dynamic> && a['code'] is String) {
              attrs[a['code'] as String] = (a['value_index'] as int?) ?? 0;
            }
          }
          final product = vt['product'] as Map<String, dynamic>?;
          final variantMin =
              (product?['price_range']
                      as Map<String, dynamic>?)?['minimum_price']
                  as Map<String, dynamic>?;
          return ProductVariant(
            sku: (product?['sku'] as String?) ?? '',
            attributes: attrs,
            price: _parseMoney(
              variantMin?['final_price'] as Map<String, dynamic>?,
            ),
            inStock: (product?['stock_status'] as String?) != 'OUT_OF_STOCK',
            imageUrl: httpsMediaUrl(
              (product?['image'] as Map<String, dynamic>?)?['url'] as String?,
            ),
          );
        })
        .toList();

    // "More Information" tab — the storefront-visible additional attributes
    // (Magento `custom_attributesV2(is_visible_on_front:true)`), mirroring the
    // website's product-details table. Selected-option attributes carry a label
    // (e.g. manufacturer → "Emporio Armani"); plain ones carry a value. Blank
    // values (color/material set to a space) are dropped, matching the site.
    final attributes = <ProductAttribute>[];
    String? brand;
    final customAttrs =
        (json['custom_attributesV2'] as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    for (final item in customAttrs ?? const []) {
      if (item is! Map<String, dynamic>) continue;
      final code = (item['code'] as String?) ?? '';
      final selected = item['selected_options'] as List<dynamic>?;
      final value = (selected != null && selected.isNotEmpty)
          ? ((selected.first as Map<String, dynamic>?)?['label'] as String? ??
                '')
          : (item['value'] as String? ?? '');
      final trimmed = value.trim();
      if (code.isEmpty || trimmed.isEmpty) continue;
      if (code == 'manufacturer') brand = trimmed;
      attributes.add(ProductAttribute(code: code, value: trimmed));
    }

    return ProductDetail(
      sku: (json['sku'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      urlKey: (json['url_key'] as String?) ?? '',
      brand: brand,
      attributes: attributes,
      description: _stripHtml(
        (json['description'] as Map<String, dynamic>?)?['html'] as String?,
      ),
      shortDescription: _stripHtml(
        (json['short_description'] as Map<String, dynamic>?)?['html']
            as String?,
      ),
      gallery: gallery.toSet().toList(growable: false),
      regularPrice: _parseMoney(
        minPrice?['regular_price'] as Map<String, dynamic>?,
      ),
      finalPrice: _parseMoney(
        minPrice?['final_price'] as Map<String, dynamic>?,
      ),
      inStock: (json['stock_status'] as String?) != 'OUT_OF_STOCK',
      badge: badgeFromJson(json),
      options: options,
      variants: variants,
      ratingSummary: (json['rating_summary'] as int?) ?? 0,
      reviewCount: (json['review_count'] as int?) ?? 0,
      ratingHistogram: (json['rating_histogram'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (b) => RatingBar(
              stars: (b['stars'] as num?)?.toInt() ?? 0,
              count: (b['count'] as num?)?.toInt() ?? 0,
              percent: (b['percent'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(growable: false),
      alsoLike: (json['also_like_products'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(productFromJson)
          .toList(growable: false),
      reviews:
          ((json['reviews'] as Map<String, dynamic>?)?['items']
                      as List<dynamic>? ??
                  const [])
              .whereType<Map<String, dynamic>>()
              .map(
                (r) => ProductReview(
                  nickname: (r['nickname'] as String?) ?? '',
                  summary: (r['summary'] as String?) ?? '',
                  text: (r['text'] as String?) ?? '',
                  averageRating: (r['average_rating'] as num?)?.toInt() ?? 0,
                  date: (r['created_at'] as String?) ?? '',
                ),
              )
              .toList(),
    );
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

  /// Submits a review. Magento's form has three rating dimensions (Quality /
  /// Value / Price); we send a value for each so the review saves with the same
  /// shape the website produces. [ratings] is `(id, value_id)` per dimension.
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

  /// Decodes the HTML entities Page Builder ships — including entity-*encoded*
  /// tags (`&lt;p&gt;…`) that AR content commonly emits, which would otherwise
  /// render as literal `<p>` text after the tag strip in [_stripHtml].
  String _decodeHtmlEntities(String s) => s
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  String? _stripHtml(String? html) {
    if (html == null || html.isEmpty) return null;
    // Decode entities first so entity-encoded tags (AR Page Builder) get
    // stripped below instead of showing as literal HTML.
    final text = _decodeHtmlEntities(html)
        // Drop <style>/<script> blocks entirely — Page Builder emits a
        // <style> block whose CSS would otherwise leak into the description.
        .replaceAll(
          RegExp(
            r'<(style|script)[^>]*>.*?</\1>',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        // Turn list items into bullet lines and block breaks into newlines so
        // the short description (a <ul> of features) keeps its structure.
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
        .replaceAll(
          RegExp(r'</(p|div|li|ul|ol|tr|h[1-6])>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp('<[^>]*>'), ' ')
        // Collapse runs of spaces/tabs but keep newlines, then trim each line
        // and drop the empties.
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    return text.isEmpty ? null : text;
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

  Money? _parseMoney(Map<String, dynamic>? json) => moneyFromJson(json);

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
