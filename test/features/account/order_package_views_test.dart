import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';

import '../../support/marketplace_fakes.dart';
import '../../support/order_package_fixtures.dart';

/// How the order screens lay an order out by package: the server's split
/// first, the lines' sellers next, one list last.

CustomerOrder _copy(
  CustomerOrder order, {
  List<OrderLine>? lines,
  List<OrderPackage>? packages,
}) => CustomerOrder(
  number: order.number,
  status: order.status,
  date: order.date,
  lines: lines ?? order.lines,
  trackings: order.trackings,
  packages: packages ?? order.packages,
);

void main() {
  test('packages take their lines by uid, in the server\'s order', () {
    final views = orderPackageViews(packagedOrder())!;

    expect(views, hasLength(2));
    expect(views.first.seller?.name, 'loly store');
    expect(views.first.package?.statusLabel, 'Processing');
    expect(views.first.lines.map((l) => l.sku), ['DRESS']);
    expect(views.last.lines.map((l) => l.sku), ['SOFA', 'CHAIR']);
  });

  test('a line no package names closes the list in a group of its own', () {
    final order = packagedOrder();
    final extra = OrderLine(
      name: 'Gift wrap',
      quantity: 1,
      sku: 'WRAP',
      uid: 'OTk5',
      seller: seller(null, 'Hub Market', marketplace: true),
    );
    final views = orderPackageViews(
      _copy(order, lines: [...order.lines, extra]),
    )!;

    expect(views, hasLength(3));
    expect(views.last.package, isNull);
    expect(views.last.seller, isNull);
    expect(views.last.lines.single.sku, 'WRAP');
  });

  test('a line two packages name is shown once', () {
    final order = packagedOrder();
    final twice = OrderPackage(
      statusCode: 'complete',
      statusLabel: 'Complete',
      state: 'complete',
      itemUids: const [dressUid],
    );
    final views = orderPackageViews(
      _copy(order, packages: [...order.packages, twice]),
    )!;

    // The third package names only a line already placed: no card for it.
    expect(views, hasLength(2));
    expect(views.expand((v) => v.lines).map((l) => l.sku), [
      'DRESS',
      'SOFA',
      'CHAIR',
    ]);
  });

  test('packages naming none of the lines fall back to the sellers', () {
    final order = packagedOrder();
    final views = orderPackageViews(
      _copy(
        order,
        lines: [
          for (final line in order.lines)
            OrderLine(
              name: line.name,
              quantity: line.quantity,
              sku: line.sku,
              seller: line.seller,
            ),
        ],
      ),
    )!;

    expect(views.map((v) => v.seller?.name), ['loly store', 'MIA CO']);
    expect(views.map((v) => v.package), everyElement(isNull));
  });

  test('without packages or sellers the order is one list', () {
    final order = packagedOrder();
    final plain = _copy(
      order,
      packages: const [],
      lines: [
        for (final line in order.lines)
          OrderLine(name: line.name, quantity: line.quantity, sku: line.sku),
      ],
    );

    expect(orderPackageViews(plain), isNull);
  });

  test('tracking numbers the cards show, and whether one shipped', () {
    final views = orderPackageViews(packagedOrder());

    expect(packagedTrackingNumbers(views), {dhlNumber, aramexNumber});
    expect(anyPackageShipped(views), isTrue);

    final bySeller = orderPackageViews(
      _copy(packagedOrder(), packages: const []),
    );
    expect(packagedTrackingNumbers(bySeller), isEmpty);
    expect(anyPackageShipped(bySeller), isFalse);
    expect(packagedTrackingNumbers(null), isEmpty);
    expect(anyPackageShipped(null), isFalse);
  });
}
