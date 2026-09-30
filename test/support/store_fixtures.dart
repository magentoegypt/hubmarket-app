import 'dart:convert';

import 'package:gql/ast.dart';
import 'package:gql/language.dart' show printNode;
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/graphql/possible_types.dart';

import 'search_fixtures.dart';

// The seller API (hmStores / hmStore), a seller's products and hmBestSellers
// as the server answers them — shared by the stores tests and their renders.
//
// Objects read through a fragment carry their `__typename`, as the server's
// answers do (the client adds it to every selection): the cache only fills a
// fragment whose type it can check.

/// One request the fake backend received.
class RecordedRequest {
  const RecordedRequest(this.operation, this.variables, this.document);

  final String operation;
  final Map<String, dynamic> variables;

  /// The document as printed, for asserting inlined values.
  final String document;

  /// The names of the types the document's variables are declared with.
  List<String> get variableTypes => [
    for (final match in RegExp(r'\$\w+\s*:\s*\[?\s*(\w+)').allMatches(document))
      match.group(1)!,
  ];
}

/// A GraphQL client answering every request with [answer]: a `Map` is the
/// `data`, a [Response] is returned as is, an [Exception] fails the request
/// like the network does, and a `Future` of a `Map` answers when it
/// completes. Records what was asked in [requests].
class FakeStoresBackend {
  FakeStoresBackend(this.answer);

  final Object Function(RecordedRequest request) answer;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// The requests for [operation].
  List<RecordedRequest> of(String operation) => [
    for (final r in requests)
      if (r.operation == operation) r,
  ];

  late final GraphQLClient client = GraphQLClient(
    link: Link.function((request, [forward]) {
      final document = request.operation.document;
      final name =
          request.operation.operationName ??
          document.definitions
              .whereType<OperationDefinitionNode>()
              .firstOrNull
              ?.name
              ?.value ??
          '';
      final recorded = RecordedRequest(
        name,
        Map<String, dynamic>.of(request.variables),
        printNode(document),
      );
      requests.add(recorded);
      Response data(Object? json) => Response(
        data: json as Map<String, dynamic>,
        response: const <String, dynamic>{},
      );
      final result = answer(recorded);
      if (result is Response) return Stream.value(result);
      if (result is Exception) return Stream.error(result);
      // A late answer: the test completes it when it wants the data in.
      if (result is Future<Object?>) {
        return Stream.fromFuture(result.then(data));
      }
      return Stream.value(data(result));
    }),
    // Canned data may leave out `__typename`s; the ones a fragment needs are
    // in the fixtures below.
    cache: GraphQLCache(
      partialDataPolicy: PartialDataCachePolicy.accept,
      possibleTypes: kPossibleTypes,
    ),
  );
}

/// `HmStoreCard` JSON. The P3.1 fields (primary category, facet value) are
/// always in the answer; a document that doesn't ask for them never sees
/// them.
Map<String, dynamic> storeCardJson({
  required String code,
  required int id,
  required String name,
  double? rating,
  int reviews = 0,
  int products = 0,
  String? logo,
  Map<String, dynamic>? dispatch,
  bool featured = false,
  String joined = '2023-06-12T08:00:00Z',
  String store = 'en',
  ({int id, String name})? category,
  String? facet,
}) => {
  '__typename': 'HmStoreCard',
  'code': code,
  'vendor_entity_id': id,
  'name': name,
  'logo_url': logo,
  'rating': rating,
  'review_count': reviews,
  'product_count': products,
  'dispatch_time': dispatch,
  'is_featured': featured,
  'joined_at': joined,
  'link': {
    '__typename': 'HmLink',
    'type': 'STORE',
    'url': 'https://hub-market.magento2.click/$store/shop/$code',
    'path': 'shop/$code',
    'uid': null,
    'code': code,
  },
  'primary_category': category == null
      ? null
      : {
          '__typename': 'HmCategoryCount',
          'id': category.id,
          'uid': base64.encode(utf8.encode('${category.id}')),
          'name': category.name,
          'count': products,
        },
  'facet_value': facet ?? name,
};

/// Top-level categories of the fixtures: Figma 12's chips.
({int id, String name}) _category(String key, String store) {
  const names = {
    'furniture': (id: 34, en: 'Furniture', ar: 'أثاث'),
    'fashion': (id: 35, en: 'Fashion', ar: 'أزياء'),
    'lighting': (id: 36, en: 'Lighting', ar: 'إضاءة'),
    'building': (id: 37, en: 'Building Materials', ar: 'مواد البناء'),
    'grocery': (id: 38, en: 'Grocery', ar: 'بقالة'),
  };
  final c = names[key]!;
  return (id: c.id, name: store == 'ar' ? c.ar : c.en);
}

/// The sellers of the Figma frames, in the store view's language.
Map<String, dynamic> miaCard({String store = 'en'}) => storeCardJson(
  code: 'MIA',
  id: 12,
  name: store == 'ar' ? 'ميا كو' : 'MIA CO',
  rating: 4.8,
  reviews: 126,
  products: 38,
  featured: true,
  category: _category('furniture', store),
  dispatch: {
    '__typename': 'HmDispatchTime',
    'code': 'next_day',
    'label': store == 'ar' ? 'اليوم التالي' : 'Next day',
    'source': 'DECLARED',
  },
  store: store,
);

