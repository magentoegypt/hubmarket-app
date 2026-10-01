import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';

/// Whether an order is delivered, cancelled or on hold must not depend on the
/// language of the status label: the Arabic store view names them in Arabic.
CustomerOrder _order(String status, [List<OrderPackage> packages = const []]) =>
    CustomerOrder(
      number: '1',
      status: status,
      date: '2026-09-28',
      packages: packages,
    );

OrderPackage _package(String state, [String label = '']) =>
    OrderPackage(statusCode: state, statusLabel: label, state: state);

void main() {
  group('order status without packages (the status label)', () {
    test('English labels', () {
      expect(_order('Complete').isDelivered, isTrue);
      expect(_order('Processing').isDelivered, isFalse);
      expect(_order('Canceled').isCancelled, isTrue);
      expect(_order('Closed').isCancelled, isTrue);
      expect(_order('On Hold').isOnHold, isTrue);
      expect(_order('Pending').isOnHold, isFalse);
    });

    test('Arabic labels', () {
      expect(_order('مكتمل').isDelivered, isTrue);
      expect(_order('تم التوصيل').isDelivered, isTrue);
      expect(_order('قيد التنفيذ').isDelivered, isFalse);
      expect(_order('ملغي').isCancelled, isTrue);
      expect(_order('ملغاة').isCancelled, isTrue);
      expect(_order('قيد التنفيذ').isCancelled, isFalse);
      expect(_order('معلق').isOnHold, isTrue);
    });
  });

  group('order status with the server\'s packages', () {
    test('delivered only when every package is complete', () {
      expect(
        _order('مكتمل', [_package('complete'), _package('complete')]).isDelivered,
        isTrue,
      );
      expect(
        _order('Complete', [_package('complete'), _package('processing')])
            .isDelivered,
        isFalse,
      );
    });

    test('cancelled only when every package is cancelled or closed', () {
      expect(
        _order('x', [_package('canceled'), _package('closed')]).isCancelled,
        isTrue,
      );
      expect(
        _order('Canceled', [_package('canceled'), _package('new')]).isCancelled,
        isFalse,
      );
    });

    test('a state this build does not know leaves it to the label', () {
      final order = _order('Complete', [_package('mystery')]);
      expect(order.isDelivered, isTrue);
    });
  });
}
