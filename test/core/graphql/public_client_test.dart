import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';

/// Records every HTTP request the real link chain sends.
class _Recorder {
  final requests = <http.BaseRequest>[];

  late final client = MockClient((request) async {
    requests.add(request);
    return http.Response(
      jsonEncode({
        'data': {
          '__typename': 'Query',
          'hmAppConfig': {'__typename': 'HmAppConfig', 'store_code': 'ar'},
          'ping': true,
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  const pingDocument = r'''
mutation Ping {
  revokeCustomerToken { result }
}
''';

  group('the public GET client', () {
    test('sends a query as GET, with the Store header and no Authorization',
        () async {
      final recorder = _Recorder();
      final client = buildGraphQLClient(
        config: AppConfig.current,
        storeCode: () => 'ar',
        getForQueries: true,
        httpClient: recorder.client,
      );

      final result = await client.query(
        QueryOptions(
          document: gql('query HmAppConfig { hmAppConfig { store_code } }'),
        ),
      );

      expect(result.hasException, isFalse, reason: '${result.exception}');
      final request = recorder.requests.single;
      expect(request.method, 'GET');
      expect(request.headers['Store'], 'ar');
      expect(request.headers['User-Agent'], AppConfig.current.userAgent);
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      final params = request.url.queryParameters;
      expect(params['operationName'], 'HmAppConfig');
      expect(params.containsKey('variables'), isFalse);
      expect(
        params['query'],
        'query HmAppConfig{__typename hmAppConfig{__typename store_code}}',
      );
      expect(request.url.path, '/graphql');
    });

    test('the probe document fits comfortably in a URL', () {
      final url = Uri.parse(AppConfig.current.graphqlEndpoint).replace(
        queryParameters: {
          'operationName': 'HmAppConfig',
          'query': compactGraphQLDocument(
            HubAppConfigRepository.documentFor(HmPlatform.android),
          ),
        },
      );
      expect(url.toString().length, lessThan(1500));
    });

    test('mutations still go as POST', () async {
      final recorder = _Recorder();
      final client = buildGraphQLClient(
        config: AppConfig.current,
        storeCode: () => 'en',
        getForQueries: true,
        httpClient: recorder.client,
      );

      await client.mutate(MutationOptions(document: gql(pingDocument)));

      expect(recorder.requests.single.method, 'POST');
    });

    test('only a client built with a token sends one (over POST)', () async {
      final recorder = _Recorder();
      final authed = buildGraphQLClient(
        config: AppConfig.current,
        storeCode: () => 'en',
        token: () async => 'customer-token',
        httpClient: recorder.client,
      );

      await authed.query(
        QueryOptions(document: gql('query HmAppConfig { hmAppConfig { store_code } }')),
      );

      final request = recorder.requests.single;
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer customer-token');
    });
  });

  group('compactGraphQLDocument', () {
    test('drops comments and spacing, keeps separators and strings', () {
      const document = '''
# Home rails
query Home(\$size: Int = 20) {
  a: products(search: "  two  spaces ", pageSize: \$size) {
    items { sku ... on BundleProduct { dynamic_sku } }
  }
  cmsBlocks(identifiers: ["x", "y"]) { items { identifier } }
}
''';
      expect(
        compactGraphQLDocument(document),
        'query Home(\$size:Int=20){a:products(search:"  two  spaces "'
        'pageSize:\$size){items{sku...on BundleProduct{dynamic_sku}}}'
        'cmsBlocks(identifiers:["x" "y"]){items{identifier}}}',
      );
    });
  });
}
