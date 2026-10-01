import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_route_query.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_subject.dart';

import '../../test/support/fakes.dart';
import '../../test/support/hubapp_fakes.dart';
import '../../test/support/marketplace_fakes.dart';
import '../../test/support/pdp_fixtures.dart';
import '../../test/support/search_fixtures.dart';
import '../../test/support/store_fixtures.dart';

// Fixtures of the stores-and-product scenes (scenes_stores_product.dart) that
// the widget tests keep private inside their own files: copied here, not
// imported, so a test can change without breaking the device audit. The big
// ones (the sellers, the dress, the bundles) are imported from test/support.

/// A token-less public (GET) client that answers nothing: every operation
/// fails like the network does. The audit harness does not fake
/// `publicGraphqlClientProvider`, so a scene whose screen could read it
/// installs this one — a read never leaves the app, on the phone either.
Override offlinePublicClient() => publicClientOverride(const {});

// ---------------------------------------------------------------------------
// Stores (test/features/stores/stores_harness.dart)
// ---------------------------------------------------------------------------

/// The server of the stores screens: the Figma sellers, MIA CO's page and
/// products, the best sellers. A featured-only list is MIA CO alone; a name
/// filters on the name or code, as the backend does.
Object Function(RecordedRequest) storesAnswers({String store = 'en'}) =>
    (request) => switch (request.operation) {
      'HmStores' when request.variables['featured'] == true => storesData([
        miaCard(store: store),
      ]),
      'HmStores' => storesData([
        for (final card in sampleStoreCards(store: store))
          if (_named(card, request.variables['name'] as String?)) card,
      ]),
      'HmStore' => miaStoreData(store: store),
      'HmStoreReviews' => miaReviewsData(store: store),
      'HmStoreCategories' => storeCategoriesData(store: store),
      'Products' => productsData(miaProducts(store: store), store: store),
      'HmBestSellers' => bestSellersData(store: store),
      _ => Exception('offline (device audit): ${request.operation}'),
    };

bool _named(Map<String, dynamic> card, String? name) {
  final needle = name?.trim().toLowerCase() ?? '';
  return needle.isEmpty ||
      (card['name'] as String).toLowerCase().contains(needle) ||
      (card['code'] as String).toLowerCase().contains(needle);
}

/// The stores screens' public client, answering [storesAnswers].
Override storesPublicClient(String locale) => publicGraphqlClientProvider
    .overrideWithValue(FakeStoresBackend(storesAnswers(store: locale)).client);

/// The category tree the About tab names its categories from (the facet's
/// uids are those of [kSearchTree]).
Override storesCatalog(String locale) =>
    catalogRepositoryProvider.overrideWithValue(
      FakeCatalogRepository(
        categories: locale == 'ar' ? kSearchTreeAr : kSearchTree,
      ),
    );

// ---------------------------------------------------------------------------
// Product pages (test/features/marketplace/marketplace_harness.dart)
// ---------------------------------------------------------------------------

Money aed(double amount) => Money(amount: amount, currency: 'AED');

/// Serves one canned [ProductDetail].
class DetailCatalog extends FakeCatalogRepository {
  DetailCatalog(this.detail);
  final ProductDetail detail;

  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async => detail;
}

/// `HmProductMarketplace` as the public client answers it for one product.
Override marketplaceAnswer(Map<String, dynamic> item) =>
    publicGraphqlClientProvider.overrideWithValue(
      fakeHubAppClient({
        'HmProductMarketplace': {
          'products': {
            'items': [item],
          },
        },
      }),
    );

// ---------------------------------------------------------------------------
// "Sold by N other sellers" (test/features/marketplace/other_sellers_test.dart)
// ---------------------------------------------------------------------------

