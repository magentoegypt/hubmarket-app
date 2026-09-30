import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';

/// The interfaces of [sdl] with the types that implement them.
Map<String, Set<String>> _implementations(String sdl) {
  final out = <String, Set<String>>{};
  for (final match in RegExp(
    r'^type (\w+) implements ([\w\s&]+?)\s*[{@]',
    multiLine: true,
  ).allMatches(sdl)) {
    for (final iface in match.group(2)!.split('&')) {
      out.putIfAbsent(iface.trim(), () => <String>{}).add(match.group(1)!);
    }
  }
  return out;
}

/// The type conditions of every fragment the app defines.
Set<String> _fragmentTypes() => {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File &&
        (file.path.endsWith('.dart') || file.path.endsWith('.graphql')) &&
        !file.path.endsWith('.graphql.dart') &&
        !file.path.endsWith('schema.graphql') &&
        !file.path.endsWith('hubapp.graphql'))
      for (final match in RegExp(
        r'fragment\s+\w+\s+on\s+(\w+)',
      ).allMatches(file.readAsStringSync()))
        match.group(1)!,
};

void main() {
  final schema = File('lib/core/graphql/schema.graphql').readAsStringSync();
  final interfaces = {
    for (final match in RegExp(
      r'^interface (\w+)',
      multiLine: true,
    ).allMatches(schema))
      match.group(1)!,
  };

  test('every interface a fragment is written on has its concrete types', () {
    final used = _fragmentTypes().where(interfaces.contains).toSet();

    expect(used, contains('ProductInterface'));
    expect(kGraphQLPossibleTypes.keys.toSet(), containsAll(used));
  });

  test('the concrete types are the live schema\'s', () {
    final implementations = _implementations(schema);
    for (final MapEntry(key: iface, value: types)
        in kGraphQLPossibleTypes.entries) {
      expect(types, implementations[iface], reason: iface);
    }
  });

  test('a fragment on ProductInterface comes back filled', () async {
    final client = buildGraphQLClient(
      config: AppConfig.current,
      storeCode: () => 'en',
      getForQueries: true,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {
              '__typename': 'Query',
              'products': {
                '__typename': 'Products',
                'items': [
                  {
                    '__typename': 'ConfigurableProduct',
                    'sku': 'A',
                    'name': 'Corner Sofa Bed',
                    'hm_seller': {
                      '__typename': 'HmSellerSummary',
                      'name': 'MIA CO',
                    },
                  },
                ],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await client.query(
      QueryOptions(
        document: gql(r'''
query PossibleTypes { products(search: "sofa") { items { sku ...PossibleTypesCard } } }
fragment PossibleTypesCard on ProductInterface { name }
'''),
      ),
    );

    expect(result.exception, isNull);
    final item = (result.data!['products'] as Map)['items'][0] as Map;
    expect(item['name'], 'Corner Sofa Bed');
  });
}
