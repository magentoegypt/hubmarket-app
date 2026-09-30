import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/notification_routes.dart';
import 'package:hubmarket_app/app/routes.dart';

void main() {
  group('notificationRoute', () {
    test('honours an explicit route path', () {
      expect(notificationRoute({'route': '/product/coco'}), '/product/coco');
    });

    test('ignores a non-path route value', () {
      expect(notificationRoute({'route': 'not-a-path'}), isNull);
    });

    test('maps typed payloads to routes', () {
      // An order's id is its number: the order itself opens.
      expect(
        notificationRoute({'type': 'order', 'id': '000000123'}),
        AppRoutes.orderByNumber('000000123'),
      );
      expect(AppRoutes.orderByNumber('000000123'), '/orders/000000123');
      expect(notificationRoute({'type': 'order'}), AppRoutes.orders);
      expect(
        notificationRoute({'type': 'product', 'id': 'coco'}),
        AppRoutes.product('coco'),
      );
      expect(
        notificationRoute({'type': 'category', 'id': 'cat-1'}),
        AppRoutes.category('cat-1'),
      );
      expect(notificationRoute({'type': 'cart'}), AppRoutes.cart);
      expect(notificationRoute({'type': 'wishlist'}), AppRoutes.wishlist);
      expect(notificationRoute({'type': 'promo'}), AppRoutes.home);
    });

    test('product/category without an id yields no route', () {
      expect(notificationRoute({'type': 'product'}), isNull);
      expect(notificationRoute({'type': 'category', 'id': ''}), isNull);
    });

    test('unknown / empty payloads yield no route', () {
      expect(notificationRoute({}), isNull);
      expect(notificationRoute({'type': 'mystery'}), isNull);
    });
  });
}