List<Map<String, dynamic>> sampleStoreCards({String store = 'en'}) {
  final ar = store == 'ar';
  return [
    miaCard(store: store),
    storeCardJson(
      code: 'loly',
      id: 7,
      name: ar ? 'متجر لولي' : 'loly store',
      rating: 4.6,
      reviews: 88,
      products: 64,
      store: store,
      category: _category('fashion', store),
    ),
    storeCardJson(
      code: 'ENARA',
      id: 9,
      name: ar ? 'إنارة' : 'ENARA',
      rating: 4.9,
      reviews: 19,
      products: 19,
      store: store,
      category: _category('lighting', store),
    ),
    storeCardJson(
      code: 'future_building',
      id: 21,
      name: ar ? 'المستقبل لمواد البناء' : 'Future Building Materials',
      rating: 4.5,
      reviews: 41,
      products: 22,
      store: store,
      category: _category('building', store),
    ),
    storeCardJson(
      code: 'walmart',
      id: 30,
      name: ar ? 'وول مارت' : 'walmart',
      products: 120,
      store: store,
      category: _category('grocery', store),
    ),
  ];
}

/// `hmStoreCategories` data: Figma 12's chips with their seller counts.
Map<String, dynamic> storeCategoriesData({String store = 'en'}) => {
  'hmStoreCategories': {
    'total_count': 5,
    'items': [
      for (final (key, count) in [
        ('grocery', 1),
        ('furniture', 1),
        ('fashion', 1),
        ('lighting', 1),
        ('building', 1),
      ])
        {
          'id': _category(key, store).id,
          'uid': base64.encode(utf8.encode('${_category(key, store).id}')),
          'name': _category(key, store).name,
          'count': count,
        },
    ],
  },
};

/// `hmStoreReviews` data for MIA CO: the card's rating, two reviews shown in
/// this store view (of three), one about a product the storefront no longer
/// lists.
Map<String, dynamic> miaReviewsData({
  String store = 'en',
  bool none = false,
}) {
  final ar = store == 'ar';
  return {
    'hmStoreReviews': {
      'summary': {'rating': 4.8, 'review_count': 126},
      'total_count': none ? 0 : 2,
      'page_info': {
        'current_page': 1,
        'page_size': 20,
        'total_pages': none ? 0 : 1,
      },
      'items': none
          ? const <Object>[]
          : [
              {
                'id': 41,
                'nickname': ar ? 'سارة' : 'Sara K.',
                'title': ar ? 'كنبة رائعة' : 'Great sofa',
                'text': ar
                    ? 'مريحة ومتينة، ووصلت في موعدها.'
                    : 'Comfortable and well made, delivered on time.',
                'rating': 5.0,
                'created_at': '2026-09-20T08:15:00Z',
                'product': {
                  'name': ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
                  'url_key': 'sofabed123',
                  'thumbnail_url': null,
                },
              },
              {
                'id': 40,
                'nickname': ar ? 'عمر' : 'Omar',
                'title': null,
                'text': ar ? 'جيد مقابل السعر.' : 'Good for the price.',
                'rating': 4.0,
                'created_at': '2026-09-18T10:00:00Z',
                'product': {
                  'name': ar ? 'مصباح قديم' : 'Old Lamp',
                  'url_key': null,
                  'thumbnail_url': null,
                },
              },
            ],
    },
  };
}

/// `hmStores` data.
Map<String, dynamic> storesData(
  List<Map<String, dynamic>> cards, {
  int? total,
  int page = 1,
  int pages = 1,
}) => {
  'hmStores': {
    '__typename': 'HmStorePage',
    'total_count': total ?? cards.length,
    'page_info': {
      '__typename': 'SearchResultPageInfo',
      'current_page': page,
      'page_size': 20,
      'total_pages': pages,
    },
    'items': cards,
  },
};

/// `hmStore` data for MIA CO, with its About text and both policies.
Map<String, dynamic> miaStoreData({String store = 'en', bool policies = true}) {
  final ar = store == 'ar';
  return {
    'hmStore': {
      '__typename': 'HmStore',
      'banner_url': null,
      'short_description': ar
          ? 'أثاث عصري للمنازل والمكاتب'
          : 'Modern furniture for homes and offices',
      'about_html': ar
          ? '<p>تصمم ميا كو وتبيع أثاثًا عصريًا للمنازل والمكاتب — كنب وأطقم غرف معيشة وكراسي طعام ومكاتب، مع التوصيل والتركيب في جميع أنحاء الإمارات.</p>'
          : '<p>MIA CO designs and sells modern furniture for homes and offices — sofas, living-room sets, dining chairs and desks, delivered and assembled across the UAE.</p>',
      'shipping_policy_html': policies
          ? (ar
                ? '<p>التوصيل خلال 72 ساعة في جميع أنحاء الإمارات. التوصيل العادي 10 د.إ، ومجاني فوق 200 د.إ.</p>'
                : '<p>Delivered within 72 hours across the UAE. Standard delivery AED 10, <strong>free over AED 200</strong>.</p>')
          : null,
      'refund_policy_html': policies
          ? (ar
                ? '<p>يمكن إرجاع المنتجات المعيبة أو استبدالها خلال 7 أيام بحالتها الأصلية، دون رسوم شحن إضافية.</p>'
                : '<p>Defective items can be returned or exchanged within 7 days in original condition, with no extra shipping charge. See <a href="https://hub-market.magento2.click/en/return-policy">our return policy</a>.</p>')
          : null,
      // P3.1: only a document with the store page extras reads these.
      'contact': {'phone': '+971 50 123 4567'},
      'location': ar ? 'دبي، الإمارات العربية المتحدة' : 'Dubai, United Arab Emirates',
      'sales_count': 1240,
      'card': miaCard(store: store),
    },
  };
}

