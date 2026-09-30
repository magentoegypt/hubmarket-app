import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A stand-in for an Algolia *secured* key: base64 of a 64-hex HMAC and the
/// restrictions, as the storefront mints them. Not a real key.
String fakeSecuredKey({DateTime? validUntil, String tagFilters = ''}) {
  final until =
      (validUntil ?? DateTime.now().add(const Duration(hours: 20)))
          .millisecondsSinceEpoch ~/
      1000;
  return base64.encode(
    utf8.encode('${'ab' * 32}tagFilters=$tagFilters&validUntil=$until'),
  );
}

/// The storefront's `window.algoliaConfig` for [store], as the live pages
/// serve it (29 Sep 2026), with a fake key.
Map<String, dynamic> storefrontAlgoliaConfig({
  String store = 'en',
  String? apiKey,
  bool pages = true,
}) {
  final ar = store == 'ar';
  return {
    'applicationId': 'HL67ED06DQ',
    'apiKey': apiKey ?? fakeSecuredKey(),
    'indexName': 'hubmarket_$store',
    'baseIndexName': 'hubmarket_$store',
    'hitsPerPage': 12,
    'maxValuesPerFacet': 10,
    'currencyCode': 'AED',
    'priceGroup': 'default',
    'priceKey': '.AED.default',
    'showCatsNotIncludedInNavigation': false,
    'instant': {'enabled': false, 'categorySeparator': ' /// '},
    'autocomplete': {
      'enabled': true,
      'nbOfProductsSuggestions': 8,
      'nbOfCategoriesSuggestions': 2,
      'sections': [
        if (pages) {'name': 'pages', 'label': 'Pages', 'hitsPerPage': '2'},
      ],
    },
    'facets': [
      {'attribute': 'price', 'type': 'slider', 'label': ar ? 'السعر' : 'Price'},
      {
        'attribute': 'categories',
        'type': 'conjunctive',
        'label': ar ? 'الفئات' : 'Categories',
      },
      {
        'attribute': 'mgs_brand',
        'type': 'disjunctive',
        'label': ar ? 'العلامة التجارية' : 'Brand',
      },
      {
        'attribute': 'color',
        'type': 'disjunctive',
        'label': ar ? 'اللون' : 'Color',
      },
      {
        'attribute': 'seller',
        'type': 'disjunctive',
        'label': ar ? 'البائع' : 'Seller',
      },
      {
        'attribute': 'rating_summary',
        'type': 'slider',
        'label': ar ? 'التقييم' : 'Rating',
      },
    ],
    'sortingIndices': [
      {
        'attribute': 'price',
        'sort': 'asc',
        'name': 'hubmarket_${store}_products_price_default_asc',
        'label': ar ? 'الأقل سعراً' : 'Lowest price',
      },
      {
        'attribute': 'price',
        'sort': 'desc',
        'name': 'hubmarket_${store}_products_price_default_desc',
        'label': ar ? 'الأعلى سعراً' : 'Highest price',
      },
      {
        'attribute': 'created_at',
        'sort': 'desc',
        'name': 'hubmarket_${store}_products_created_at_desc',
        'label': ar ? 'الأحدث أولاً' : 'Newest first',
      },
    ],
    'translations': {'hmIn': ar ? 'في' : 'in'},
  };
}

