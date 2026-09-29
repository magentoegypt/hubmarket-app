import '../../../core/util/media.dart';
import '../domain/money.dart';
import '../domain/product.dart';
import '../domain/product_detail.dart';

/// Shared parsers for the common `Money` and listing-`Product` GraphQL shapes,
/// reused by catalogue and wishlist repositories.
Money? moneyFromJson(Map<String, dynamic>? json) {
  final value = json?['value'];
  if (value is! num) return null;
  return Money(
    amount: value.toDouble(),
    currency: (json!['currency'] as String?) ?? 'AED',
  );
}

Product productFromJson(Map<String, dynamic> json) {
  final image = json['image'] as Map<String, dynamic>?;
  final minPrice =
      (json['price_range'] as Map<String, dynamic>?)?['minimum_price']
          as Map<String, dynamic>?;
  return Product(
    sku: (json['sku'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    urlKey: (json['url_key'] as String?) ?? '',
    imageUrl: httpsMediaUrl(image?['url'] as String?),
    regularPrice: moneyFromJson(
      minPrice?['regular_price'] as Map<String, dynamic>?,
    ),
    finalPrice: moneyFromJson(
      minPrice?['final_price'] as Map<String, dynamic>?,
    ),
    inStock: (json['stock_status'] as String?) != 'OUT_OF_STOCK',
    badge: badgeFromJson(json),
  );
}

/// Maps the backend `is_new_arrival` / `is_bestseller` flags to a single
/// merchandising badge. Bestseller wins when a product qualifies for both.
/// Tolerates GraphQL Boolean or Magento Int (0/1). Absent fields → no badge.
ProductBadge badgeFromJson(Map<String, dynamic> json) {
  bool truthy(Object? v) => v == true || (v is num && v != 0);
  if (truthy(json['is_bestseller'])) return ProductBadge.bestseller;
  if (truthy(json['is_new_arrival'])) return ProductBadge.isNew;
  return ProductBadge.none;
}

/// Maps one `products.items[0]` of the PDP query to a [ProductDetail].
ProductDetail productDetailFromJson(Map<String, dynamic> json) {
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
          price: moneyFromJson(
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
      (json['short_description'] as Map<String, dynamic>?)?['html'] as String?,
    ),
    gallery: gallery.toSet().toList(growable: false),
    regularPrice: moneyFromJson(
      minPrice?['regular_price'] as Map<String, dynamic>?,
    ),
    finalPrice: moneyFromJson(
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