/// An `HmProductOffer` as the backend serves it (the live Joust Duffle Bag
/// family of 30 Sep 2026; test/features/marketplace/product_offers_test.dart).
Map<String, dynamic> offerJson(
  int id,
  String code,
  String name, {
  required double price,
  double? regular,
  String type = 'simple',
  Map<String, dynamic>? dispatch,
  double? rating,
}) => {
  '__typename': 'HmProductOffer',
  'uid': 'uid-$id',
  'sku': 'SKU-$id',
  'url_key': 'offer-$id',
  'type_id': type,
  'seller': sellerJson(code, name, rating: rating),
  'price': {'value': price, 'currency': 'AED'},
  'regular_price': {'value': regular ?? price, 'currency': 'AED'},
  'stock_status': 'IN_STOCK',
  'dispatch_time': dispatch,
};

/// The Joust Duffle Bag family of 30 Sep 2026: the main product sold by
/// test_1 (AED 28.90 after a special price), and two other sellers.
ProductDetail duffleDetail({
  String sku = '24-MB01',
  String urlKey = 'joust-duffle-bag',
}) => ProductDetail(
  sku: sku,
  name: 'Joust Duffle Bag',
  urlKey: urlKey,
  typeId: 'simple',
  regularPrice: aed(34),
  finalPrice: aed(28.9),
  description: 'Big enough to haul a basketball and some sneakers.',
);

/// The main product with its two offers, cheapest first.
Map<String, dynamic> duffleMainItem() => {
  '__typename': 'SimpleProduct',
  'sku': '24-MB01',
  'hm_seller': sellerJson('test_1', 'Test 1', rating: 4.7),
  'hm_offer_count': 2,
  'hm_other_offers': [
    offerJson(
      2287,
      'ENARA',
      'ENARA',
      price: 34,
      rating: 4.4,
      dispatch: {'code': 'days_2_3', 'label': '2-3 days', 'source': 'DECLARED'},
    ),
    offerJson(
      2150,
      'hassan1',
      'Hassan Store',
      price: 40,
      regular: 45,
      dispatch: {
        'code': 'next_day',
        'label': 'Next business day',
        'source': 'DECLARED',
      },
    ),
  ],
};

/// Hassan Store's offer page, read by its URL.
Map<String, dynamic> duffleOfferPage() => {
  '__typename': 'SimpleProduct',
  'sku': 'SKU-2150',
  'hm_seller': sellerJson('hassan1', 'Hassan Store'),
  'hm_offer_count': 2,
  'hm_other_offers': [
    offerJson(1, 'test_1', 'Test 1', price: 28.9, regular: 34),
    offerJson(2287, 'ENARA', 'ENARA', price: 34),
  ],
};

/// The public client: the main product by url_key; an offer, which product
/// search leaves out, only by its URL.
Override dufflePublicClient() => publicGraphqlClientProvider.overrideWithValue(
  RecordingGraphQLClient((request, document) {
    final key = request.variables['urlKey'];
    if (key != null) {
      return {
        'products': {
          'items': [if (key == 'joust-duffle-bag') duffleMainItem()],
        },
      };
    }
    return {
      'route': request.variables['url'] == 'offer-2150.html'
          ? duffleOfferPage()
          : null,
    };
  }).client,
);

/// The catalogue: only the main product is found by url_key.
class DuffleCatalog extends FakeCatalogRepository {
  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async =>
      urlKey == 'joust-duffle-bag' ? duffleDetail() : null;
}

/// Offer pages by URL.
class DuffleRoutes extends ProductRouteRepository {
  DuffleRoutes() : super(fakeGraphQLClient());

  @override
  Future<ProductDetail?> fetchDetail(String url) async =>
      url == 'offer-2150.html'
      ? duffleDetail(sku: 'SKU-2150', urlKey: 'offer-2150')
      : null;
}

// ---------------------------------------------------------------------------
// Added to cart (test/features/cart/added_to_cart_sheet_test.dart)
// ---------------------------------------------------------------------------

/// The cart of Figma 18b: 4 items, AED 543 — what an add lands in the sheet's
/// "Cart subtotal" (test/features/checkout/checkout_harness.dart).
Cart sheetCart(String id) => Cart(
  id: id,
  totalQuantity: 4,
  items: [
    CartItem(
      uid: 'i-sofa',
      sku: 'SOFA',
      name: 'Corner Sofa Bed',
      quantity: 1,
      unitPrice: aed(425),
      rowTotal: aed(425),
      options: const ['Colour: Teal'],
    ),
    CartItem(
      uid: 'i-chair',
      sku: 'CHAIR',
      name: 'Dining Chair with Gold Metal Legs',
      quantity: 2,
      unitPrice: aed(34),
      rowTotal: aed(68),
    ),
    CartItem(
      uid: 'i-dress',
      sku: 'DRESS',
      name: 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      unitPrice: aed(50),
      rowTotal: aed(50),
      options: const ['Size: M'],
    ),
  ],
  totals: CartTotals(subtotal: aed(543), grandTotal: aed(553)),
);