/// A storefront page carrying [config] the way Magento renders it: the JSON
/// inside a JavaScript string literal with every character but letters,
/// digits, space and `,._` written as `\uXXXX`.
String storefrontHtml(Map<String, dynamic> config) {
  final literal = StringBuffer();
  for (final unit in jsonEncode(config).codeUnits) {
    final char = String.fromCharCode(unit);
    if (RegExp(r'[A-Za-z0-9 ,._]').hasMatch(char)) {
      literal.write(char);
    } else {
      literal.write(
        '\\u${unit.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      );
    }
  }
  return '<!doctype html><html><head><title>Hub Market</title></head><body>'
      '<script>window.algoliaConfig = JSON.parse(\'$literal\')</script>'
      '<script>(function () { var c = window.algoliaConfig; })();</script>'
      '</body></html>';
}

/// One search of a recorded multi-query.
class RecordedQuery {
  RecordedQuery(this.indexName, this.params);

  final String indexName;

  /// Decoded parameters; list values are still JSON strings.
  final Map<String, String> params;

  String get query => params['query'] ?? '';

  /// A JSON-valued parameter, decoded.
  Object? json(String name) =>
      params[name] == null ? null : jsonDecode(params[name]!);
}

/// Answers one search: its results map (`hits`, `nbHits`, `facets`, …).
typedef AlgoliaAnswer = Map<String, dynamic> Function(RecordedQuery query);

/// A fake of both backends the app's Algolia search talks to: the storefront
/// page that carries `window.algoliaConfig`, and Algolia's multi-query
/// endpoint. Records every request.
class FakeAlgoliaBackend {
  FakeAlgoliaBackend({
    Map<String, Map<String, dynamic>>? configs,
    this.answer,
    this.pageStatus = 200,
    this.algoliaStatus = 200,
  }) : configs =
           configs ??
           {
             'en': storefrontAlgoliaConfig(),
             'ar': storefrontAlgoliaConfig(store: 'ar'),
           };

  /// `algoliaConfig` per store code; a store without one serves a page
  /// without it.
  final Map<String, Map<String, dynamic>> configs;
  AlgoliaAnswer? answer;
  int pageStatus;
  int algoliaStatus;

  final List<http.Request> pageRequests = [];
  final List<http.Request> algoliaRequests = [];

  /// Every search Algolia was asked, in order.
  final List<RecordedQuery> queries = [];

  /// The searches of the last multi-query call.
  List<RecordedQuery> lastCall = const [];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    if (request.method == 'GET') {
      pageRequests.add(request);
      if (pageStatus != 200) return http.Response('down', pageStatus);
      final segments = request.url.pathSegments.where((s) => s.isNotEmpty);
      final store = segments.isEmpty ? '' : segments.last;
      final config = configs[store];
      return http.Response.bytes(
        utf8.encode(
          config == null
              ? '<html><body>No search here</body></html>'
              : storefrontHtml(config),
        ),
        200,
        headers: {'content-type': 'text/html; charset=UTF-8'},
      );
    }

    algoliaRequests.add(request);
    if (algoliaStatus != 200) {
      return http.Response(
        jsonEncode({
          'message': 'Invalid Application-ID or API key',
          'status': algoliaStatus,
        }),
        algoliaStatus,
      );
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final call = [
      for (final r in (body['requests'] as List).cast<Map<String, dynamic>>())
        RecordedQuery(
          r['indexName'] as String,
          Uri.splitQueryString(r['params'] as String),
        ),
    ];
    queries.addAll(call);
    lastCall = call;
    final respond = answer ?? (_) => emptyResult();
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'results': [for (final q in call) respond(q)],
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=UTF-8'},
    );
  }
}

/// An Algolia search result with nothing in it.
Map<String, dynamic> emptyResult() => {
  'hits': <Object>[],
  'nbHits': 0,
  'page': 0,
  'nbPages': 0,
  'hitsPerPage': 0,
};

/// A products-index record as the Magento extension writes it.
Map<String, dynamic> productRecord({
  required String id,
  required String name,
  required String urlKey,
  String store = 'en',
  Object? sku,
  String type = 'simple',
  num price = 100,
  String? original,
  Object? specialTo,
  List<String> categoryPaths = const [],
  List<String> categoryIds = const [],
  String? highlighted,
  String? seller,
  String? sellerKey,
}) => {
  'objectID': id,
  'name': name,
  // AlgoliaVendor AddSellerData: a seller's product carries its seller.
  'seller': ?seller,
  'seller_url_key': ?sellerKey,
  'url': 'https://hub-market.magento2.click/$store/$urlKey.html',
  'sku': sku ?? urlKey,
  'type_id': type,
  'image_url':
      'https://hub-market.magento2.click/media/catalog/product/cache/big/$urlKey.jpg',
  'thumbnail_url':
      'https://hub-market.magento2.click/media/catalog/product/cache/small/$urlKey.jpg',
  'price': {
    'AED': {
      'default': price,
      'default_formated': 'AED\u00A0$price',
      'special_from_date': '',
      'special_to_date': specialTo ?? '',
      'default_original_formated': ?original,
    },
  },
  'categories': {
    for (var level = 0; level < categoryPaths.length; level++)
      'level$level': [categoryPaths[level]],
  },
  'categoryIds': categoryIds,
  '_highlightResult': {
    'name': {'value': highlighted ?? name, 'matchLevel': 'full'},
  },
};
