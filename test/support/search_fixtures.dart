import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/search_highlight.dart';

import 'algolia_fakes.dart';

// Shared by the search screen tests and their Figma renders.

// The live furniture branch (ids 74–77), a second top-level category, and an
// empty one that is neither a popular tile nor a scope choice.
const kFurnitureUid = 'NzQ=';
const kHomeFurnitureUid = 'NzU=';
const kLivingRoomUid = 'Nzc=';

const List<Category> kSearchTree = <Category>[
  Category(
    uid: kFurnitureUid,
    name: 'Furniture',
    urlKey: 'furniture',
    productCount: 7,
    children: <Category>[
      Category(
        uid: kHomeFurnitureUid,
        name: 'Home Furniture',
        urlKey: 'home-furniture',
        productCount: 5,
      ),
      Category(
        uid: kLivingRoomUid,
        name: 'Living Room Sets',
        urlKey: 'living-room-sets',
        productCount: 3,
      ),
    ],
  ),
  Category(uid: 'MTQw', name: 'Fashion', urlKey: 'fashion', productCount: 19),
  Category(uid: 'OTk=', name: 'Promotions', urlKey: 'promotions'),
];

/// [kSearchTree] as the Arabic store view names it.
const List<Category> kSearchTreeAr = <Category>[
  Category(
    uid: kFurnitureUid,
    name: 'اثاث',
    urlKey: 'furniture',
    productCount: 7,
    children: <Category>[
      Category(
        uid: kHomeFurnitureUid,
        name: 'أثاث منزلي',
        urlKey: 'home-furniture',
        productCount: 5,
      ),
      Category(
        uid: kLivingRoomUid,
        name: 'أطقم غرف المعيشة',
        urlKey: 'living-room-sets',
        productCount: 3,
      ),
    ],
  ),
  Category(uid: 'MTQw', name: 'أزياء', urlKey: 'fashion', productCount: 19),
  Category(uid: 'OTk=', name: 'عروض', urlKey: 'promotions'),
];

// ---------------------------------------------------------------- Algolia

/// The storefront's Algolia answers for "sofa" (records shaped as the live
/// indices serve them, 29 Sep 2026): the first page's products (four named
/// ones, and six more on a full results page), one more on the second page,
/// a matching category and two CMS pages.
Map<String, dynamic> Function(RecordedQuery) sofaAnswers({
  bool products = true,
  bool suggestions = true,
  String store = 'en',
}) => (query) {
  if (query.indexName.endsWith('_categories')) {
    return {
      'hits': [
        if (suggestions)
          {
            'objectID': '77',
            'name': store == 'ar' ? 'أطقم غرف المعيشة' : 'Living Room Sets',
            'level': 3,
            'product_count': 3,
          },
      ],
    };
  }
  if (query.indexName.endsWith('_pages')) {
    return {
      'hits': [
        if (suggestions) ...[
          {
            'objectID': '11',
            'name': store == 'ar' ? 'الشحن والتوصيل' : 'Shipping & delivery',
            'url': 'https://hub-market.magento2.click/$store/shipping-delivery',
          },
          {
            'objectID': '12',
            'name': store == 'ar' ? 'سياسة الإرجاع' : 'Return policy',
            'url': 'https://hub-market.magento2.click/$store/return-policy',
          },
        ],
      ],
    };
  }
  if (!products) return emptyResult();
  final facets = {
    'categoryIds': {'74': 12, '77': 5, '75': 4},
    'mgs_brand': {'MIA': 8},
    'color': {'Grey': 3, 'Teal': 2},
    'seller': {'MIA CO': 8},
  };
  // A count-only search for a filtered facet.
  if (query.params['hitsPerPage'] == '0') {
    return {'hits': <Object>[], 'nbHits': 12, 'facets': facets};
  }
  final page = int.parse(query.params['page'] ?? '0');
  final perPage = int.parse(query.params['hitsPerPage'] ?? '20');
  final ar = store == 'ar';
  return {
    'hits': page == 0
        ? [
            productRecord(
              id: '2096',
              store: store,
              name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
              urlKey: 'sofabed123',
              sku: ['sofabed123', 'sofabed123-grey'],
              type: 'configurable',
              price: 425,
              original: 'AED\u00A0500',
              categoryPaths: ar
                  ? ['اثاث', 'اثاث /// أطقم غرف المعيشة']
                  : ['Furniture', 'Furniture /// Living Room Sets'],
              categoryIds: ['74', '77'],
              highlighted: ar
                  ? [
                      kHighlightPreTag,
                      'كنبة',
                      kHighlightPostTag,
                      ' سرير ركنه',
                    ].join()
                  : 'Corner ${kHighlightPreTag}Sofa$kHighlightPostTag Bed',
            ),
            productRecord(
              id: '2097',
              store: store,
              name: ar ? 'غرفة معيشة 3 قطع' : '3-Piece Living Room Set',
              urlKey: 'living-room-set',
              sku: '3-piece-set',
              price: 255,
              original: 'AED\u00A0300',
              categoryPaths: ar
                  ? ['اثاث', 'اثاث /// أطقم غرف المعيشة']
                  : ['Furniture', 'Furniture /// Living Room Sets'],
              categoryIds: ['74', '77'],
            ),
            productRecord(
              id: '2101',
              store: store,
              name: ar
                  ? 'كرسي طعام بارجل ذهبية معدنية'
                  : 'Dining Chair with Gold Metal Legs',
              urlKey: 'chairs125',
              sku: ['chairs125', 'chairs125-pink'],
              type: 'configurable',
              price: 34,
              original: 'AED\u00A040',
              categoryPaths: ar
                  ? ['اثاث', 'اثاث /// أثاث منزلي']
                  : ['Furniture', 'Furniture /// Home Furniture'],
              categoryIds: ['74', '75'],
            ),
            productRecord(
              id: '2102',
              store: store,
              name: ar ? 'كرسي هزاز عنابي' : 'Burgundy Rocking Chair',
              urlKey: 'chairs126',
              sku: 'chairs126',
              price: 180,
              categoryPaths: ar
                  ? ['اثاث', 'اثاث /// أثاث منزلي']
                  : ['Furniture', 'Furniture /// Home Furniture'],
              categoryIds: ['74', '75'],
            ),
            // A full results page scrolls; the type-ahead asks for fewer.
            if (perPage >= 20)
              for (var i = 1; i <= 6; i++)
                productRecord(
                  id: '230$i',
                  store: store,
                  name: 'Sofa Cushion $i',
                  urlKey: 'sofa-cushion-$i',
                  price: 20 + i,
                ),
          ]
        : [
            productRecord(
              id: '2200',
              store: store,
              name: 'Velvet Sofa',
              urlKey: 'velvet-sofa',
              price: 999,
            ),
          ],
    'nbHits': 12,
    'page': page,
    'nbPages': 2,
    'hitsPerPage': 20,
    'facets': facets,
    'facets_stats': {
      'price.AED.default': {'min': 34, 'max': 999},
    },
  };
};