/// Serves [sheetCart], whatever was added.
class SheetCartRepository extends FakeCartRepository {
  @override
  Future<Cart> getCart(String cartId) async => sheetCart(cartId);

  @override
  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    bool throwOnUserError = true,
  }) async => sheetCart(cartId);
}

// ---------------------------------------------------------------------------
// The review form (test/features/catalog/presentation/write_review_screen_test.dart)
// ---------------------------------------------------------------------------

/// The store's rating dimensions — Quality, Value and Price, 1–5 each, as
/// Magento ships them. Nothing is ever sent: `createReview` does nothing.
class ReviewFormCatalog extends FakeCatalogRepository {
  @override
  Future<List<ReviewRatingMetadata>> fetchReviewRatingsMetadata() async => [
    for (final (id, name) in [
      ('quality', 'Quality'),
      ('value', 'Value'),
      ('price', 'Price'),
    ])
      ReviewRatingMetadata(
        id: id,
        name: name,
        values: [
          for (var star = 1; star <= 5; star++)
            ReviewRatingValue(valueId: '${id[0]}-$star', value: star),
        ],
      ),
  ];
}

/// What the product page hands the form: the dress and its store (no photo,
/// see [withBlankPhotos]).
ReviewSubject dressReviewSubject(String locale) {
  final dress = floralDressDetail(locale: locale);
  return ReviewSubject(
    sku: dress.sku,
    name: dress.name,
    sellerName: locale == 'ar' ? 'متجر لولي' : 'loly store',
  );
}

/// The frame's values for the review form: nickname, summary, review.
const Map<String, (String, String, String)> kReviewFormText = {
  'en': (
    'Sara A.',
    'Lovely fabric, true to size',
    'Beautiful print and the tie waist is really flattering. The fabric is '
        'light — perfect for the Dubai heat. Arrived in two days.',
  ),
  'ar': (
    'سارة أ.',
    'قماش جميل ومقاس مضبوط',
    'الطبعة جميلة ورباط الخصر يعطي شكلًا رائعًا. القماش خفيف ومناسب لحرّ '
        'دبي. وصل خلال يومين.',
  ),
};

// ---------------------------------------------------------------------------
// Photos
// ---------------------------------------------------------------------------

/// [detail] with [count] blank photo slots instead of the fixture's catalogue
/// URLs. The gallery's pager and "1 / 4" counter follow the number of photos,
/// so the slots keep them; a blank URL draws the same tinted tile a photo that
/// failed to load does, with no network image in the tree. That matters: the
/// host sweep's capture waits for every network image to load, which never
/// happens in a test, and the phone would ask the live store for files that do
/// not exist. No scene carries a photo URL; real ones could go in here.
ProductDetail withBlankPhotos(ProductDetail detail, {int count = 4}) =>
    ProductDetail(
      sku: detail.sku,
      name: detail.name,
      urlKey: detail.urlKey,
      typeId: detail.typeId,
      brand: detail.brand,
      brandOptionId: detail.brandOptionId,
      description: detail.description,
      shortDescription: detail.shortDescription,
      attributes: detail.attributes,
      gallery: List<String>.filled(count, ''),
      regularPrice: detail.regularPrice,
      finalPrice: detail.finalPrice,
      inStock: detail.inStock,
      badge: detail.badge,
      options: detail.options,
      variants: detail.variants,
      ratingSummary: detail.ratingSummary,
      reviewCount: detail.reviewCount,
      reviews: detail.reviews,
      alsoLike: detail.alsoLike,
      onlyLeft: detail.onlyLeft,
      categories: detail.categories,
    );
