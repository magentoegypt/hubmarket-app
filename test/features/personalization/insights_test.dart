import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/personalization/data/insights_client.dart';
import 'package:hubmarket_app/features/personalization/data/insights_tracker.dart';
import 'package:hubmarket_app/features/personalization/data/product_object_ids.dart';
import 'package:hubmarket_app/features/personalization/domain/insights_event.dart';

import '../../support/hubapp_fakes.dart';

final _at = DateTime.utc(2026, 10, 2, 12);
final _atMs = _at.millisecondsSinceEpoch;

const _settings = AlgoliaSettings(
  appId: 'HL67ED06DQ',
  searchKey: 'search-only-key',
  indexName: 'hubmarket_en',
);

/// Resolves the SKUs it was given and nothing else.
class _FixedIds extends ProductObjectIds {
  _FixedIds(this.ids) : super(FakeHubAppClient(const {}));

  final Map<String, String> ids;
  final asked = <List<String>>[];

  @override
  Future<Map<String, String>> resolve(Iterable<String> skus) async {
    asked.add(skus.toList());
    return {
      for (final sku in skus)
        if (ids[sku] case final id?) sku: id,
    };
  }
}

/// What reached Algolia: one decoded body per request, and the requests.
class _Algolia {
  _Algolia({this.status = 200});

  final int status;
  final requests = <http.Request>[];

  List<Map<String, dynamic>> get events => [
    for (final request in requests)
      ...(jsonDecode(request.body)['events'] as List).cast<Map<String, dynamic>>(),
  ];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return http.Response('{"status":$status,"message":"x"}', status);
  });
}

