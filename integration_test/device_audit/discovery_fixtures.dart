import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/deals/data/deals_repository.dart';
import 'package:hubmarket_app/features/deals/domain/deals.dart';
import 'package:hubmarket_app/features/home/data/home_content_repository.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:intl/intl.dart';

import '../../test/features/stores/stores_harness.dart';
import '../../test/support/algolia_fakes.dart';
import '../../test/support/fakes.dart';
import '../../test/support/search_fixtures.dart';
import '../../test/support/store_fixtures.dart';

// Fixtures of the discovery scenes (scenes_discovery.dart): Home, Categories,
// Search, the listing, Deals, Bundles, Brands. Copied from the widget tests that
// render these frames, which keep theirs private; the shared fakes
// (test/support) are imported as the other scene files do. Images are left out
// everywhere, as in the tests: nothing here touches the network.

// ------------------------------------------------------------------- Home

/// Live CMS markup of the Build 1 blocks (hub-market.magento2.click, 1 Oct
/// 2026): test/features/home/home_audit_test.dart.
const build1Blocks = <String, String>{
  HomeCmsBlocks.deliveryPromise:
      '<p>Free delivery on qualifying orders &middot; Fast nationwide shipping</p>',
  HomeCmsBlocks.promos:
      '<div class="hm-promos">'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/electronics.html/"><span class="hm-promo__icon">⚡</span><span class="hm-promo__kicker">Flash Sale</span><span class="hm-promo__title">Up to 50% Off Electronics &amp; Tech</span><span class="hm-promo__text">Today only</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/super-market.html/"><span class="hm-promo__icon">🌙</span><span class="hm-promo__kicker">Seasonal Offers</span><span class="hm-promo__title">Fresh Grocery Deals</span><span class="hm-promo__text">Same-day delivery &middot; Free over AED 150</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/all.html/"><span class="hm-promo__icon">💳</span><span class="hm-promo__kicker">Buy Now Pay Later</span><span class="hm-promo__title">Split in 4 with Tabby</span><span class="hm-promo__text">0% interest &middot; Instant approval</span></a>'
      '</div>',
  HomeCmsBlocks.trust:
      '<div class="hm-trust">'
      '<div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers</span><span class="hm-trust__text">Verified &amp; approved</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Secure Payments</span><span class="hm-trust__text">Cards, cash on delivery, Tabby &amp; Tamara</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Fast Delivery</span><span class="hm-trust__text">Across all seven emirates</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Easy Returns</span><span class="hm-trust__text">14-day return policy</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">WhatsApp Support</span><span class="hm-trust__text">24/7 customer care</span></div>'
      '</div>',
};

/// The category tree Build 1's "Shop by category" and its rails read.
const build1Categories = <Category>[
  Category(uid: 'Mw==', name: 'Grocery', urlKey: 'super-market', productCount: 7),
  Category(uid: 'NA==', name: 'Pharmacy', urlKey: 'pharmacy', productCount: 8),
  Category(uid: 'NQ==', name: 'Furniture', urlKey: 'furniture', productCount: 7),
  Category(uid: 'Ng==', name: 'Fashion', urlKey: 'clothes', productCount: 19),
  Category(uid: 'Nw==', name: 'FMCG', urlKey: 'fmcg', productCount: 5),
];

Product _homeProduct(String name, double price, [double? was, double? rating]) =>
    Product(
      sku: name,
      name: name,
      urlKey: name.toLowerCase().replaceAll(' ', '-'),
      brand: 'MIA CO',
      regularPrice: Money(amount: was ?? price, currency: 'AED'),
      finalPrice: Money(amount: price, currency: 'AED'),
      ratingSummary: rating == null ? null : rating * 20,
      reviewCount: rating == null ? null : 3,
    );

/// The products of every Build 1 category rail.
final build1Rail = <Product>[
  _homeProduct('Corner Sofa Bed', 425, 500, 4.7),
  _homeProduct('3-Piece Living Room Set', 255, 300),
  _homeProduct('Dining Table Set 6 Seats', 340, 400),
  _homeProduct('Oak Bookshelf', 190, 220),
];

