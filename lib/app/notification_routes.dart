import 'routes.dart';

/// Maps a push-notification data payload to an in-app route, or null if it
/// carries no navigable target. The backend can send either an explicit
/// `route` (a path starting with `/`) or a typed `{ type, id }` pair.
String? notificationRoute(Map<String, dynamic> data) {
  final route = data['route'];
  if (route is String && route.startsWith('/')) return route;

  final type = data['type']?.toString();
  final id = (data['id'] ?? data['value'] ?? data['url_key'])?.toString();
  final hasId = id != null && id.isNotEmpty;

  switch (type) {
    case 'order':
      return AppRoutes.orders;
    case 'product':
      return hasId ? AppRoutes.product(id) : null;
    case 'category':
      return hasId ? AppRoutes.category(id) : null;
    case 'cart':
      return AppRoutes.cart;
    case 'wishlist':
      return AppRoutes.wishlist;
    case 'promo':
    case 'promotion':
    case 'promotions':
      return AppRoutes.home;
    default:
      return null;
  }
}
