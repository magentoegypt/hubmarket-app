import '../../../core/util/media.dart';
import '../domain/money.dart';
import '../domain/product.dart';
import '../domain/product_detail.dart';

/// Hub Market's brand attribute (label "Brand"), used for the brand landing
/// filter and the PDP brand line. Core `manufacturer` exists but is neither
/// filterable nor filled on this store; it is still honoured on the PDP.
const String kBrandAttributeCode = 'mgs_brand';

const Set<String> _brandAttributeCodes = {kBrandAttributeCode, 'manufacturer'};

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

/// A GraphQL number that may come as a numeric string; null for anything
/// else.
num? _number(Object? value) =>
    value is num ? value : (value is String ? num.tryParse(value.trim()) : null);

/// Maps a listing product (PLP / search / wishlist / PDP rails). [now] only
/// pins "today" for the NEW badge in tests. The rating fields stay null when
/// the document didn't ask for `rating_summary` / `review_count`, the seller
/// ones unless it asked for `hm_seller` (`SellerSelections.withCardSellers`).
Product productFromJson(Map<String, dynamic> json, {DateTime? now}) {
  final image = json['image'] as Map<String, dynamic>?;
  final minPrice =
      (json['price_range'] as Map<String, dynamic>?)?['minimum_price']
          as Map<String, dynamic>?;
  final seller = json['hm_seller'];
  // Hub Market's own products: the website's card leaves the seller line empty.
  final sold = seller is Map<String, dynamic> && seller['is_marketplace'] != true
      ? seller
      : null;
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
    categories: productCategoriesFromJson(json['categories']),
    typeId: productTypeFromTypename(json['__typename']),
    ratingSummary: _number(json['rating_summary'])?.toDouble(),
    reviewCount: _number(json['review_count'])?.toInt(),
    sellerKnown: json.containsKey('hm_seller'),
    sellerName: _text(sold?['name']),
    sellerCode: _text(sold?['code']),
  );
}

/// A trimmed non-empty string, else null.
String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

/// Magento's product type from a GraphQL item's `__typename` (which the
/// client adds to every selection): `ConfigurableProduct` → `configurable`,
/// `SimpleProduct` → `simple`. Null for anything else.
String? productTypeFromTypename(Object? typename) {
  if (typename is! String || !typename.endsWith('Product')) return null;
  final type = typename.substring(0, typename.length - 'Product'.length);
  return type.isEmpty ? null : type.toLowerCase();
}

/// `items.categories` of the search query → [ProductCategoryRef]s. Entries with
/// no uid or name are dropped. `include_in_menu` is an Int (0/1) on the wire,
/// like the category tree's, and an absent flag counts as shown.
List<ProductCategoryRef> productCategoriesFromJson(Object? json) {
  if (json is! List) return const <ProductCategoryRef>[];
  final refs = <ProductCategoryRef>[];
  for (final item in json.whereType<Map<String, dynamic>>()) {
    final uid = (item['uid'] as String?) ?? '';
    final name = ((item['name'] as String?) ?? '').trim();
    if (uid.isEmpty || name.isEmpty) continue;
    refs.add(
      ProductCategoryRef(
        uid: uid,
        name: name,
        level: (item['level'] as num?)?.toInt() ?? 0,
        inMenu: switch (item['include_in_menu']) {
          final bool flag => flag,
          final num flag => flag != 0,
          _ => true,
        },
      ),
    );
  }
  return List.unmodifiable(refs);
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

/// A configurable product's `configurable_options` (swatches, sizes): the
/// product page's and a bundle's configurable children's.
List<ConfigurableOption> configurableOptionsFromJson(Object? json) => [
  for (final o in (json is List ? json : const []).whereType<Map<String, dynamic>>())
    ConfigurableOption(
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
];

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

  final options = configurableOptionsFromJson(json['configurable_options']);

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
          onlyLeft: _unitsLeft(product?['only_x_left_in_stock']),
        );
      })
      .toList();

  // "More Information" tab — the storefront-visible additional attributes
  // (Magento `custom_attributesV2(is_visible_on_front:true)`), mirroring the
  // website's product-details table. Selected-option attributes carry labels
  // (e.g. mgs_brand → "Samsung"; a multiselect such as material lists every
  // label: "Nylon, CoolTech™, Wool"); plain ones carry a value. Option labels
  // are entity-decoded (the catalogue stores "CoolTech&trade;"). Blank values
  // are dropped, matching the site.
  final attributes = <ProductAttribute>[];
  String? brand;
  int? brandOptionId;
  final customAttrs =
      (json['custom_attributesV2'] as Map<String, dynamic>?)?['items']
          as List<dynamic>?;
  for (final item in customAttrs ?? const []) {
    if (item is! Map<String, dynamic>) continue;
    final code = (item['code'] as String?) ?? '';
    final labels = [
      for (final option in item['selected_options'] as List<dynamic>? ?? [])
        if (option is Map<String, dynamic>)
          _decodeHtmlEntities((option['label'] as String? ?? '').trim()),
    ].where((label) => label.isNotEmpty);
    final value = labels.isNotEmpty
        ? labels.join(', ')
        : (item['value'] as String? ?? '').trim();
    if (code.isEmpty || value.isEmpty) continue;
    final isBrand = _brandAttributeCodes.contains(code);
    if (isBrand && brand == null) {
      brand = value;
      // The option id brand pages filter on — only `mgs_brand`'s own, and
      // only for a single brand.
      final options = item['selected_options'];
      if (code == kBrandAttributeCode && options is List && options.length == 1) {
        final option = options.first;
        if (option is Map<String, dynamic>) {
          brandOptionId = int.tryParse('${option['value'] ?? ''}'.trim());
        }
      }
    }
    attributes.add(ProductAttribute(code: code, value: value, isBrand: isBrand));
  }

  return ProductDetail(
    sku: (json['sku'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    urlKey: (json['url_key'] as String?) ?? '',
    typeId: productTypeFromTypename(json['__typename']),
    brand: brand,
    brandOptionId: brandOptionId,
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
    // `Float!` in the schema; integral on the wire today, so tolerate both.
    ratingSummary: (json['rating_summary'] as num?)?.round() ?? 0,
    reviewCount: (json['review_count'] as int?) ?? 0,
    alsoLike: alsoLikeFromJson(json, now: now),
    onlyLeft: _unitsLeft(json['only_x_left_in_stock']),
    categories: productCategoriesFromJson(json['categories']),
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

/// `only_x_left_in_stock`: a Float the store fills only while the "Only X left"
/// threshold is set and the stock is at or under it. Null for anything but a
/// positive number.
int? _unitsLeft(Object? value) {
  final left = _number(value);
  return left != null && left > 0 ? left.round() : null;
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
    .replaceAll('&trade;', '™')
    .replaceAll('&reg;', '®')
    .replaceAll('&copy;', '©')
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