/// An order placed yesterday and still open: Home's active-order card.
CustomerOrder homeOpenOrder() => CustomerOrder(
  number: '000000248',
  status: 'Processing',
  date: DateFormat('yyyy-MM-dd HH:mm:ss').format(
    DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(hours: 12)).subtract(const Duration(days: 1)),
  ),
  id: 'id-248',
  total: const Money(amount: 553, currency: 'AED'),
  lines: const [
    OrderLine(name: 'Line 0', quantity: 1),
    OrderLine(name: 'Line 1', quantity: 1),
  ],
);

/// "YOUR SEARCHES": the customer's own recent searches, newest first, as the
/// local cache holds them.
String homeSearchHistory() =>
    jsonEncode(['bag', 'shirt', 'dress', 'women']);

/// One unread notification, so the Home bell shows its orange dot (Figma 07).
List<NotificationItem> homeUnreadInbox() => [
  NotificationItem(
    id: 'n1',
    kind: NotificationKind.order,
    title: 'Your order shipped',
    body: '',
    receivedAt: DateTime.now(),
  ),
];

/// Wraps a screen to give it the notification inbox [items] while it is
/// mounted: the inbox is a process-wide singleton (`NotificationInbox`), and a
/// device run mounts every scene in one process, so the unread dot must not
/// outlive the Home scene that wants it.
class InboxScope extends StatefulWidget {
  const InboxScope({super.key, required this.items, required this.child});

  final List<NotificationItem> items;
  final Widget child;

  @override
  State<InboxScope> createState() => _InboxScopeState();
}

class _InboxScopeState extends State<InboxScope> {
  @override
  void initState() {
    super.initState();
    NotificationInbox.instance.items.value = widget.items;
  }

