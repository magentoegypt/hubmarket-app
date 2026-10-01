import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/features/account/data/account_queries.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/marketplace_fakes.dart';
import '../../support/order_package_fixtures.dart';

/// `CustomerOrder.hm_packages` (HubAppOrders): asked for only while the server
/// serves it, dropped on its own when it doesn't, and read into packages.

Map<String, dynamic> _orders(Map<String, dynamic> order) => {
  'customer': {
    '__typename': 'Customer',
    'orders': {
      '__typename': 'CustomerOrders',
      'total_count': 1,
      'page_info': {'current_page': 1, 'total_pages': 1},
      'items': [order],
    },
  },
};

/// [order] as a server without some HubApp fields answers: those left out.
Map<String, dynamic> _without(
  Map<String, dynamic> order, {
  bool packages = false,
  bool sellers = false,
}) => {
  for (final entry in order.entries)
    if (!(packages && entry.key == 'hm_packages')) entry.key: entry.value,
  if (sellers)
    'items': [
      for (final item in order['items'] as List)
        {
          for (final entry in (item as Map<String, dynamic>).entries)
            if (entry.key != 'hm_seller') entry.key: entry.value,
        },
    ],
};

Response _refusal(List<String> fields) => Response(
  errors: [
    for (final field in fields)
      GraphQLError(
        message:
            'Cannot query field "$field" on type "'
            '${field == 'hm_seller' ? 'OrderItemInterface' : 'CustomerOrder'}".',
      ),
  ],
  response: const <String, dynamic>{},
);

