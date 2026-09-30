/// Centralised route paths + the primary bottom-nav tabs.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String welcome = '/welcome';
  static const String home = '/home';
  static const String categories = '/categories';
  static const String cart = '/cart';
  static const String wishlist = '/wishlist';
  static const String account = '/account';
  static const String search = '/search';
  static const String brands = '/brands';
  static const String brand = '/brand';

  /// Figma 12 — every approved seller (`hmStores`); Home's store sections and
  /// search's "Browse stores" open it. See [store] for one seller.
  static const String stores = '/stores';
  static const String signIn = '/signin';
  static const String signUp = '/signup';
  static const String forgotPassword = '/forgot';
  static const String resetPassword = '/reset-password';

  /// Figma 05 — carries a `VerifyCodeFlow` in `extra`.
  static const String verifyCode = '/verify-code';
  static const String orders = '/orders';

  /// Carries a `CustomerOrder` in `extra`; without one, `?number=` opens
  /// [orderByNumber].
  static const String orderDetail = '/order-detail';
  static const String orderTracking = '/order-tracking';
  static const String guestTrackOrder = '/track-order';

  /// Returns: My returns (Figma 23b), the return form (23) and one return
  /// (23c, [returnDetail]).
  static const String returns = '/returns';
  static const String returnRequest = '/return-request';
  static const String myReviews = '/my-reviews';
  static const String addresses = '/addresses';
  static const String addressForm = '/address';
  static const String paymentMethods = '/payment-methods';

  /// Figma 20d — store credit balance and transactions (HubAppAccount).
  static const String myCredit = '/my-credit';
  static const String editProfile = '/profile';
  static const String notifications = '/notifications';
  static const String notificationSettings = '/notification-settings';
  static const String help = '/help';
  static const String helpTopic = '/help/topic';
  static const String about = '/about';
  static const String privacyData = '/privacy-data';
  static const String cmsPage = '/page';
  static const String settings = '/settings';
  static const String diagnostics = '/diagnostics';
  static const String webview = '/webview';
  static const String checkout = '/checkout';
  static const String orderSuccess = '/order-success';

  /// Figma 10b — today's deals (`hmDeals`).
  static const String deals = '/deals';

  /// Figma 10c — bundle deals (`hmBundleDeals`).
  static const String bundles = '/bundles';

  /// Best sellers by units ordered (`hmBestSellers`): Home's BEST_SELLERS and
  /// the no-results page's "Popular right now" lead here.
  static const String bestSellers = '/best-sellers';

  static String category(String uid) => '/category/$uid';
  static String subcategories(String uid) => '/subcategories/$uid';
  static String product(String urlKey) => '/product/$urlKey';

  /// Figma 13 — one seller's store page, by seller code: `HmStoreCard.code`,
  /// or `HmLink.code` of a `STORE` link. A `StoreCard` in `extra` paints the
  /// header before the page loads.
  static String store(String code) => '/store/${Uri.encodeComponent(code)}';
  static String review(String sku) => '/review/$sku';
  static String productReviews(String urlKey) => '/reviews/$urlKey';

  /// Figma 10e — one brand's page by its `url_key` (an `HmLink.code` of a
  /// `BRAND` link). A `Brand` in `extra` skips the brand lookup.
  static String brandPage(String urlKey) =>
      '/brand/${Uri.encodeComponent(urlKey)}';

  /// One order by its number (increment id), e.g. `/orders/000000248` — from
  /// a push, a link or Order placed. Under My Orders, so going there leaves
  /// the list beneath (see `OrderLinkScreen`).
  static String orderByNumber(String number) =>
      '$orders/${Uri.encodeComponent(number)}';

  /// Track order (26) with the order number [number] filled in.
  static String guestTrackOrderFor(String number) => Uri(
    path: guestTrackOrder,
    queryParameters: {'number': number},
  ).toString();

  /// The return form opened on order [orderNumber].
  static String returnRequestFor(String orderNumber) => Uri(
    path: returnRequest,
    queryParameters: {'order': orderNumber},
  ).toString();

  static String returnDetail(int id) => '$returns/$id';

  /// A CMS page by its identifier, e.g. `about-us`.
  static String cmsPageById(String identifier, {String? title}) =>
      _cmsPage('id', identifier, title);

  /// A CMS page by its store-relative URL path (see `storePathOf`).
  static String cmsPageByUrl(String path, {String? title}) =>
      _cmsPage('url', path, title);

  static String _cmsPage(String key, String value, String? title) => Uri(
    path: cmsPage,
    queryParameters: {
      key: value,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    },
  ).toString();
}

/// Persistent bottom-navigation destinations.
enum AppTab { home, categories, cart, wishlist, account }

extension AppTabRoute on AppTab {
  String get route => switch (this) {
    AppTab.home => AppRoutes.home,
    AppTab.categories => AppRoutes.categories,
    AppTab.cart => AppRoutes.cart,
    AppTab.wishlist => AppRoutes.wishlist,
    AppTab.account => AppRoutes.account,
  };
}
