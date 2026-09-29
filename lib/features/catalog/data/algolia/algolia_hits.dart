import '../../../../core/util/media.dart';
import '../../../cms/domain/cms_links.dart';
import '../../domain/category.dart';
import '../../domain/money.dart';
import '../../domain/product.dart';
import '../../domain/search_facets.dart';
import '../../domain/search_highlight.dart';
import '../../domain/search_results.dart';
import 'algolia_settings.dart';

// Maps Algolia records — as the Magento extension (3.18) indexes them for Hub
// Market — to the app's search types. Checked against the live indices on
// 29 Sep 2026:
//
//   products:   objectID, name, url (…/en/<url_key>.html), sku (a string, or
//               the parent + children for a configurable), type_id,
//               image_url, thumbnail_url, categories.level0…N ("A /// B"),
//               categoryIds, price.AED.{default, default_original_formated,
//               special_from_date, special_to_date}, rating_summary, seller
//   categories: objectID (the id), name, path, level, url, product_count,
//               include_in_menu
//   pages:      objectID, name, slug, url, content

String _text(Object? value) => value is String ? value.trim() : '';

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

/// A product URL's url_key — what the PDP route takes:
/// `https://…/en/sofabed123.html` → `sofabed123`. Empty when [url] doesn't
/// point at a product page.
String productUrlKeyFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final segments =
      uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
  if (segments.isEmpty) return '';
  final last = segments.last;
  if (last.toLowerCase().endsWith('.html')) {
    return last.substring(0, last.length - '.html'.length);
  }
  // Without the suffix only a path below the store segment can be a product.
  return segments.length > 1 ? last : '';
}

/// The amount in a price the storefront formatted for display — "AED 500",
/// the Arabic view's "500 د.إ.", "AED 1,299" — or null. Algolia carries the
/// pre-discount price only this way (`default_original_formated`), rounded as
/// the storefront shows prices (Hub Market: whole dirhams). For a range
/// ("AED 425 - AED 500") the first, lowest, amount.
double? parseFormattedPrice(Object? formatted) {
  if (formatted is! String || formatted.trim().isEmpty) return null;
  final western = formatted.replaceAllMapped(
    RegExp('[\u0660-\u0669\u06F0-\u06F9\u066B\u066C]'),
    (m) {
      final code = m.group(0)!.codeUnitAt(0);
      if (code == 0x066B) return '.';
      if (code == 0x066C) return ',';
      return '${code >= 0x06F0 ? code - 0x06F0 : code - 0x0660}';
    },
  );
  final match = RegExp(r'\d[\d,]*(?:\.\d+)?').firstMatch(western);
  return match == null
      ? null
      : double.tryParse(match.group(0)!.replaceAll(',', ''));
}

/// Whether a special price is running at [now]: Algolia keeps a record's
/// special price until the next reindex, so the storefront checks its
/// `special_from_date` / `special_to_date` (Unix seconds, or "") itself.
bool specialPriceActive(Object? from, Object? to, DateTime now) {
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  if (from is num && from > seconds) return false;
  if (to is num && to < seconds) return false;
  return true;
}

/// The name of the deepest category a product record is filed under —
/// "Home Furniture" from `categories.level1: ["Furniture /// Home Furniture"]`
/// — for the type-ahead's "in …" line. Null without categories.
String? deepestCategoryName(Object? categories, {String separator = ' /// '}) {
  if (categories is! Map) return null;
  var deepest = -1;
  String? name;
  for (final MapEntry(:key, :value) in categories.entries) {
    final level = int.tryParse('$key'.replaceFirst('level', ''));
    if (level == null || level <= deepest) continue;
    final paths = value is List ? value : [value];
    final path = paths
        .whereType<String>()
        .map((p) => p.trim())
        .firstWhere((p) => p.isNotEmpty, orElse: () => '');
    if (path.isEmpty) continue;
    final last = path.split(separator.trim()).last.trim();
    if (last.isEmpty) continue;
    deepest = level;
    name = last;
  }
  return name;
}

/// An absolute https URL for a record's image: absolute ones are upgraded to
/// https, root-relative ones resolved against the record's own [pageUrl].
String? _imageUrl(Object? value, String pageUrl) {
  final url = _text(value);
  if (url.isEmpty) return null;
  if (url.startsWith('http')) return httpsMediaUrl(url);
  final base = Uri.tryParse(pageUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) return null;
  return httpsMediaUrl(base.resolve(url).toString());
}

