import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/store/store_view.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/domain/customer.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/wishlist/domain/wishlist_entry.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/cms_page.dart';

class FakeLocalCache implements LocalCache {
  FakeLocalCache([this._stores]);
  final List<Map<String, dynamic>>? _stores;
  final Map<String, String> _kv = {};

  @override
  List<Map<String, dynamic>>? readStores() => _stores;

  @override
  Future<void> writeStores(List<Map<String, dynamic>> stores) async {}

  @override
  String? readString(String key) => _kv[key];

  @override
  Future<void> writeString(String key, String value) async => _kv[key] = value;

  @override
  Future<void> deleteKey(String key) async => _kv.remove(key);
}

class FakeLocalePrefs implements LocalePrefs {
  FakeLocalePrefs([this._value]);
  String? _value;

  @override
  String? read() => _value;

  @override
  Future<void> write(String locale) async => _value = locale;
}

class FakeStoreRepository implements StoreRepository {
  FakeStoreRepository(this.stores);
  final List<StoreView> stores;

  @override
  Future<List<StoreView>> fetchAvailableStores() async => stores;
}

class FakeSecureTokenStore implements SecureTokenStore {
  FakeSecureTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

const Customer kSampleCustomer = Customer(
  firstName: 'Layla',
  lastName: 'Hassan',
  email: 'layla@example.com',
);

class FakeCartRepository implements CartRepository {
  Cart _cart = const Cart(id: 'guest-1');
  String? customerCart = 'customer-1';
  int createCalls = 0;
  int mergeCalls = 0;

  @override
  Future<String> createGuestCart() async {
    createCalls++;
    return 'guest-1';
  }

  @override
  Future<String?> customerCartId() async => customerCart;

  @override
  Future<Cart> getCart(String cartId) async => _cart;

  @override
  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    bool throwOnUserError = true,
  }) async {
    _cart = Cart(
      id: cartId,
      items: [
        for (final item in items)
          CartItem(
            uid: 'i-${item['sku']}',
            sku: item['sku'] as String,
            name: item['sku'] as String,
            quantity: (item['quantity'] as int?) ?? 1,
            rowTotal: const Money(amount: 100, currency: 'AED'),
          ),
      ],
    );
    return _cart;
  }

  @override
  Future<Cart> updateItem(String cartId, String uid, int quantity) async {
    _cart = Cart(
      id: cartId,
      items: [
        for (final item in _cart.items)
          if (item.uid == uid)
            CartItem(
              uid: item.uid,
              sku: item.sku,
              name: item.name,
              quantity: quantity,
              rowTotal: item.rowTotal,
            )
          else
            item,
      ],
    );
    return _cart;
  }

  @override
  Future<Cart> removeItem(String cartId, String uid) async {
    _cart = Cart(
      id: cartId,
      items: _cart.items.where((i) => i.uid != uid).toList(),
    );
    return _cart;
  }

  @override
  Future<Cart> applyCoupon(String cartId, String code) async {
    _cart = Cart(
      id: cartId,
      items: _cart.items,
      totals: CartTotals(appliedCoupon: code),
    );
    return _cart;
  }

  @override
  Future<Cart> removeCoupon(String cartId) async {
    _cart = Cart(id: cartId, items: _cart.items);
    return _cart;
  }

  @override
  Future<Cart> mergeCarts(String source, String destination) async {
    mergeCalls++;
    _cart = Cart(id: destination, items: _cart.items);
    return _cart;
  }
}

class FakeCheckoutRepository implements CheckoutRepository {
  FakeCheckoutRepository({
    this.shippingMethods = const <ShippingMethodOption>[
      ShippingMethodOption(
        carrierCode: 'flatrate',
        methodCode: 'flatrate',
        title: 'Flat Rate · Fixed',
        amount: Money(amount: 20, currency: 'AED'),
      ),
    ],
    this.paymentMethods = const <PaymentMethodOption>[
      PaymentMethodOption(code: 'cashondelivery', title: 'Cash on Delivery'),
      PaymentMethodOption(
        code: 'tabby_installments',
        title: 'Tabby — Pay later',
        isOnline: true,
      ),
    ],
    this.grandTotal = const Money(amount: 219, currency: 'AED'),
    this.orderResult = const PlaceOrderResult(orderNumber: '000000123'),
    this.fail = false,
    this.guestOtpVerifyFails = false,
  });