/// A listing product as `products` / `hmBestSellers` serve it.
Map<String, dynamic> productJson({
  required String sku,
  required String name,
  required double price,
  double? regular,
  String type = 'SimpleProduct',
  String? seller,
}) => {
  '__typename': type,
  'sku': sku,
  'name': name,
  'url_key': sku,
  'stock_status': 'IN_STOCK',
  'new_from_date': null,
  'new_to_date': null,
  'image': null,
  'price_range': {
    'minimum_price': {
      'regular_price': {'value': regular ?? price, 'currency': 'AED'},
      'final_price': {'value': price, 'currency': 'AED'},
    },
  },
  // Read only by a listing's seller twin (a server that lists vendors).
  'hm_seller': seller == null
      ? null
      : {
          '__typename': 'HmSellerSummary',
          'code': 'MIA',
          'vendor_entity_id': 12,
          'name': seller,
          'logo_url': null,
          'rating': 4.8,
          'review_count': 126,
          'product_count': 38,
          'is_marketplace': false,
          'link': null,
        },
};

/// MIA CO's products (Figma 13).
List<Map<String, dynamic>> miaProducts({String store = 'en'}) {
  final ar = store == 'ar';
  return [
    productJson(
      sku: 'sofabed123',
      name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
      price: 425,
      regular: 500,
      seller: ar ? 'ميا كو' : 'MIA CO',
    ),
    productJson(
      sku: 'living-room-set',
      name: ar ? 'غرفة معيشة 3 قطع' : '3-Piece Living Room Set',
      price: 255,
      regular: 300,
      seller: ar ? 'ميا كو' : 'MIA CO',
    ),
    productJson(
      sku: 'chairs125',
      name: ar
          ? 'كرسي طعام بارجل ذهبية معدنية'
          : 'Dining Chair with Gold Metal Legs',
      price: 34,
      regular: 40,
      seller: ar ? 'ميا كو' : 'MIA CO',
    ),
    productJson(
      sku: 'chairs126',
      name: ar ? 'كرسي هزاز عنابي' : 'Burgundy Rocking Chair',
      price: 180,
      seller: ar ? 'ميا كو' : 'MIA CO',
    ),
  ];
}

/// `products` data with the category facet the About tab reads.
Map<String, dynamic> productsData(
  List<Map<String, dynamic>> items, {
  int? total,
  String store = 'en',
}) {
  final ar = store == 'ar';
  return {
    'products': {
      'total_count': total ?? items.length,
      'page_info': {'current_page': 1, 'total_pages': 1, 'page_size': 20},
      'items': items,
      'aggregations': [
        {
          'attribute_code': 'category_uid',
          'label': ar ? 'الفئة' : 'Category',
          'options': [
            {
              'label': ar ? 'اثاث' : 'Furniture',
              'value': kFurnitureUid,
              'count': 38,
            },
            {
              'label': ar ? 'أثاث منزلي' : 'Home Furniture',
              'value': kHomeFurnitureUid,
              'count': 20,
            },
            {
              'label': ar ? 'أطقم غرف المعيشة' : 'Living Room Sets',
              'value': kLivingRoomUid,
              'count': 8,
            },
          ],
        },
        {
          'attribute_code': 'vendor_id',
          'label': 'Vendor Id',
          'options': [
            {'label': '12', 'value': '12', 'count': 38},
          ],
        },
      ],
    },
  };
}

/// The S2 rail's best sellers.
Map<String, dynamic> bestSellersData({String store = 'en'}) {
  final ar = store == 'ar';
  return {
    'hmBestSellers': {
      'total_count': 3,
      'items': [
        productJson(
          sku: '24-MB04',
          name: ar ? 'حقيبة سفر Joust' : 'Joust Duffle Bag',
          price: 29,
          regular: 34,
        ),
        productJson(
          sku: '24-MB05',
          name: ar ? 'حقيبة كتف Strive' : 'Strive Shoulder Pack',
          price: 32,
        ),
        productJson(
          sku: '24-MB06',
          name: ar ? 'حقيبة ظهر Crown' : 'Crown Summit Backpack',
          price: 38,
        ),
      ],
    },
  };
}
