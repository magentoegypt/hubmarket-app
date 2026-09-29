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

/// Maps a listing product (PLP / search / wishlist / PDP rails). [now] only
/// pins "today" for the NEW badge in tests.
Product productFromJson(Map<String, dynamic> json, {DateTime? now}) {
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
    badge: badgeFromJson(json, now: now),
  );
}

/// The merchandising badge the catalogue can actually back.
///
/// Hub Market has no NEW / bestseller flags of its own, so NEW comes from
/// Magento's core "Set Product as New From / To" dates (`new_from_date` /
/// `new_to_date`, see [isNewByDateWindow]). [ProductBadge.bestseller] is never
/// produced: the store has no bestseller attribute, and a guessed one would be
/// fabricated merchandising.
ProductBadge badgeFromJson(Map<String, dynamic> json, {DateTime? now}) =>
    isNewByDateWindow(json['new_from_date'], json['new_to_date'], now: now)
    ? ProductBadge.isNew
    : ProductBadge.none;

/// Whether today falls inside a product's "new" window — the rule Magento's
/// own New Products widget applies: at least one bound is set, `from` (when
/// set) is on or before today and `to` (when set) is on or after today.
///
/// Compared by calendar day: Magento stores both as dates and returns them as
/// `2026-09-10 00:00:00`. "Today" is the device's date, which can differ from
/// the store's (Asia/Riyadh) date for a few hours around midnight — harmless
/// for a badge. A bound that is set but unreadable yields no badge rather than
/// a guess.
bool isNewByDateWindow(Object? from, Object? to, {DateTime? now}) {
  final fromText = from is String ? from.trim() : '';
  final toText = to is String ? to.trim() : '';
  if (fromText.isEmpty && toText.isEmpty) return false;
  final start = fromText.isEmpty ? null : _calendarDay(fromText);
  final end = toText.isEmpty ? null : _calendarDay(toText);
  if ((fromText.isNotEmpty && start == null) ||
      (toText.isNotEmpty && end == null)) {
    return false;
  }
  final clock = now ?? DateTime.now();
  final today = DateTime.utc(clock.year, clock.month, clock.day);
  if (start != null && today.isBefore(start)) return false;
  if (end != null && today.isAfter(end)) return false;
  return true;
}

/// The calendar day of a Magento date / datetime string (`YYYY-MM-DD…`), as a
/// UTC midnight so comparisons ignore DST. Null for anything else, including
/// roll-overs such as `0000-00-00` or `2026-02-31`.
DateTime? _calendarDay(String value) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Maps one `products.items[0]` of the PDP query to a [ProductDetail]. [now]
/// only pins "today" for the NEW badge in tests.
ProductDetail productDetailFromJson(
  Map<String, dynamic> json, {
  DateTime? now,
}) {
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
    badge: badgeFromJson(json, now: now),
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
    alsoLike: alsoLikeFromJson(json, now: now),
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

/// Most "You may also like" cards the PDP shows.
const int _alsoLikeLimit = 8;

/// "You may also like" for the PDP: Magento's core `related_products` first,
/// then `upsell_products`, de-duplicated by SKU and capped at 8.
///
/// The product itself is skipped — the live catalogue links some products to
/// themselves — and so is any entry without a SKU or url_key, which could not
/// open a PDP. Empty when neither list has anything, which hides the rail.
List<Product> alsoLikeFromJson(Map<String, dynamic> json, {DateTime? now}) {
  final seen = <String>{};
  final ownSku = json['sku'];
  if (ownSku is String && ownSku.isNotEmpty) seen.add(ownSku);
  final picks = <Product>[];
  for (final source in const ['related_products', 'upsell_products']) {
    for (final item in json[source] as List<dynamic>? ?? const []) {
      if (item is! Map<String, dynamic>) continue;
      final product = productFromJson(item, now: now);
      if (product.sku.isEmpty || product.urlKey.isEmpty) continue;
      if (!seen.add(product.sku)) continue;
      picks.add(product);
      if (picks.length == _alsoLikeLimit) return List.unmodifiable(picks);
    }
  }
  return List.unmodifiable(picks);
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