  final List<ShippingMethodOption> shippingMethods;
  final List<PaymentMethodOption> paymentMethods;
  final Money? grandTotal;
  final PlaceOrderResult orderResult;
  final bool fail;
  final bool guestOtpVerifyFails;

  /// Every repository call, in order — `setPaymentMethod:cashondelivery` etc.
  final List<String> calls = [];

  String? guestOtpPhone;
  bool? guestOtpResend;
  String? guestOtpCode;
  String? guestEmail;
  Map<String, dynamic>? lastAddress;
  String? selectedShippingMethod;
  String? selectedPaymentCode;

  /// Emails [hasAccount] reports as belonging to a customer.
  Set<String> registeredEmails = {};

  @override
  Future<bool> hasAccount(String email) async {
    calls.add('hasAccount');
    return registeredEmails.contains(email);
  }

  @override
  Future<void> setGuestEmail(String cartId, String email) async {
    calls.add('setGuestEmail');
    if (fail) throw const Failure(FailureKind.unknown);
    guestEmail = email;
  }

  @override
  Future<List<ShippingMethodOption>> setShippingAddress(
    String cartId,
    Map<String, dynamic> address,
  ) async {
    calls.add('setShippingAddress');
    if (fail) throw const Failure(FailureKind.unknown);
    lastAddress = address;
    return shippingMethods;
  }

  @override
  Future<Money?> setShippingMethod(
    String cartId,
    String carrier,
    String method,
  ) async {
    calls.add('setShippingMethod:$carrier|$method');
    if (fail) throw const Failure(FailureKind.unknown);
    selectedShippingMethod = '$carrier|$method';
    return grandTotal;
  }

  @override
  Future<List<PaymentMethodOption>> setBillingSameAsShipping(
    String cartId,
  ) async {
    calls.add('setBillingSameAsShipping');
    if (fail) throw const Failure(FailureKind.unknown);
    return paymentMethods;
  }

  @override
  Future<void> setPaymentMethod(String cartId, String code) async {
    calls.add('setPaymentMethod:$code');
    if (fail) throw const Failure(FailureKind.unknown);
    selectedPaymentCode = code;
  }

  @override
  Future<void> requestGuestCheckoutOtp(
    String mobile, {
    bool resend = false,
  }) async {
    calls.add('requestGuestCheckoutOtp');
    if (fail) throw const Failure(FailureKind.unknown);
    guestOtpPhone = mobile;
    guestOtpResend = resend;
  }

  @override
  Future<void> verifyGuestCheckoutOtp(String mobile, String code) async {
    calls.add('verifyGuestCheckoutOtp');
    if (guestOtpVerifyFails) {
      throw const Failure(
        FailureKind.server,
        detail: 'The OTP code is not valid.',
      );
    }
    guestOtpPhone = mobile;
    guestOtpCode = code;
  }

  @override
  Future<PlaceOrderResult> placeOrder(String cartId) async {
    calls.add('placeOrder');
    if (fail) throw const Failure(FailureKind.unknown);
    return orderResult;
  }
}

class FakeWishlistRepository implements WishlistRepository {
  WishlistData _data = const WishlistData(id: 'wl-1');

  @override
  Future<WishlistData?> fetchWishlist() async => _data;

  @override
  Future<WishlistData> addProduct(String wishlistId, String sku) async {
    _data = WishlistData(
      id: wishlistId,
      entries: [
        ..._data.entries,
        WishlistEntry(
          id: 'item-$sku',
          product: Product(sku: sku, name: sku, urlKey: sku),
        ),
      ],
    );
    return _data;
  }