void main() {
  group('the events, as the Insights API takes them', () {
    Map<String, Object?> one(InsightsEvent event) =>
        event.toJson(index: 'hubmarket_en_products', userToken: 'hm-tok', at: _at).single;

    test('a viewed product', () {
      expect(one(InsightsEvent.viewed('2226')), {
        'eventType': 'view',
        'eventName': 'Viewed Product',
        'index': 'hubmarket_en_products',
        'userToken': 'hm-tok',
        'timestamp': _atMs,
        'objectIDs': ['2226'],
      });
    });

    test('a clicked product and a wishlist add use the website\'s names', () {
      expect(one(InsightsEvent.clicked('7')), containsPair('eventType', 'click'));
      expect(one(InsightsEvent.clicked('7')), containsPair('eventName', 'Product Clicked'));
      final wish = one(InsightsEvent.addedToWishlist('7'));
      expect(wish, containsPair('eventType', 'conversion'));
      expect(wish, containsPair('eventName', 'Added to Wishlist'));
      expect(wish.containsKey('eventSubtype'), isFalse);
    });

    test('an add to cart with its price carries the subtype, object data and '
        'currency', () {
      final event = one(
        InsightsEvent.addedToCart(
          const [InsightsLine(objectId: '2226', quantity: 2, unitPrice: 99)],
          'AED',
        ),
      );
      expect(event, containsPair('eventType', 'conversion'));
      expect(event, containsPair('eventSubtype', 'addToCart'));
      expect(event, containsPair('eventName', 'Added to Cart'));
      expect(event['objectIDs'], ['2226']);
      expect(event['objectData'], [
        {'price': 99.0, 'quantity': 2},
      ]);
      expect(event, containsPair('currency', 'AED'));
    });

    test('without a price it is the plain conversion', () {
      final event = one(
        InsightsEvent.addedToCart(const [InsightsLine(objectId: '2226', quantity: 1)], 'AED'),
      );
      expect(event, containsPair('eventName', 'Added to Cart'));
      expect(event.containsKey('eventSubtype'), isFalse);
      expect(event.containsKey('objectData'), isFalse);
      expect(event.containsKey('currency'), isFalse);
    });

    test('a placed order is a purchase', () {
      final event = one(
        InsightsEvent.purchased(
          const [
            InsightsLine(objectId: '1', quantity: 1, unitPrice: 10),
            InsightsLine(objectId: '2', quantity: 3, unitPrice: 4.5),
          ],
          'AED',
        ),
      );
      expect(event, containsPair('eventName', 'Placed order'));
      expect(event, containsPair('eventSubtype', 'purchase'));
      expect(event['objectIDs'], ['1', '2']);
      expect(event['objectData'], [
        {'price': 10.0, 'quantity': 1},
        {'price': 4.5, 'quantity': 3},
      ]);
    });

    test('an order of more than 20 products is split: Algolia takes 20 per '
        'event', () {
      final payloads = InsightsEvent.purchased(
        [
          for (var i = 0; i < 25; i++)
            InsightsLine(objectId: '$i', quantity: 1, unitPrice: 5),
        ],
        'AED',
      ).toJson(index: 'i', userToken: 't', at: _at);
      expect(payloads.map((p) => (p['objectIDs'] as List).length), [20, 5]);
      expect(payloads.map((p) => (p['objectData'] as List).length), [20, 5]);
      expect(payloads.last['objectIDs'], ['20', '21', '22', '23', '24']);
    });
  });

  group('product ids', () {
    test('the id is inside the uid', () {
      expect(ProductObjectIds.idFromUid('MjIyNg=='), '2226');
      expect(ProductObjectIds.idFromUid('MjExMQ=='), '2111');
      expect(ProductObjectIds.idFromUid(null), isNull);
      expect(ProductObjectIds.idFromUid(''), isNull);
      expect(ProductObjectIds.idFromUid('not base64!'), isNull);
      // a uid that is not a number (a category path, say)
      expect(ProductObjectIds.idFromUid(base64.encode(utf8.encode('abc'))), isNull);
    });

    Map<String, dynamic> products(Map<String, String> uids) => {
      'products': {
        '__typename': 'Products',
        'items': [
          for (final e in uids.entries)
            {'__typename': 'SimpleProduct', 'sku': e.key, 'uid': e.value},
        ],
      },
    };

    test('are asked of the catalogue by SKU once, then remembered', () async {
      final log = <dynamic>[];
      final ids = ProductObjectIds(
        FakeHubAppClient({
          'ProductObjectIds': products({'DL-PD-8021G-3L': 'MjIyNg=='}),
        }, log: log.cast()),
      );

      expect(await ids.resolve(['DL-PD-8021G-3L']), {'DL-PD-8021G-3L': '2226'});
      expect(log, hasLength(1));
      // asked again, in another case: no second request
      expect(await ids.resolve(['dl-pd-8021g-3l']), {'dl-pd-8021g-3l': '2226'});
      expect(log, hasLength(1));
    });

    test('a SKU the catalogue does not know is left out, and a failure is '
        'quiet', () async {
      final ids = ProductObjectIds(
        FakeHubAppClient({'ProductObjectIds': products({'A': 'MQ=='})}),
      );
      expect(await ids.resolve(['A', 'B']), {'A': '1'});
      expect(await ProductObjectIds(FakeHubAppClient(const {})).resolve(['A']), isEmpty);
    });

    test('an id learnt for free can be remembered', () async {
      final ids = ProductObjectIds(FakeHubAppClient(const {}));
      ids.remember('sku1', '42');
      ids.remember('sku2', 'not-an-id');
      expect(await ids.resolve(['sku1', 'sku2']), {'sku1': '42'});
    });
  });

  group('the client', () {
    test('posts the events to the Insights host with the app id and key', () async {
      final algolia = _Algolia();
      final ok = await InsightsClient(algolia.client, userAgent: 'HubMarket/1')
          .send(appId: 'HL67ED06DQ', apiKey: 'k', events: [{'eventName': 'x'}]);

      expect(ok, isTrue);
      final request = algolia.requests.single;
      expect(request.url.toString(), 'https://insights.algolia.io/1/events');
      expect(request.method, 'POST');
      expect(request.headers['X-Algolia-Application-Id'], 'HL67ED06DQ');
      expect(request.headers['X-Algolia-API-Key'], 'k');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['User-Agent'], 'HubMarket/1');
      expect(jsonDecode(request.body), {
        'events': [{'eventName': 'x'}],
      });
    });

    test('says no for a refusal or a lost connection, and never throws', () async {
      for (final status in [400, 422, 500]) {
        final ok = await InsightsClient(_Algolia(status: status).client)
            .send(appId: 'a', apiKey: 'k', events: [{'e': 1}]);
        expect(ok, isFalse, reason: '$status');
      }
      final offline = InsightsClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await offline.send(appId: 'a', apiKey: 'k', events: [{'e': 1}]), isFalse);
    });

    test('sends nothing when there is nothing to send', () async {
      final algolia = _Algolia();
      expect(await InsightsClient(algolia.client).send(appId: 'a', apiKey: 'k', events: []), isTrue);
      expect(algolia.requests, isEmpty);
    });
  });

  group('the tracker', () {
    ({InsightsTracker tracker, _Algolia algolia, _FixedIds ids, List<bool> enabled}) make({
      bool enabled = true,
      AlgoliaSettings? settings = _settings,
      Map<String, String> ids = const {'sku1': '101', 'sku2': '102'},
      int status = 200,
      DateTime Function()? clock,
    }) {
      final algolia = _Algolia(status: status);
      final fixed = _FixedIds(ids);
      final flag = [enabled];
      final tracker = InsightsTracker(
        enabled: () => flag.single,
        settings: () async => settings,
        token: () => 'hm-tok',
        ids: fixed,
        client: InsightsClient(algolia.client),
        clock: clock ?? () => _at,
      );
      return (tracker: tracker, algolia: algolia, ids: fixed, enabled: flag);
    }

    test('tells Algolia about a viewed product, under the shopper\'s token, on '
        'the products index', () async {
      final t = make();
      t.tracker.productViewed('sku1');
      await pumpEventQueue();

      expect(t.algolia.events.single, {
        'eventType': 'view',
        'eventName': 'Viewed Product',
        'index': 'hubmarket_en_products',
        'userToken': 'hm-tok',
        'timestamp': _atMs,
        'objectIDs': ['101'],
      });
      final request = t.algolia.requests.single;
      expect(request.headers['X-Algolia-Application-Id'], 'HL67ED06DQ');
      expect(request.headers['X-Algolia-API-Key'], 'search-only-key');
    });

    test('a page opened twice within half a minute is one view; later it is '
        'another', () async {
      var now = _at;
      final t = make(clock: () => now);
      t.tracker.productViewed('sku1');
      await pumpEventQueue();
      now = _at.add(const Duration(seconds: 10));
      t.tracker.productViewed('sku1');
      await pumpEventQueue();
      expect(t.algolia.events, hasLength(1));

      now = _at.add(const Duration(seconds: 31));
      t.tracker.productViewed('sku1');
      await pumpEventQueue();
      expect(t.algolia.events, hasLength(2));

      // another product is its own view
      t.tracker.productViewed('sku2');
      await pumpEventQueue();
      expect(t.algolia.events, hasLength(3));
    });

    test('a tap, a wishlist add and a cart add', () async {
      final t = make();
      t.tracker.productClicked('sku1');
      t.tracker.addedToWishlist('sku2');
      t.tracker.addedToCart('sku1', quantity: 2, unitPrice: const Money(amount: 49.5, currency: 'AED'));
      await pumpEventQueue();

      expect(
        t.algolia.events.map((e) => '${e['eventType']}:${e['eventName']}:${e['objectIDs']}'),
        unorderedEquals([
          'click:Product Clicked:[101]',
          'conversion:Added to Wishlist:[102]',
          'conversion:Added to Cart:[101]',
        ]),
      );
      final cart = t.algolia.events.firstWhere((e) => e['eventName'] == 'Added to Cart');
      expect(cart['eventSubtype'], 'addToCart');
      expect(cart['objectData'], [
        {'price': 49.5, 'quantity': 2},
      ]);
      expect(cart['currency'], 'AED');
    });

    test('a cart add without a price is the plain conversion', () async {
      final t = make();
      t.tracker.addedToCart('sku1');
      await pumpEventQueue();
      final cart = t.algolia.events.single;
      expect(cart['eventName'], 'Added to Cart');
      expect(cart.containsKey('objectData'), isFalse);
    });

    test('a placed order is one purchase of every line the catalogue knows', () async {
      final t = make();
      t.tracker.orderPlaced(const [
        TrackedLine(sku: 'sku1', quantity: 1, unitPrice: Money(amount: 10, currency: 'AED')),
        TrackedLine(sku: 'sku2', quantity: 3, unitPrice: Money(amount: 4, currency: 'AED')),
        TrackedLine(sku: 'unknown', quantity: 1, unitPrice: Money(amount: 1, currency: 'AED')),
      ]);
      await pumpEventQueue();

      final order = t.algolia.events.single;
      expect(order['eventName'], 'Placed order');
      expect(order['eventSubtype'], 'purchase');
      expect(order['objectIDs'], ['101', '102']);
      expect(order['objectData'], [
        {'price': 10.0, 'quantity': 1},
        {'price': 4.0, 'quantity': 3},
      ]);
      expect(order['currency'], 'AED');
      t.tracker.orderPlaced(const []);
      await pumpEventQueue();
      expect(t.algolia.requests, hasLength(1));
    });

    test('sends nothing, and asks nothing, with personalisation off', () async {
      final t = make(enabled: false);
      t.tracker
        ..productViewed('sku1')
        ..productClicked('sku1')
        ..addedToCart('sku1')
        ..addedToWishlist('sku1')
        ..orderPlaced(const [TrackedLine(sku: 'sku1', quantity: 1)]);
      await pumpEventQueue();
      expect(t.algolia.requests, isEmpty);
      expect(t.ids.asked, isEmpty);
    });

    test('sends nothing without a token: no consent, no id', () async {
      final algolia = _Algolia();
      final tracker = InsightsTracker(
        enabled: () => true,
        settings: () async => _settings,
        token: () => null,
        ids: _FixedIds(const {'sku1': '101'}),
        client: InsightsClient(algolia.client),
      );
      tracker
        ..productViewed('sku1')
        ..addedToWishlist('sku1');
      await pumpEventQueue();
      expect(algolia.requests, isEmpty);
    });

    test('an event is dropped when the switch goes off while its ids are on '
        'their way', () async {
      final t = make();
      t.tracker.productClicked('sku1');
      t.enabled[0] = false;
      await pumpEventQueue();
      expect(t.algolia.requests, isEmpty);
    });

    test('sends nothing without Algolia settings or for a product it cannot '
        'identify', () async {
      final none = make(settings: null);
      none.tracker.productClicked('sku1');
      await pumpEventQueue();
      expect(none.algolia.requests, isEmpty);

      final unknown = make();
      unknown.tracker.productClicked('not-in-the-catalogue');
      await pumpEventQueue();
      expect(unknown.algolia.requests, isEmpty);
    });

    test('a refusal or a failure anywhere never reaches the caller', () async {
      final refused = make(status: 422);
      refused.tracker.productViewed('sku1');
      await pumpEventQueue();

      final broken = InsightsTracker(
        enabled: () => true,
        settings: () async => throw StateError('no settings'),
        token: () => 'hm-tok',
        ids: _FixedIds(const {}),
        client: InsightsClient(_Algolia().client),
      );
      expect(() => broken.productClicked('x'), returnsNormally);
      await pumpEventQueue();

      expect(() => trackInsights(() => throw StateError('no provider'), (t) => t.productClicked('x')), returnsNormally);
    });
  });
}