void main() {
  test('order documents ask for no HubApp field today; the twin adds both', () {
    for (final document in [
      AccountQueries.orders,
      AccountQueries.orderByNumber,
      AccountQueries.recentOrders,
      AccountQueries.guestOrderByToken,
      AccountQueries.guestOrder,
      AccountQueries.cancelOrder,
    ]) {
      expect(document, isNot(contains('hm_')));
      expect(
        AccountQueries.withHubApp(document, sellers: false, packages: false),
        document,
      );
      final twin = AccountQueries.withHubApp(
        document,
        sellers: true,
        packages: true,
      );
      expect(twin, contains('...HmOrderSellers'));
      expect(twin, contains('...HmOrderPackages'));
      final ast = parseString(twin);
      expect(
        ast.definitions.whereType<OperationDefinitionNode>(),
        hasLength(1),
      );
      final fragments = [
        for (final f in ast.definitions.whereType<FragmentDefinitionNode>())
          f.name.value,
      ];
      // Each fragment once, although both twins need the seller fields.
      expect(fragments.toSet(), hasLength(fragments.length));
      expect(
        fragments,
        containsAll([
          'OrderFields',
          'HmOrderSellers',
          'HmOrderPackages',
          'HmSellerFields',
          'HmLinkFields',
        ]),
      );

      final packagesOnly = AccountQueries.withHubApp(
        document,
        sellers: false,
        packages: true,
      );
      expect(packagesOnly, contains('hm_packages'));
      expect(packagesOnly, isNot(contains('...HmOrderSellers')));
    }
  });

  test('with HubApp the order comes split by store', () async {
    final server = RecordingGraphQLClient(
      (_, __) => _orders(packagedOrderJson()),
    );
    final page = await AccountRepository(
      server.client,
      marketplace: RecordingMarketplaceGate(),
    ).fetchOrders();

    expect(server.documents.single, contains('hm_packages'));
    expect(server.documents.single, contains('hm_seller'));
    final order = page.items.single;
    expect(order.lines.map((l) => l.uid), [dressUid, sofaUid, chairUid]);
    expect(order.packages, hasLength(2));

    final loly = order.packages.first;
    expect(loly.seller?.name, 'loly store');
    expect(loly.statusLabel, 'Processing');
    expect(loly.stage, OrderPackageStage.processing);
    expect(loly.itemUids, [dressUid]);
    expect(loly.subtotal?.amount, 50);
    expect(loly.discount, isNull);
    expect(loly.shippingAmount, isNull);
    expect(loly.grandTotal?.formatted(), 'AED 50');
    final shipment = loly.shipments.single;
    expect(shipment.number, '000000031');
    expect(shipment.createdAt, DateTime.utc(2026, 9, 29, 6, 10));
    expect(shipment.tracks.map((t) => t.number), [dhlNumber, aramexNumber]);
    expect(shipment.tracks.first.trackingUrl, Uri.parse(dhlUrl));
    expect(shipment.tracks.last.trackingUrl, isNull);
    expect(shipment.tracks.last.carrierTitle, 'Aramex');
    expect(loly.comments.single.message, 'Packed and handed to DHL.');

    final mia = order.packages.last;
    expect(mia.stage, OrderPackageStage.pending);
    expect(mia.itemUids, [sofaUid, chairUid]);
    expect(mia.discount?.amount, 25);
    expect(mia.grandTotal?.amount, 468);
    expect(mia.shipments, isEmpty);
  });

  test('a server without hm_packages still gets the sellers', () async {
    final server = RecordingGraphQLClient(
      (_, document) => document.contains('hm_packages')
          ? _refusal(['hm_packages'])
          : _orders(_without(packagedOrderJson(), packages: true)),
    );
    final gate = RecordingMarketplaceGate();
    final page = await AccountRepository(
      server.client,
      marketplace: gate,
    ).fetchOrders();

    expect(gate.packagesMissingCalls, 1);
    expect(gate.sellersMissingCalls, 0);
    expect(server.documents, hasLength(2));
    expect(server.documents.last, isNot(contains('hm_packages')));
    expect(server.documents.last, contains('hm_seller'));
    final order = page.items.single;
    expect(order.packages, isEmpty);
    expect(order.lines.map((l) => l.seller?.name), [
      'loly store',
      'MIA CO',
      'MIA CO',
    ]);

    // The gate stops asking: the next order read goes without packages.
    await AccountRepository(server.client, marketplace: gate).fetchOrders();
    expect(server.documents, hasLength(3));
    expect(server.documents.last, isNot(contains('hm_packages')));
  });

  test('a server without hm_seller still gets the packages', () async {
    final server = RecordingGraphQLClient(
      (_, document) => document.contains('hm_seller')
          ? _refusal(['hm_seller'])
          : _orders(_without(packagedOrderJson(), sellers: true)),
    );
    final gate = RecordingMarketplaceGate();
    final page = await AccountRepository(
      server.client,
      marketplace: gate,
    ).fetchOrders();

    expect(gate.sellersMissingCalls, 1);
    expect(gate.packagesMissingCalls, 0);
    expect(server.documents.last, contains('hm_packages'));
    expect(page.items.single.packages, hasLength(2));
  });

  test('a server without either gets today\'s document', () async {
    final server = RecordingGraphQLClient(
      (_, document) =>
          document.contains('hm_packages') || document.contains('hm_seller')
          ? _refusal([
              if (document.contains('hm_seller')) 'hm_seller',
              if (document.contains('hm_packages')) 'hm_packages',
            ])
          : _orders(_without(packagedOrderJson(), packages: true, sellers: true)),
    );
    final gate = RecordingMarketplaceGate();
    final page = await AccountRepository(
      server.client,
      marketplace: gate,
    ).fetchOrders();

    expect(gate.sellersMissingCalls, 1);
    expect(gate.packagesMissingCalls, 1);
    expect(server.documents, hasLength(2));
    expect(server.documents.last, isNot(contains('hm_')));
    expect(page.items.single.lines, hasLength(3));
  });

  test('a refusal naming neither field drops both rather than guess', () async {
    final server = RecordingGraphQLClient(
      (_, document) => document.contains('hm_')
          ? Response(
              errors: const [
                GraphQLError(message: 'Unknown type "HmSomethingElse".'),
              ],
              response: const <String, dynamic>{},
            )
          : _orders(_without(packagedOrderJson(), packages: true, sellers: true)),
    );
    final gate = RecordingMarketplaceGate();
    await AccountRepository(server.client, marketplace: gate).fetchOrders();

    expect(gate.sellersMissingCalls, 1);
    expect(gate.packagesMissingCalls, 1);
    expect(server.documents, hasLength(2));
  });

  test('without HubApp nothing of it is asked for', () async {
    final server = RecordingGraphQLClient(
      (_, __) => _orders(_without(packagedOrderJson(), packages: true, sellers: true)),
    );
    final page = await AccountRepository(
      server.client,
      marketplace: const FixedMarketplaceGate(),
    ).fetchOrders();

    expect(server.documents.single, isNot(contains('hm_')));
    expect(page.items.single.packages, isEmpty);
    expect(page.items.single.lines.map((l) => l.uid), everyElement(isNull));
  });

  test('a guest order by token carries its packages', () async {
    final server = RecordingGraphQLClient(
      (_, __) => {'guestOrderByToken': packagedOrderJson()},
    );
    final order = await AccountRepository(
      server.client,
      marketplace: RecordingMarketplaceGate(),
    ).fetchGuestOrderByToken('token-1');

    expect(server.documents.single, contains('hm_packages'));
    expect(order.placedAsGuest, isTrue);
    expect(order.packages.map((p) => p.seller?.name), ['loly store', 'MIA CO']);
  });

  group('OrderPackage.fromJson', () {
    test('reads what it knows and leaves out what it cannot use', () {
      final package = OrderPackage.fromJson({
        'status_code': 'shipped_partially',
        'state': 'a_new_state',
        'item_uids': ['MTAx', '', null, 7],
        'subtotal': {'value': '12.5', 'currency': 'AED'},
        'grand_total': {'value': null},
        'shipments': [
          {
            'number': '000000040',
            'created_at': 'not a date',
            'tracks': [
              {'number': ' ', 'carrier_title': 'Blank'},
              {
                'number': 'X1',
                'carrier_code': 'dhl',
                'tracking_url': 'http://insecure.example/X1',
              },
              {'number': 'X2', 'tracking_url': 'javascript:alert(1)'},
            ],
          },
          {'number': ''},
          'junk',
        ],
        'comments': [
          {'message': ''},
          {'message': 'Ready', 'created_at': '2026-09-29T06:05:00Z'},
        ],
      })!;

      // No label: the code itself; an unknown state is no stage.
      expect(package.statusLabel, 'shipped_partially');
      expect(package.stage, OrderPackageStage.unknown);
      expect(package.seller, isNull);
      expect(package.itemUids, ['MTAx']);
      expect(package.subtotal?.amount, 12.5);
      expect(package.grandTotal, isNull);
      final shipment = package.shipments.single;
      expect(shipment.createdAt, isNull);
      expect(shipment.tracks.map((t) => t.number), ['X1', 'X2']);
      // Only https pages open.
      expect(shipment.tracks.map((t) => t.trackingUrl), everyElement(isNull));
      expect(shipment.tracks.last.carrierCode, 'custom');
      expect(package.comments.single.message, 'Ready');
    });

    test('is null without an object, and the list skips what is not one', () {
      expect(OrderPackage.fromJson(null), isNull);
      expect(OrderPackage.fromJson('x'), isNull);
      expect(OrderPackage.listFromJson(null), isEmpty);
      expect(
        OrderPackage.listFromJson([
          {'status_code': 'complete', 'state': 'complete'},
          42,
        ]).single.stage,
        OrderPackageStage.complete,
      );
    });

    test('states map to stages', () {
      expect(OrderPackageStage.parse('new'), OrderPackageStage.pending);
      expect(
        OrderPackageStage.parse('pending_payment'),
        OrderPackageStage.pending,
      );
      expect(
        OrderPackageStage.parse('payment_review'),
        OrderPackageStage.processing,
      );
      expect(OrderPackageStage.parse('closed'), OrderPackageStage.canceled);
      expect(OrderPackageStage.parse('canceled'), OrderPackageStage.canceled);
      expect(OrderPackageStage.parse('holded'), OrderPackageStage.onHold);
      expect(OrderPackageStage.parse(null), OrderPackageStage.unknown);
    });
  });
}
