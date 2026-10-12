import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/features/account/data/account_queries.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/marketplace_fakes.dart';
import '../../support/order_fulfillment_fixtures.dart';
import '../../support/order_package_fixtures.dart';

/// `CustomerOrder.hm_fulfillment` (FulfillmentTracking, CL036-DEV17): asked for
/// only while the server lists the `fulfillment` capability, dropped on its own
/// when it doesn't answer, and read into deliveries.

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

/// [order] as a server without the module answers: no `hm_fulfillment`.
Map<String, dynamic> _without(Map<String, dynamic> order) => {
  for (final entry in order.entries)
    if (entry.key != 'hm_fulfillment') entry.key: entry.value,
};

Response _refusal(List<String> fields) => Response(
  errors: [
    for (final field in fields)
      GraphQLError(
        message: 'Cannot query field "$field" on type "CustomerOrder".',
      ),
  ],
  response: const <String, dynamic>{},
);

void main() {
  group('the order documents', () {
    final documents = {
      'orders': AccountQueries.orders,
      'orderByNumber': AccountQueries.orderByNumber,
      'recentOrders': AccountQueries.recentOrders,
      'guestOrderByToken': AccountQueries.guestOrderByToken,
      'guestOrder': AccountQueries.guestOrder,
      'cancelOrder': AccountQueries.cancelOrder,
    };

    documents.forEach((name, document) {
      test('$name: asks for the deliveries only when told to', () {
        expect(document, isNot(contains('hm_fulfillment')));
        expect(
          AccountQueries.withHubApp(
            document,
            sellers: false,
            packages: false,
            fulfillment: false,
          ),
          document,
        );

        final twin = AccountQueries.withHubApp(
          document,
          sellers: false,
          packages: false,
          fulfillment: true,
        );
        expect(twin, contains('...HmOrderFulfillment'));
        expect(twin, contains('hm_fulfillment'));
        expect(twin, isNot(contains('...HmOrderPackages')));
        expect(twin, isNot(contains('...HmOrderSellers')));
        final ast = parseString(twin);
        expect(
          ast.definitions.whereType<OperationDefinitionNode>(),
          hasLength(1),
        );
        final fragments = [
          for (final f in ast.definitions.whereType<FragmentDefinitionNode>())
            f.name.value,
        ];
        // Each fragment once, although the seller's fields come with it.
        expect(fragments.toSet(), hasLength(fragments.length));
        expect(
          fragments,
          containsAll([
            'OrderFields',
            'HmOrderFulfillment',
            'HmSellerFields',
            'HmLinkFields',
          ]),
        );
      });
    });

    test('all three twins together are still one valid document', () {
      final twin = AccountQueries.withHubApp(
        AccountQueries.orders,
        sellers: true,
        packages: true,
        fulfillment: true,
      );
      final fragments = [
        for (final f in parseString(
          twin,
        ).definitions.whereType<FragmentDefinitionNode>())
          f.name.value,
      ];
      expect(fragments.toSet(), hasLength(fragments.length));
      expect(
        fragments,
        containsAll([
          'HmOrderSellers',
          'HmOrderPackages',
          'HmOrderFulfillment',
        ]),
      );
    });

    test(
      'the fragment asks for what the screens print and nothing internal',
      () {
        const fragment = AccountQueries.hmOrderFulfillment;
        for (final field in [
          'status_code',
          'status_label',
          'route_label',
          'handled_by',
          'tracked',
          'tracking_number',
          'tracking_url',
          'expected_delivery',
          'item_uids',
          'timeline',
        ]) {
          expect(fragment, contains(field));
        }
      },
    );
  });

  group('reading hm_fulfillment', () {
    OrderFulfillment read(Map<String, dynamic> json) =>
        OrderFulfillment.fromJson(json)!;

    test('an order placed before planning: one delivery per seller', () {
      final fulfillment = read(fulfillmentJson());

      expect(fulfillment.statusCode, 'preparing');
      expect(fulfillment.statusLabel, 'Preparing');
      expect(fulfillment.tone, DeliveryTone.info);
      expect(fulfillment.hasDeliveries, isTrue);
      expect(fulfillment.deliveries.map((d) => d.id), [
        'delivery-1',
        'delivery-2',
      ]);

      final loly = fulfillment.deliveries.first;
      expect(loly.route, 'direct');
      expect(loly.routeLabel, 'From the seller to you');
      expect(loly.sellerName, 'loly store');
      expect(loly.handledBy, 'seller');
      expect(loly.statusCode, 'on_the_way');
      expect(loly.statusLabel, 'On the way to you');
      expect(loly.tracked, isTrue);
      expect(loly.itemUids, [dressUid]);
      expect(loly.expectedDelivery, DateTime.utc(2026, 10, 15, 9));
      expect(loly.updatedAt, DateTime.utc(2026, 9, 29, 6, 10));
      final courier = loly.courier!;
      expect(courier.isThirdParty, isTrue);
      expect(courier.title, 'DHL');
      expect(courier.label, 'Courier');
      expect(courier.trackingNumber, dhlTrackingNumber);
      expect(courier.trackingUrl!.host, 'www.dhl.com');
      expect(loly.timeline.map((s) => s.statusCode), [
        'ordered',
        'ready_for_pickup',
        'on_the_way',
      ]);
      expect(loly.timeline.map((s) => s.statusLabel), [
        'Order placed',
        'Ready for courier pickup',
        'On the way to you',
      ]);
      expect(loly.timeline.first.at, DateTime.utc(2026, 9, 28, 6, 42));

      final mia = fulfillment.deliveries.last;
      expect(mia.tracked, isFalse);
      expect(mia.courier, isNull);
      expect(mia.expectedDelivery, isNull);
      expect(mia.itemUids, [sofaUid, chairUid]);
      expect(mia.timeline.single.statusCode, 'ordered');
    });

    test('an order through the warehouse: legs in, one leg out', () {
      final fulfillment = read(warehouseFulfillmentJson());

      expect(fulfillment.statusCode, 'to_hub');
      expect(fulfillment.deliveries.map((d) => d.route), [
        'to_hub',
        'to_hub',
        'from_hub',
      ]);
      // A line can ride a leg into the warehouse and again the leg out of it.
      expect(fulfillment.deliveries.first.itemUids, [dressUid]);
      expect(fulfillment.deliveries.last.itemUids, [
        dressUid,
        sofaUid,
        chairUid,
      ]);
      // The leg out can carry several sellers' items: no one seller is named.
      expect(fulfillment.deliveries.last.seller?.isMarketplace, isTrue);
      expect(fulfillment.deliveries.last.sellerName, isNull);
      expect(fulfillment.deliveries.first.sellerName, 'loly store');
      // Its own drivers: the courier reads as its label, with no number.
      final own = fulfillment.deliveries.last.courier!;
      expect(own.isThirdParty, isFalse);
      expect(own.title, 'Hub Market delivery');
      expect(own.trackingNumber, isNull);
      expect(own.trackingUrl, isNull);
    });

    test(
      'the Arabic store view comes back in Arabic, as the server wrote it',
      () {
        final fulfillment = read(fulfillmentJson(locale: 'ar'));

        expect(fulfillment.statusLabel, 'قيد التجهيز');
        expect(fulfillment.deliveries.first.routeLabel, 'من البائع إليك');
        expect(fulfillment.deliveries.first.statusLabel, 'في الطريق إليك');
        expect(fulfillment.deliveries.first.courier!.label, 'شركة الشحن');
      },
    );

    test('the tone of each status reads as the website colours it', () {
      for (final code in ['delivered', 'completed']) {
        expect(deliveryToneOf(code), DeliveryTone.success, reason: code);
      }
      for (final code in ['delayed', 'on_hold']) {
        expect(deliveryToneOf(code), DeliveryTone.warning, reason: code);
      }
      for (final code in ['canceled', 'refunded']) {
        expect(deliveryToneOf(code), DeliveryTone.danger, reason: code);
      }
      for (final code in [
        'ordered',
        'preparing',
        'ready_for_pickup',
        'to_hub',
        'at_hub',
        'shipped',
        'on_the_way',
        'a_status_of_a_later_server',
      ]) {
        expect(deliveryToneOf(code), DeliveryTone.info, reason: code);
      }
    });

    test('a tracking page is only ever a web page', () {
      for (final url in [
        'javascript:alert(1)',
        'http://insecure.example/track',
        'dhl://track/123',
        'not a url',
        '',
      ]) {
        final json = fulfillmentJson();
        final deliveries = json['deliveries'] as List;
        (deliveries.first as Map<String, dynamic>)['courier'] =
            thirdPartyCourierJson(url: url);
        expect(
          read(json).deliveries.first.courier!.trackingUrl,
          isNull,
          reason: url,
        );
      }
    });

    test('times without a zone are read as UTC, whatever the device says', () {
      final json = fulfillmentJson();
      final first = (json['deliveries'] as List).first as Map<String, dynamic>;
      first['expected_delivery'] = '2026-10-15 09:00:00';
      first['updated_at'] = '2026-09-29T06:10:00';
      (first['timeline'] as List).first['at'] = '2026-09-28T09:42:00+03:00';

      final delivery = read(json).deliveries.first;
      expect(delivery.expectedDelivery, DateTime.utc(2026, 10, 15, 9));
      expect(delivery.updatedAt, DateTime.utc(2026, 9, 29, 6, 10));
      expect(delivery.timeline.first.at, DateTime.utc(2026, 9, 28, 6, 42));
      expect(delivery.expectedDelivery!.isUtc, isTrue);
    });

    test('what the server leaves out is left out, not invented', () {
      final json = fulfillmentJson();
      final delivery =
          (json['deliveries'] as List).first as Map<String, dynamic>
            ..['seller'] = null
            ..['courier'] = null
            ..['handled_by'] = null
            ..['expected_delivery'] = null
            ..['updated_at'] = null;
      (delivery['timeline'] as List).first['at'] = null;

      final read1 = read(json).deliveries.first;
      expect(read1.seller, isNull);
      expect(read1.sellerName, isNull);
      expect(read1.courier, isNull);
      expect(read1.handledBy, isNull);
      expect(read1.expectedDelivery, isNull);
      expect(read1.timeline.first.at, isNull);
    });

    test(
      'unreadable entries are skipped; an unreadable whole is no fulfillment',
      () {
        final json = fulfillmentJson();
        json['deliveries'] = <Object?>[
          ...(json['deliveries'] as List),
          'nonsense',
          <String, dynamic>{'id': 'delivery-9'}, // no status
          null,
        ];
        expect(read(json).deliveries, hasLength(2));

        expect(OrderFulfillment.fromJson(null), isNull);
        expect(OrderFulfillment.fromJson('text'), isNull);
        expect(OrderFulfillment.fromJson(<String, dynamic>{}), isNull);
        expect(
          OrderFulfillment.fromJson({
            'status_code': 'delivered',
          })!.hasDeliveries,
          isFalse,
        );
      },
    );
  });

  group('AccountRepository', () {
    test('with the module the order comes with its deliveries', () async {
      final server = RecordingGraphQLClient(
        (_, __) => _orders(fulfilledOrderJson()),
      );
      final gate = RecordingMarketplaceGate();
      final page = await AccountRepository(
        server.client,
        marketplace: gate,
      ).fetchOrders();

      expect(server.documents.single, contains('hm_fulfillment'));
      expect(server.documents.single, contains('hm_packages'));
      final order = page.items.single;
      expect(order.hasDeliveries, isTrue);
      expect(order.fulfillment!.statusCode, 'preparing');
      expect(order.fulfillment!.deliveries, hasLength(2));
      // The deliveries point at the very lines the order holds.
      final uids = order.lines.map((l) => l.uid).toSet();
      for (final delivery in order.fulfillment!.deliveries) {
        expect(uids.containsAll(delivery.itemUids), isTrue);
      }
      // And the packages came with it.
      expect(order.packages, hasLength(2));
    });

    test(
      'the server could not read the progress: no fulfillment, no failure',
      () async {
        final server = RecordingGraphQLClient(
          (_, __) => _orders(fulfilledOrderJson(fulfillment: null)),
        );
        final page = await AccountRepository(
          server.client,
          marketplace: RecordingMarketplaceGate(),
        ).fetchOrders();

        expect(page.items.single.fulfillment, isNull);
        expect(page.items.single.hasDeliveries, isFalse);
        expect(page.items.single.lines, hasLength(3));
      },
    );

    test(
      'a server without hm_fulfillment still gets the packages and sellers',
      () async {
        final server = RecordingGraphQLClient(
          (_, document) => document.contains('hm_fulfillment')
              ? _refusal(['hm_fulfillment'])
              : _orders(_without(fulfilledOrderJson())),
        );
        final gate = RecordingMarketplaceGate();
        final page = await AccountRepository(
          server.client,
          marketplace: gate,
        ).fetchOrders();

        expect(gate.fulfillmentMissingCalls, 1);
        expect(gate.packagesMissingCalls, 0);
        expect(gate.sellersMissingCalls, 0);
        expect(server.documents, hasLength(2));
        expect(server.documents.last, isNot(contains('hm_fulfillment')));
        expect(server.documents.last, contains('hm_packages'));
        expect(server.documents.last, contains('hm_seller'));
        expect(page.items.single.fulfillment, isNull);
        expect(page.items.single.packages, hasLength(2));

        // The gate stops asking: the next read goes without it.
        await AccountRepository(server.client, marketplace: gate).fetchOrders();
        expect(server.documents, hasLength(3));
        expect(server.documents.last, isNot(contains('hm_fulfillment')));
      },
    );

    test(
      'a server that only lacks hm_packages keeps asking for the deliveries',
      () async {
        final server = RecordingGraphQLClient(
          (_, document) => document.contains('hm_packages')
              ? _refusal(['hm_packages'])
              : _orders(fulfilledOrderJson()),
        );
        final gate = RecordingMarketplaceGate();
        final page = await AccountRepository(
          server.client,
          marketplace: gate,
        ).fetchOrders();

        expect(gate.packagesMissingCalls, 1);
        expect(gate.fulfillmentMissingCalls, 0);
        expect(server.documents.last, contains('hm_fulfillment'));
        expect(page.items.single.fulfillment, isNotNull);
      },
    );

    test(
      'a refusal naming none of the HubApp fields drops all three',
      () async {
        final server = RecordingGraphQLClient(
          (_, document) => document.contains('hm_')
              ? Response(
                  errors: const [
                    GraphQLError(message: 'Unknown type "HmSomethingElse".'),
                  ],
                  response: const <String, dynamic>{},
                )
              : _orders(_without(fulfilledOrderJson())),
        );
        final gate = RecordingMarketplaceGate();
        await AccountRepository(server.client, marketplace: gate).fetchOrders();

        expect(gate.sellersMissingCalls, 1);
        expect(gate.packagesMissingCalls, 1);
        expect(gate.fulfillmentMissingCalls, 1);
        expect(server.documents, hasLength(2));
        expect(server.documents.last, isNot(contains('hm_')));
      },
    );

    test('without the capability nothing of it is asked for', () async {
      final server = RecordingGraphQLClient(
        (_, __) => _orders(_without(fulfilledOrderJson())),
      );
      final gate = RecordingMarketplaceGate(
        MarketplaceFeatures.all.copyWith(fulfillment: false),
      );
      final page = await AccountRepository(
        server.client,
        marketplace: gate,
      ).fetchOrders();

      expect(server.documents.single, isNot(contains('hm_fulfillment')));
      expect(page.items.single.fulfillment, isNull);

      // Nor on a server without HubApp at all.
      final plain = RecordingGraphQLClient(
        (_, __) => _orders(_without(fulfilledOrderJson())),
      );
      await AccountRepository(
        plain.client,
        marketplace: const FixedMarketplaceGate(),
      ).fetchOrders();
      expect(plain.documents.single, isNot(contains('hm_')));
    });

    test('a guest order by token carries its deliveries', () async {
      final server = RecordingGraphQLClient(
        (_, __) => {'guestOrderByToken': fulfilledOrderJson()},
      );
      final order = await AccountRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(),
      ).fetchGuestOrderByToken('token-1');

      expect(server.documents.single, contains('hm_fulfillment'));
      expect(order.placedAsGuest, isTrue);
      expect(order.fulfillment!.deliveries, hasLength(2));
    });
  });
}
