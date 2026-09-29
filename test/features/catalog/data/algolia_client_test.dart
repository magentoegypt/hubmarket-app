import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _appId = 'HL67ED06DQ';
const _key = 'public-search-key-for-tests';

const _queries = <AlgoliaQuery>[
  AlgoliaQuery('hubmarket_en_products', {
    'query': 'sofa bed',
    'hitsPerPage': 8,
    'facets': ['categoryIds'],
    'facetFilters': [
      ['color:Blue', 'color:Red'],
      'categoryIds:74',
    ],
    'analytics': false,
    'page': null,
  }),
  AlgoliaQuery('hubmarket_en_pages', {'query': 'sofa bed', 'hitsPerPage': 2}),
];

http.Response _ok(int results) => http.Response(
  jsonEncode({
    'results': [
      for (var i = 0; i < results; i++) {'hits': <Object>[], 'nbHits': i},
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('AlgoliaQuery', () {
    test('encodes params as one URL-encoded string, lists as JSON', () {
      final params = Uri.splitQueryString(_queries.first.encodedParams());
      expect(params['query'], 'sofa bed');
      expect(params['hitsPerPage'], '8');
      expect(params['analytics'], 'false');
      expect(jsonDecode(params['facets']!), ['categoryIds']);
      expect(jsonDecode(params['facetFilters']!), [
        ['color:Blue', 'color:Red'],
        'categoryIds:74',
      ]);
      // Null parameters are left out.
      expect(params.containsKey('page'), isFalse);
      // Spaces as %20, never '+', which Algolia would read literally.
      expect(_queries.first.encodedParams(), contains('query=sofa%20bed'));
    });
  });

  group('AlgoliaClient.multiQuery', () {
    test(
      'POSTs every query to the DSN host with the Algolia headers',
      () async {
        final sent = <http.Request>[];
        final client = AlgoliaClient(
          MockClient((request) async {
            sent.add(request);
            return _ok(2);
          }),
          userAgent: 'HubMarketApp-test',
        );

        final results = await client.multiQuery(
          appId: _appId,
          apiKey: _key,
          queries: _queries,
        );

        expect(results, hasLength(2));
        expect(results[1]['nbHits'], 1);
        expect(sent, hasLength(1));
        final request = sent.single;
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://hl67ed06dq-dsn.algolia.net/1/indexes/*/queries',
        );
        expect(request.headers['X-Algolia-Application-Id'], _appId);
        expect(request.headers['X-Algolia-API-Key'], _key);
        expect(request.headers['Content-Type'], startsWith('application/json'));
        expect(request.headers['User-Agent'], 'HubMarketApp-test');
        // The key never travels in the URL.
        expect(request.url.toString(), isNot(contains(_key)));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final requests = (body['requests'] as List)
            .cast<Map<String, dynamic>>();
        expect(requests.map((r) => r['indexName']), [
          'hubmarket_en_products',
          'hubmarket_en_pages',
        ]);
        expect(requests.first['params'], _queries.first.encodedParams());
      },
    );

    test(
      'a network error falls back to the -1/-2/-3 algolianet hosts',
      () async {
        final hosts = <String>[];
        final client = AlgoliaClient(
          MockClient((request) async {
            hosts.add(request.url.host);
            if (hosts.length < 3) {
              throw http.ClientException('Failed host lookup', request.url);
            }
            return _ok(2);
          }),
        );

        final results = await client.multiQuery(
          appId: _appId,
          apiKey: _key,
          queries: _queries,
        );

        expect(results, hasLength(2));
        expect(hosts, [
          'hl67ed06dq-dsn.algolia.net',
          'hl67ed06dq-1.algolianet.com',
          'hl67ed06dq-2.algolianet.com',
        ]);
      },
    );

    test('a host that times out is skipped', () async {
      final hosts = <String>[];
      final client = AlgoliaClient(
        MockClient((request) {
          hosts.add(request.url.host);
          // The DSN host never answers.
          if (hosts.length == 1) return Completer<http.Response>().future;
          return Future.value(_ok(2));
        }),
        timeout: const Duration(milliseconds: 20),
      );

      await client.multiQuery(appId: _appId, apiKey: _key, queries: _queries);

      expect(hosts, [
        'hl67ed06dq-dsn.algolia.net',
        'hl67ed06dq-1.algolianet.com',
      ]);
    });

    test('a 5xx or a non-search body tries the next host too', () async {
      var calls = 0;
      final client = AlgoliaClient(
        MockClient((request) async {
          calls++;
          if (calls == 1) return http.Response('{"message":"busy"}', 503);
          if (calls == 2) return http.Response('<html>portal</html>', 200);
          return _ok(2);
        }),
      );

      final results = await client.multiQuery(
        appId: _appId,
        apiKey: _key,
        queries: _queries,
      );
      expect(results, hasLength(2));
      expect(calls, 3);
    });

    test('a 4xx is Algolia\'s answer: no other host is tried', () async {
      var calls = 0;
      final client = AlgoliaClient(
        MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({'message': 'validUntil has expired', 'status': 403}),
            403,
          );
        }),
      );

      await expectLater(
        client.multiQuery(appId: _appId, apiKey: _key, queries: _queries),
        throwsA(
          isA<AlgoliaException>()
              .having((e) => e.kind, 'kind', AlgoliaErrorKind.rejected)
              .having((e) => e.status, 'status', 403)
              .having((e) => e.isKeyRejected, 'isKeyRejected', isTrue)
              .having((e) => e.message, 'message', 'validUntil has expired')
              // Nothing the exception prints carries the key.
              .having((e) => '$e', 'toString', isNot(contains(_key))),
        ),
      );
      expect(calls, 1);
    });

    test('when no host answers, the failure is "unreachable"', () async {
      var calls = 0;
      final client = AlgoliaClient(
        MockClient((request) async {
          calls++;
          throw http.ClientException('offline', request.url);
        }),
      );

      await expectLater(
        client.multiQuery(appId: _appId, apiKey: _key, queries: _queries),
        throwsA(
          isA<AlgoliaException>().having(
            (e) => e.kind,
            'kind',
            AlgoliaErrorKind.unreachable,
          ),
        ),
      );
      expect(calls, 4);
    });
  });
}