/// A products-index record as a [Product], or null when it lacks a name or a
/// product URL to open.
///
/// The price is the record's `price.<currency>.<group>`; a struck-through
/// regular price comes from `<group>_original_formated`, which the extension
/// writes only while a special price applies — and which the storefront
/// ignores once the special price's dates have passed, as this does.
Product? productFromAlgoliaHit(
  Map<String, dynamic> hit,
  AlgoliaSettings settings, {
  required DateTime now,
}) {
  final url = _text(hit['url']);
  final urlKey = productUrlKeyFromUrl(url);
  final name = _text(hit['name']);
  if (urlKey.isEmpty || name.isEmpty) return null;

  final sku = switch (hit['sku']) {
    final String single => single.trim(),
    final List<dynamic> many when many.isNotEmpty => '${many.first}'.trim(),
    _ => '',
  };

  Money? regular;
  Money? price;
  final prices = hit['price'];
  final byCurrency = prices is Map ? prices[settings.currencyCode] : null;
  if (byCurrency is Map && byCurrency[settings.priceGroup] is num) {
    var amount = (byCurrency[settings.priceGroup] as num).toDouble();
    var before = amount;
    final original = parseFormattedPrice(
      byCurrency['${settings.priceGroup}_original_formated'],
    );
    if (original != null && original > amount) {
      if (specialPriceActive(
        byCurrency['special_from_date'],
        byCurrency['special_to_date'],
        now,
      )) {
        before = original;
      } else {
        amount = original;
        before = original;
      }
    }
    price = Money(amount: amount, currency: settings.currencyCode);
    regular = Money(amount: before, currency: settings.currencyCode);
  }

  final type = _text(hit['type_id']);
  return Product(
    sku: sku,
    name: name,
    urlKey: urlKey,
    imageUrl: _imageUrl(hit['image_url'], url),
    thumbUrl: _imageUrl(hit['thumbnail_url'], url),
    regularPrice: regular,
    finalPrice: price,
    // The extension leaves out-of-stock products out of the index unless the
    // store shows them; then the record says so.
    inStock: switch (hit['in_stock']) {
      final bool flag => flag,
      final num flag => flag != 0,
      _ => true,
    },
    typeId: type.isEmpty ? null : type,
  );
}

/// A type-ahead product row: the product, its name's highlight from
/// `_highlightResult`, and its deepest category.
SearchProductHit? productHitFromAlgolia(
  Map<String, dynamic> hit,
  AlgoliaSettings settings, {
  required DateTime now,
  String query = '',
}) {
  final product = productFromAlgoliaHit(hit, settings, now: now);
  if (product == null) return null;
  final highlights = hit['_highlightResult'];
  final name = highlights is Map ? highlights['name'] : null;
  final highlighted = name is Map ? name['value'] : null;
  var matches = const <TextSlice>[];
  if (highlighted is String) {
    final parsed = parseHighlighted(highlighted);
    // Offsets are only good for the text they were taken from.
    if (parsed.text == product.name) matches = parsed.matches;
  } else {
    matches = searchMatchSlices(product.name, query);
  }
  return SearchProductHit(
    product: product,
    nameMatches: matches,
    categoryName: deepestCategoryName(
      hit['categories'],
      separator: settings.categorySeparator,
    ),
  );
}

/// A categories-index record as a [SearchCategory] chip: its id is the
/// `objectID`, whose base64 is the uid the category route takes.
SearchCategory? categoryFromAlgoliaHit(Map<String, dynamic> hit) {
  final id = '${hit['objectID'] ?? ''}'.trim();
  final name = _text(hit['name']);
  if (!RegExp(r'^\d+$').hasMatch(id) || name.isEmpty) return null;
  return SearchCategory(
    uid: categoryUidFromId(id),
    name: name,
    count: _int(hit['product_count']),
    level: _int(hit['level']),
  );
}

/// A pages-index record as a [SearchPageHit], or null without a title or a
/// page path (the store's home page).
SearchPageHit? pageFromAlgoliaHit(Map<String, dynamic> hit) {
  final title = _text(hit['name']);
  final url = _text(hit['url']);
  if (title.isEmpty || storePathOf(url).isEmpty) return null;
  return SearchPageHit(title: title, url: url);
}

/// A facet's value counts from a search response (`facets.<attribute>`), in
/// Algolia's order (most matches first).
Map<String, int> facetCounts(Object? facets, String attribute) {
  final values = facets is Map ? facets[attribute] : null;
  if (values is! Map) return const <String, int>{};
  return {
    for (final MapEntry(:key, :value) in values.entries)
      if ('$key'.trim().isNotEmpty && _int(value) > 0) '$key': _int(value),
  };
}

/// A numeric facet's bounds from a response's `facets_stats`, or null.
({double min, double max})? facetStats(Object? stats, String attribute) {
  final entry = stats is Map ? stats[attribute] : null;
  if (entry is! Map || entry['min'] is! num || entry['max'] is! num) {
    return null;
  }
  return (
    min: (entry['min'] as num).toDouble(),
    max: (entry['max'] as num).toDouble(),
  );
}