  @override
  Future<WishlistData> removeItem(String wishlistId, String itemId) async {
    _data = WishlistData(
      id: wishlistId,
      entries: _data.entries.where((e) => e.id != itemId).toList(),
    );
    return _data;
  }

  @override
  Future<WishlistData> removeItems(
    String wishlistId,
    List<String> itemIds,
  ) async {
    _data = WishlistData(
      id: wishlistId,
      entries: _data.entries.where((e) => !itemIds.contains(e.id)).toList(),
    );
    return _data;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.loginFails = false,
    this.otpLoginFails = false,
    this.registrationOtpFails = false,
    this.customer = kSampleCustomer,
  });

  final bool loginFails;
  final bool otpLoginFails;
  final bool registrationOtpFails;
  final Customer customer;

  // Recorded inputs for assertions.
  String? lastMobileNumber;
  String? lastOtpPhone;
  String? lastOtpCode;
  bool? lastOtpResend;
  String? lastResetPassword;

  @override
  Future<String> login(String email, String password) async {
    if (loginFails) throw const Failure(FailureKind.auth);
    return 'fake-token';
  }

  @override
  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? mobileNumber,
  }) async {
    lastMobileNumber = mobileNumber;
  }

  @override
  Future<void> revokeToken() async {}

  /// Set to make [deleteAccount] throw, so tests can cover the path where the
  /// server refuses and the customer must stay signed in.
  bool deleteAccountFails = false;
  bool deleteAccountCalled = false;

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
    if (deleteAccountFails) throw const Failure(FailureKind.unknown);
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<Customer> fetchCustomer() async => customer;

  // --- WhatsApp OTP ---
  @override
  Future<void> requestLoginOtp(String phone) async => lastOtpPhone = phone;

  @override
  Future<String> loginWithOtp(String phone, String code) async {
    if (otpLoginFails) throw const Failure(FailureKind.auth);
    lastOtpPhone = phone;
    lastOtpCode = code;
    return 'fake-token';
  }

  @override
  Future<void> requestRegistrationOtp(
    String phone, {
    bool resend = false,
  }) async {
    lastOtpPhone = phone;
    lastOtpResend = resend;
  }

  @override
  Future<void> verifyRegistrationOtp(String phone, String code) async {
    if (registrationOtpFails) {
      throw const Failure(
        FailureKind.server,
        detail: 'The verification code is incorrect.',
      );
    }
    lastOtpPhone = phone;
    lastOtpCode = code;
  }

  @override
  Future<void> requestPasswordResetOtp(
    String phone, {
    bool resend = false,
  }) async {
    lastOtpPhone = phone;
    lastOtpResend = resend;
  }

  @override
  Future<void> resetPasswordWithOtp({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    lastOtpPhone = phone;
    lastOtpCode = code;
    lastResetPassword = newPassword;
  }
}

class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    this.categories = kSampleCategories,
    this.products = kSampleProducts,
    this.aggregations = kSampleAggregations,
    this.categoryThumbnails = const <String, String>{},
    this.resolved,
  });

  final List<Category> categories;
  final List<Product> products;
  final List<Aggregation> aggregations;

  /// Canned product stand-ins for categories with no image of their own.
  final Map<String, String> categoryThumbnails;

  /// Canned `urlResolver` answer for [resolveUrl]; null means unresolvable.
  final ({String type, String uid, String? urlKey})? resolved;

  /// The last URL [resolveUrl] was asked about.
  String? resolvedUrl;

  @override
  Future<List<Category>> fetchCategoryTree() async => categories;

  @override
  Future<Map<String, String>> fetchCategoryThumbnails(
    List<String> categoryUids,
  ) async => categoryThumbnails;

  @override
  Future<({String type, String uid, String? urlKey})?> resolveUrl(
    String storeUrl,
  ) async {
    resolvedUrl = storeUrl;
    return resolved;
  }

  @override
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
  }) async => ProductPage(
    items: products,
    totalCount: products.length,
    currentPage: currentPage,
    totalPages: 1,
    aggregations: aggregations,
  );

  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async =>
      kSampleDetail;

  @override
  Future<List<ReviewRatingMetadata>> fetchReviewRatingsMetadata() async =>
      const [];

  @override
  Future<void> createReview({
    required String sku,
    required String nickname,
    required String summary,
    required String text,
    required List<({String id, String valueId})> ratings,
  }) async {}
}