  @override
  void dispose() {
    NotificationInbox.instance.items.value = const [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ------------------------------------------------------------ Categories

Category _category(
  int id,
  String key,
  String en,
  String ar, {
  String locale = 'en',
  int count = 20,
  List<Category> children = const <Category>[],
}) => Category(
  uid: categoryUidFromId('$id'),
  name: locale == 'ar' ? ar : en,
  urlKey: key,
  productCount: count,
  children: children,
);

/// The rail of Figma 08: Furniture's branch is the live one (ids 74-77).
List<Category> categoriesTree(String locale) {
  Category c(int id, String key, String en, String ar, {int count = 5}) =>
      _category(id, key, en, ar, locale: locale, count: count);
  return [
    c(12, 'super-market', 'Grocery', 'سوبر ماركت'),
    _category(
      74,
      'furniture',
      'Furniture',
      'أثاث',
      locale: locale,
      count: 214,
      children: [
        c(75, 'home-furniture', 'Home Furniture', 'أثاث منزلي'),
        c(76, 'office-furniture', 'Office Furniture', 'أثاث مكتبي'),
        c(77, 'living-room-sets', 'Living Room Sets', 'أطقم غرف المعيشة'),
        c(78, 'dining-chairs', 'Dining Chairs', 'كراسي طعام'),
        c(79, 'rocking-chairs', 'Rocking Chairs', 'كراسي هزازة'),
      ],
    ),
    c(11, 'pharmacy', 'Pharmacy', 'صيدلية'),
    c(14, 'clothes', 'Fashion', 'أزياء'),
    c(15, 'fmcg', 'FMCG', 'سلع استهلاكية'),
    c(17, 'games', 'Kids & Toys', 'الأطفال والألعاب'),
    c(18, 'health', 'Cosmetics', 'مستحضرات التجميل'),
    c(21, 'electronics', 'Electronics & Tech', 'إلكترونيات وتقنية'),
  ];
}

/// `hmStores` for a category: its two best sellers, of six.
Object Function(RecordedRequest) categoriesStoresAnswer(String locale) =>
    (request) => switch (request.operation) {
      'HmStores' => storesData([
        miaCard(store: locale),
        storeCardJson(
          code: 'ENARA',
          id: 9,
          name: 'ENARA',
          rating: 4.9,
          reviews: 19,
          products: 19,
          store: locale,
        ),
      ], total: 6),
      _ => Exception('offline (device audit): ${request.operation}'),
    };

// ---------------------------------------------------------------- Search

/// [answer] without the product pictures: they would load from the network.
AlgoliaAnswer withoutImages(AlgoliaAnswer answer) => (query) {
  final result = answer(query);
  for (final hit in (result['hits'] as List).cast<Map<String, dynamic>>()) {
    hit
      ..remove('image_url')
      ..remove('thumbnail_url');
  }
  return result;
};

/// [sofaAnswers] with the seller facet MIA CO (as the index names it in the
/// store view's language) and no images.
AlgoliaAnswer searchAnswers(String locale, {bool products = true}) => (query) {
  final result = sofaAnswers(
    store: locale,
    products: products,
    suggestions: products,
  )(query);
  final facets = result['facets'];
  if (facets is Map<String, dynamic>) {
    result['facets'] = {
      ...facets,
      'seller': {locale == 'ar' ? 'ميا كو' : 'MIA CO': 8},
    };
  }
  for (final hit in (result['hits'] as List).cast<Map<String, dynamic>>()) {
    hit
      ..remove('image_url')
      ..remove('thumbnail_url');
  }
  return result;
};

/// The Hub Market App as the search frames show it: trending searches, and a
/// server that lists its satellites (sellers on cards, the store extras).
HubAppState searchHubApp(String locale) => HubAppState.available(
  HmAppConfig(
    storeCode: locale,
    locale: locale == 'ar' ? 'ar_SA' : 'en_US',
    search: HmSearchConfig(
      trendingTerms: locale == 'ar'
          ? const [
              'حقيبة',
              'سامسونج',
              'قميص',
              'فستان',
              'كنبة',
              'أرز',
              'عطور',
              'حليب',
            ]
          : const [
              'bag',
              'Samsung',
              'shirt',
              'dress',
              'sofa',
              'rice',
              'perfume',
              'milk',
            ],
    ),
    features: const {'returns': true, 'store_credit': false},
    capabilities: const {'vendors', 'bundle', 'returns', 'account'},
  ),
);

/// The landing's recent searches (Figma 09b).
List<String> searchRecents(String locale) => locale == 'ar'
    ? const [
        'كنبة سرير',
        'مكتب',
        'حليب جهينة',
        'فستان مزهر',
        'تلفزيون سامسونج',
      ]
    : const [
        'sofa bed',
        'office desk',
        'juhayna milk',
        'floral dress',
        'samsung tv',
      ];

/// The top-level categories of Figma 09b's "Popular categories", with the
/// counts the tiles show ("7+ items").
List<Category> searchPopularTree(String locale) {
  final ar = locale == 'ar';
  Category category(
    int id,
    String key,
    String en,
    String arName,
    int count,
  ) => Category(
    uid: categoryUidFromId('$id'),
    name: ar ? arName : en,
    urlKey: key,
    productCount: count,
  );
  return [
    category(12, 'super-market', 'Grocery', 'سوبر ماركت', 7),
    category(14, 'clothes', 'Fashion', 'أزياء', 19),
    category(74, 'furniture', 'Furniture', 'أثاث', 7),
    category(21, 'electronics', 'Electronics & Tech', 'إلكترونيات وتقنية', 5),
    category(11, 'pharmacy', 'Pharmacy', 'صيدلية', 8),
    category(17, 'games', 'Kids & Toys', 'الأطفال والألعاب', 4),
  ];
}

/// Home's "Shop by category" chips in the admin's order, with the glyph and the
/// pastel slot each category carries: what the landing's tiles reuse.
HmHome searchHomeWithChips(List<Category> tree) {
  const icons = {
    'super-market': ('🛒', 0),
    'clothes': ('👗', 3),
    'furniture': ('🛋️', 2),
    'electronics': ('📱', 7),
    'pharmacy': ('💊', 1),
    'games': ('🧸', 5),
  };
  return HmHome(
    storeCode: 'en',
    sections: [
      HmHomeSection(
        id: 1,
        type: HmSectionType.categoryChips,
        categories: [
          for (var i = 0; i < tree.length; i++)
            HmCategoryChip(
              id: i + 1,
              uid: tree[i].uid,
              name: tree[i].name,
              urlKey: tree[i].urlKey,
              productCount: tree[i].productCount,
              icon: icons[tree[i].urlKey]?.$1,
              tint: icons[tree[i].urlKey]?.$2,
              link: HmLink(
                type: HmLinkType.category,
                url: 'https://hub-market.magento2.click/${tree[i].urlKey}',
                uid: tree[i].uid,
              ),
            ),
        ],
      ),
    ],
  );
}

/// The best sellers of Figma S2's "Popular right now": a seller line and the
/// first card's rating, as the frame draws them.
Map<String, dynamic> searchBestSellers(String locale) {
  final data = bestSellersData(store: locale);
  final items =
      (data['hmBestSellers'] as Map<String, dynamic>)['items']
          as List<Map<String, dynamic>>;
  for (final (i, item) in items.indexed) {
    item['hm_seller'] = {
      '__typename': 'HmSellerSummary',
      'code': 'test1',
      'vendor_entity_id': 5,
      'name': 'Test 1',
      'logo_url': null,
      'rating': null,
      'review_count': 0,
      'product_count': 3,
      'is_marketplace': false,
      'link': null,
    };
    if (i == 0) {
      item['rating_summary'] = 50;
      item['review_count'] = 2;
    }
  }
  return data;
}

/// What the public (GET) client answers on the search pages that list vendors:
/// the best sellers of S2 and the stores of "Browse stores".
FakeStoresBackend searchStoresBackend(String locale) => FakeStoresBackend(
  (request) => request.operation == 'HmBestSellers'
      ? searchBestSellers(locale)
      : storesAnswers(store: locale)(request),
);

// --------------------------------------------------------------- Listing

Product _listingProduct(
  String locale,
  String sku,
  String en,
  String ar,
  double price, {
  double? regular,
  required double stars,
  required int reviews,
}) => Product(
  sku: sku,
  name: locale == 'ar' ? ar : en,
  urlKey: sku,
  regularPrice: Money(amount: regular ?? price, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
  ratingSummary: stars * 20,
  reviewCount: reviews,
  sellerName: locale == 'ar' ? 'ميا كو' : 'MIA CO',
  sellerKnown: true,
);

/// The products of Figma 10.
List<Product> listingProducts(String locale) => [
  _listingProduct(
    locale,
    'corner-sofa',
    'Corner Sofa Bed',
    'كنبة سرير ركنه',
    425,
    regular: 500,
    stars: 4.6,
    reviews: 18,
  ),
  _listingProduct(
    locale,
    'living-set',
    '3-Piece Living Room Set',
    'غرفة معيشة 3 قطع',
    300,
    stars: 4.8,
    reviews: 12,
  ),
  _listingProduct(
    locale,
    'dining-chair',
    'Dining Chair with Gold Metal Legs',
    'كرسي طعام بارجل ذهبية معدنية',
    34,
    regular: 40,
    stars: 4.4,
    reviews: 9,
  ),
  _listingProduct(
    locale,
    'rocking-chair',
    'Burgundy Rocking Chair',
    'كرسي هزاز عنابي',
    180,
    stars: 4.7,
    reviews: 21,
  ),
];

/// The facets of Furniture's listing as the live API serves them: price
/// buckets, the vendor attribute (labels are vendor ids), a size.
List<Aggregation> listingAggregations(String locale) => [
  const Aggregation(
    attributeCode: 'price',
    label: 'Price',
    options: [AggregationOption(label: '0-500', value: '0_500', count: 12)],
  ),
  Aggregation(
    attributeCode: 'category_uid',
    label: 'Category',
    options: [
      AggregationOption(
        label: 'Home Furniture',
        value: kHomeFurnitureUid,
        count: 5,
      ),
    ],
  ),
  const Aggregation(
    attributeCode: 'VENDORID',
    label: 'Vendor ID',
    options: [
      AggregationOption(label: '12', value: '522', count: 8),
      AggregationOption(label: '9', value: '523', count: 3),
      AggregationOption(label: '7', value: '524', count: 2),
      AggregationOption(label: '21', value: '525', count: 2),
    ],
  ),
  Aggregation(
    attributeCode: 'clothes_size',
    label: locale == 'ar' ? 'المقاس' : 'Size',
    options: const [
      AggregationOption(label: 'XS', value: '300', count: 1),
      AggregationOption(label: 'S', value: '301', count: 3),
      AggregationOption(label: 'M', value: '302', count: 5),
      AggregationOption(label: 'L', value: '303', count: 5),
      AggregationOption(label: 'XL', value: '304', count: 2),
    ],
  ),
];

/// The catalogue as the listing's frame has it: twelve products with a store
/// picked, eighteen without.
class FrameCatalog extends FakeCatalogRepository {
  FrameCatalog(this.locale)
    : super(categories: locale == 'ar' ? kSearchTreeAr : kSearchTree);

  final String locale;

  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? brandOptionId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async => ProductPage(
    items: listingProducts(locale),
    totalCount: attributeFilters.isEmpty ? 18 : 12,
    currentPage: currentPage,
    totalPages: 1,
    aggregations: listingAggregations(locale),
  );
}

// ----------------------------------------------------------------- Deals

const dealGrocery = DealCategory(id: 3, uid: 'Mw==', name: 'Grocery', count: 0);
const dealFurniture = DealCategory(
  id: 5,
  uid: 'NQ==',
  name: 'Furniture',
  count: 0,
);

/// A deal as the server ranks it: its product, department and discount.
typedef Deal = ({Product product, DealCategory category, int percent});

Deal _deal(String name, double price, double was, DealCategory category) => (
  product: Product(
    sku: name,
    name: name,
    urlKey: name.toLowerCase().replaceAll(' ', '-'),
    regularPrice: Money(amount: was, currency: 'AED'),
    finalPrice: Money(amount: price, currency: 'AED'),
  ),
  category: category,
  percent: ((was - price) * 100 / was).round(),
);

/// The day's ranking, deepest discount first (29 %, 25 %, 15 %, 10 %, 10 %).
final dealsRanking = <Deal>[
  _deal('Egyptian Rice 1 kg', 25, 35, dealGrocery),
  _deal('Modern Executive Desk', 263, 350, dealFurniture),
  _deal('Corner Sofa Bed', 425, 500, dealFurniture),
  _deal('Dolphin Tuna', 43, 48, dealGrocery),
  _deal('Velvet Armchair', 180, 200, dealFurniture),
];

BundleDeal _bundle(
  String name, {
  int percent = 16,
  String? seller = 'Test 1',
  bool rated = true,
}) => BundleDeal(
  uid: name,
  sku: name,
  name: name,
  urlKey: name.toLowerCase().replaceAll(' ', '-'),
  price: const Money(amount: 61, currency: 'AED'),
  regularTotal: const Money(amount: 72, currency: 'AED'),
  saving: const Money(amount: 11, currency: 'AED'),
  discountPercent: percent,
  itemCount: 4,
  ratingPercent: rated ? 90 : null,
  reviewCount: rated ? 12 : 0,
  seller: seller == null ? null : HmSellerSummary(name: seller),
);

/// The server of hmDeals and hmBundleDeals: filters and sorts the whole
/// ranking, counts the departments of every filter but the category.
class FakeDeals implements DealsRepository {
  FakeDeals({this.perPage = 20});

  final int perPage;

  @override
  Future<DealsPage> fetchDeals({
    int pageSize = 20,
    int currentPage = 1,
    DealsFilters filters = const DealsFilters(),
  }) async {
    final offered = [
      for (final d in dealsRanking)
        if (d.percent >= (filters.minDiscount ?? 0)) d,
    ];
    final matching = [
      for (final d in offered)
        if (filters.categoryId == null || d.category.id == filters.categoryId)
          d,
    ];
    double price(Deal d) => d.product.finalPrice!.amount;
    switch (filters.sort) {
      case DealsSort.priceLowHigh:
        matching.sort((a, b) => price(a).compareTo(price(b)));
      case DealsSort.priceHighLow:
        matching.sort((a, b) => price(b).compareTo(price(a)));
      default:
    }
    final start = (currentPage - 1) * perPage;
    final page = matching.skip(start).take(perPage).toList();
    final counts = <int, int>{};
    for (final d in offered) {
      counts[d.category.id] = (counts[d.category.id] ?? 0) + 1;
    }
    return DealsPage(
      items: [for (final d in page) d.product],
      totalCount: matching.length,
      pageInfo: HmPageInfo(
        currentPage: currentPage,
        pageSize: perPage,
        totalPages: (matching.length / perPage).ceil(),
      ),
      countdownEndsAt: DateTime.now().add(
        const Duration(days: 2, hours: 14, minutes: 32, seconds: 19),
      ),
      categories: counts.length < 2
          ? const <DealCategory>[]
          : [
              for (final c in [dealGrocery, dealFurniture])
                if (counts[c.id] case final count?)
                  DealCategory(
                    id: c.id,
                    uid: c.uid,
                    name: c.name,
                    count: count,
                  ),
            ],
      filtered: true,
    );
  }

  @override
  Future<BundleDealPage> fetchBundleDeals({
    int? categoryId,
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final items = categoryId == 7
        ? [_bundle('Home Fitness Starter Pack')]
        : [
            _bundle('Home Fitness Starter Pack'),
            _bundle(
              'House Tools Set',
              percent: 15,
              seller: 'Future Building Materials',
            ),
          ];
    return BundleDealPage(
      items: items,
      categories: const [
        DealCategory(id: 7, uid: 'Nw==', name: 'Fitness', count: 1),
        DealCategory(id: 13, uid: 'MTM=', name: 'Electronics & Tech', count: 1),
      ],
      maxDiscountPercent: 16,
      sellerCount: 3,
      totalCount: items.length,
    );
  }
}

// ---------------------------------------------------------------- Brands

Brand _brand(
  int id,
  String name, {
  int? option,
  int? products,
  int? sellers,
}) => Brand(
  brandId: id,
  title: name,
  urlKey: name.toLowerCase(),
  url: 'https://hub-market.magento2.click/en/brand/${name.toLowerCase()}.html',
  imageUrl: '',
  optionId: option ?? 200 + id,
  position: id,
  productCount: products,
  sellerCount: sellers,
);

/// As `hmBrands` counts them (Figma 10d).
final brandsList = <Brand>[
  _brand(1, 'Samsung', products: 12, sellers: 2),
  _brand(2, 'HP', products: 2, sellers: 1),
  _brand(3, 'Fresh', products: 2, sellers: 1),
  _brand(4, 'Acer', products: 1, sellers: 1),
  _brand(5, 'Lenovo', products: 1, sellers: 1),
  _brand(6, 'Kodak', products: 0, sellers: 0), // no products: not listed
];

/// Samsung's products, answering the mgs_brand filter like OpenSearch does.
class BrandCatalog extends FakeCatalogRepository {
  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? brandOptionId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final tvsOnly = attributeFilters['category_uid']?.contains('dHY=') ?? false;
    final items = [
      const Product(
        sku: 'tv',
        name: 'Samsung 65-Inch Television',
        urlKey: 'samsung-65',
        regularPrice: Money(amount: 1500, currency: 'AED'),
        finalPrice: Money(amount: 1275, currency: 'AED'),
      ),
      if (!tvsOnly)
        const Product(
          sku: 'a23',
          name: 'Samsung Galaxy A23',
          urlKey: 'galaxy-a23',
          regularPrice: Money(amount: 1200, currency: 'AED'),
          finalPrice: Money(amount: 1200, currency: 'AED'),
        ),
    ];
    return ProductPage(
      items: items,
      totalCount: items.length,
      currentPage: 1,
      totalPages: 1,
      aggregations: const [
        Aggregation(
          attributeCode: 'category_uid',
          label: 'Category',
          options: [
            AggregationOption(label: 'All', value: 'YWxs', count: 2),
            AggregationOption(label: 'Mobiles', value: 'bW9i', count: 1),
            AggregationOption(label: 'TVs', value: 'dHY=', count: 1),
          ],
        ),
      ],
    );
  }
}
