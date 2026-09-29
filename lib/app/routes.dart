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
  static const String signIn = '/signin';
  static const String signUp = '/signup';
  static const String forgotPassword = '/forgot';
  static const String resetPassword = '/reset-password';
  static const String orders = '/orders';
  static const String orderDetail = '/order-detail';
  static const String orderTracking = '/order-tracking';
  static const String guestTrackOrder = '/track-order';
  static const String myReviews = '/my-reviews';
  static const String addresses = '/addresses';
  static const String addressForm = '/address';
  static const String paymentMethods = '/payment-methods';
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

  static String category(String uid) => '/category/$uid';
  static String subcategories(String uid) => '/subcategories/$uid';
  static String product(String urlKey) => '/product/$urlKey';
  static String review(String sku) => '/review/$sku';
  static String productReviews(String urlKey) => '/reviews/$urlKey';

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