/// Reviews served in real pages: [productReviews] and [customerReviews] are
/// sliced by the requested page size, like Magento does.
class FakeReviewsRepository implements ReviewsRepository {
  FakeReviewsRepository({
    this.productReviews = const <ProductReview>[],
    this.reviewCount,
    this.ratingSummary = 80,
    this.customerReviews = const <CustomerReview>[],
    this.productExists = true,
  });

  final List<ProductReview> productReviews;

  /// `review_count`; defaults to the number of [productReviews].
  final int? reviewCount;
  final int ratingSummary;
  final List<CustomerReview> customerReviews;
  final bool productExists;

  final List<int> productPagesRequested = <int>[];
  final List<int> customerPagesRequested = <int>[];

  @override
  Future<ProductReviewsPage?> fetchProductReviews(
    String urlKey, {
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    productPagesRequested.add(currentPage);
    if (!productExists) return null;
    return ProductReviewsPage(
      sku: 'SKU-$urlKey',
      name: 'Product $urlKey',
      urlKey: urlKey,
      ratingSummary: ratingSummary,
      reviewCount: reviewCount ?? productReviews.length,
      reviews: _page(productReviews, pageSize, currentPage),
      currentPage: currentPage,
      totalPages: (productReviews.length / pageSize).ceil(),
    );
  }

  @override
  Future<CustomerReviewsPage> fetchCustomerReviews({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    customerPagesRequested.add(currentPage);
    return CustomerReviewsPage(
      items: _page(customerReviews, pageSize, currentPage),
      currentPage: currentPage,
      totalPages: (customerReviews.length / pageSize).ceil(),
    );
  }

  static List<T> _page<T>(List<T> all, int size, int page) =>
      all.skip((page - 1) * size).take(size).toList();
}

/// A published review with [stars] (1–5).
ProductReview sampleReview(int stars, {String nickname = 'Nour A.'}) =>
    ProductReview(
      nickname: nickname,
      summary: 'Lovely fabric',
      text: 'The fit is true to size.',
      averageRating: stars * 20,
      date: '2026-09-12 10:24:33',
    );

/// Account data for the order-cancellation, newsletter and contact-form flows.
/// Records every write so tests can assert the exact call; reads not listed
/// here are unexpected and throw.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    this.orders = const <CustomerOrder>[],
    this.cancelledOrder,
    this.cancelError,
    this.newsletterSubscribed = false,
    this.newsletterNeedsConfirmation = false,
    this.contactFails = false,
  });

  final List<CustomerOrder> orders;

  /// What `cancelOrder` returns; null mimics a payload without the order.
  final CustomerOrder? cancelledOrder;

  /// When set, both cancel calls fail with this store message, as Magento
  /// reports a refusal in `errorV2`.
  final String? cancelError;

  bool newsletterSubscribed;

  /// "Need to Confirm" on: a new subscription saves as not yet subscribed.
  final bool newsletterNeedsConfirmation;
  final bool contactFails;

  final List<({String orderId, String reason})> cancelCalls = [];
  final List<({String token, String reason})> guestCancelCalls = [];
  final List<bool> newsletterCalls = <bool>[];
  final List<Map<String, String?>> contactMessages = [];

  @override
  Future<OrderPage> fetchOrders({int pageSize = 10, int currentPage = 1}) async =>
      OrderPage(
        items: orders,
        currentPage: 1,
        totalPages: 1,
        totalCount: orders.length,
      );

  @override
  Future<CustomerOrder?> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    cancelCalls.add((orderId: orderId, reason: reason));
    if (cancelError != null) {
      throw Failure(FailureKind.server, detail: cancelError);
    }
    return cancelledOrder;
  }

  @override
  Future<void> requestGuestOrderCancel({
    required String token,
    required String reason,
  }) async {
    guestCancelCalls.add((token: token, reason: reason));
    if (cancelError != null) {
      throw Failure(FailureKind.server, detail: cancelError);
    }
  }

  @override
  Future<bool> fetchNewsletterSubscription() async => newsletterSubscribed;

  @override
  Future<bool> setNewsletterSubscription(bool subscribed) async {
    newsletterCalls.add(subscribed);
    newsletterSubscribed = subscribed && !newsletterNeedsConfirmation;
    return newsletterSubscribed;
  }

  @override
  Future<void> sendContactMessage({
    required String name,
    required String email,
    required String comment,
    String? telephone,
  }) async {
    if (contactFails) throw const Failure(FailureKind.network);
    contactMessages.add({
      'name': name,
      'email': email,
      'telephone': telephone,
      'comment': comment,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// CMS content by page identifier, by URL path and by block identifier.
class FakeCmsRepository implements CmsRepository {
  FakeCmsRepository({
    this.pages = const <String, CmsPage>{},
    this.pagesByUrl = const <String, CmsPage>{},
    this.blocks = const <String, String>{},
  });

  final Map<String, CmsPage> pages;
  final Map<String, CmsPage> pagesByUrl;
  final Map<String, String> blocks;

  final List<String> requestedUrls = <String>[];

  @override
  Future<CmsPage?> fetchPage(String identifier) async => pages[identifier];

  @override
  Future<CmsPage?> fetchPageByUrl(String url) async {
    requestedUrls.add(url);
    return pagesByUrl[url];
  }

  @override
  Future<String?> fetchBlock(String identifier) async => blocks[identifier];
}

/// The live `hm_footer_legal` block (store `en`, 29 Sep 2026).
const String kLegalLinksBlock =
    '<ul><li><a href="https://hub-market.magento2.click/en/privacy-policy-cookie-restriction-mode/">Privacy</a></li>'
    '<li><a href="https://hub-market.magento2.click/en/customer-service/">Terms</a></li>'
    '<li><a href="https://hub-market.magento2.click/en/enable-cookies/">Cookies</a></li></ul>';

const List<StoreView> kSampleStores = <StoreView>[
  StoreView(
    storeCode: 'eg_en',
    storeName: 'EN',
    locale: 'en_US',
    isDefault: true,
    baseCurrencyCode: 'AED',
    displayCurrencyCode: 'AED',
    baseUrl: 'https://hub-market.magento2.click/',
    secureBaseUrl: 'https://hub-market.magento2.click/',
    baseMediaUrl: 'https://hub-market.magento2.click/media/',
    baseLinkUrl: 'https://hub-market.magento2.click/uae-en/',
  ),
  StoreView(
    storeCode: 'eg_ar',
    storeName: 'AR',
    locale: 'ar_SA',
    isDefault: false,
    baseCurrencyCode: 'AED',
    displayCurrencyCode: 'AED',
    baseUrl: 'https://hub-market.magento2.click/',
    secureBaseUrl: 'https://hub-market.magento2.click/',
    baseMediaUrl: 'https://hub-market.magento2.click/media/',
    baseLinkUrl: 'https://hub-market.magento2.click/uae-ar/',
  ),
];

const List<Category> kSampleCategories = <Category>[
  Category(uid: 'cat-fragrance', name: 'Fragrance', urlKey: 'fragrance'),
  Category(uid: 'cat-makeup', name: 'Makeup', urlKey: 'makeup'),
  Category(uid: 'cat-new', name: 'New Arrivals', urlKey: 'new-arrivals'),
  Category(uid: 'cat-best', name: 'Bestsellers', urlKey: 'bestsellers'),
];

// imageUrl is null so widget tests don't hit the network via CachedNetworkImage.
const List<Product> kSampleProducts = <Product>[
  Product(
    sku: 'CHANEL-COCO',
    name: 'Coco Mademoiselle EDP',
    urlKey: 'coco-mademoiselle',
    brand: 'Chanel',
    regularPrice: Money(amount: 250, currency: 'AED'),
    finalPrice: Money(amount: 199, currency: 'AED'),
  ),
  Product(
    sku: 'DIOR-SAUVAGE',
    name: 'Sauvage EDT',
    urlKey: 'sauvage',
    brand: 'Dior',
    regularPrice: Money(amount: 300, currency: 'AED'),
    finalPrice: Money(amount: 300, currency: 'AED'),
  ),
];

const ProductDetail kSampleDetail = ProductDetail(
  sku: 'CHANEL-COCO',
  name: 'Coco Mademoiselle EDP',
  urlKey: 'coco-mademoiselle',
  brand: 'Chanel',
  description: 'A vibrant oriental fragrance.',
  regularPrice: Money(amount: 250, currency: 'AED'),
  finalPrice: Money(amount: 199, currency: 'AED'),
  options: <ConfigurableOption>[
    ConfigurableOption(
      attributeCode: 'size',
      label: 'Size',
      values: <SwatchValue>[
        SwatchValue(valueIndex: 1, label: '50ml'),
        SwatchValue(valueIndex: 2, label: '100ml'),
      ],
    ),
  ],
  variants: <ProductVariant>[
    ProductVariant(
      sku: 'COCO-50',
      attributes: {'size': 1},
      price: Money(amount: 199, currency: 'AED'),
    ),
    ProductVariant(
      sku: 'COCO-100',
      attributes: {'size': 2},
      price: Money(amount: 299, currency: 'AED'),
    ),
  ],
);

const List<Aggregation> kSampleAggregations = <Aggregation>[
  Aggregation(
    attributeCode: 'brand',
    label: 'Brand',
    options: <AggregationOption>[
      AggregationOption(label: 'Chanel', value: '101', count: 4),
      AggregationOption(label: 'Dior', value: '102', count: 3),
    ],
  ),
];

/// A [GraphQLClient] whose every request fails immediately — no network, no
/// retry-backoff. Mounting a screen that fires storeConfig / footer / hero /
/// brands queries then degrades to fallbacks without leaving a pending retry
/// timer in the widget test. Override via `graphqlClientProvider`.
GraphQLClient fakeGraphQLClient() => GraphQLClient(
  link: Link.function(
    (request, [forward]) =>
        Stream<Response>.error(Exception('offline (test)')),
  ),
  cache: GraphQLCache(),
);

/// Brands as the live `brands` feed serves them: mixed-case `url_key` that is
/// exactly the `shopbrand/<key>.html` path segment, and a non-null `option_id`
/// (every one of the 310 live brands has one). `Bath & Body Works` is the case
/// where the display title and the key differ.
const List<Brand> kSampleBrands = <Brand>[
  Brand(
    brandId: 114,
    title: 'Mancera',
    urlKey: 'Mancera',
    url: 'https://hub-market.magento2.click/uae-en/shopbrand/Mancera.html',
    imageUrl: 'https://hub-market.magento2.click/media/brand/mancera.png',
    optionId: 126,
    position: 0,
  ),
  Brand(
    brandId: 104,
    title: 'Bath & Body Works',
    urlKey: 'BathBodyWorks',
    url: 'https://hub-market.magento2.click/uae-en/shopbrand/BathBodyWorks.html',
    imageUrl: 'https://hub-market.magento2.click/media/brand/bbw.png',
    optionId: 110,
    position: 0,
  ),
  Brand(
    brandId: 146,
    title: 'ANUA',
    urlKey: 'ANUA',
    url: 'https://hub-market.magento2.click/uae-en/shopbrand/ANUA.html',
    imageUrl: 'https://hub-market.magento2.click/media/brand/anua.png',
    optionId: 158,
    position: 0,
  ),
];
