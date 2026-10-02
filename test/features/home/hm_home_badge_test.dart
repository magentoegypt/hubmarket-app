import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show printNode;
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/graphql/possible_types.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';

// The section badge (`HmHomeSection.badge`, admin Badge field): the small pill
// above a Home section's title. Null means no pill.

Map<String, dynamic> _home() => {
  'hmAppHome': {
    '__typename': 'HmHome',
    'store_code': 'en',
    'generated_at': null,
    'sections': [
      {
        '__typename': 'HmHomeSection',
        'id': 5,
        'type': 'PICKED_FOR_YOU',
        'title': 'Picked For You',
        'subtitle': 'Top-rated products across Hub Market',
        'limit': 16,
        'personalizable': true,
        'products': <Object?>[],
      },
    ],
  },
};

/// A server whose answer depends on whether the document asks for `badge`.
GraphQLClient _client({
  required Object withBadge,
  Object? withoutBadge,
  List<bool>? asked,
}) => GraphQLClient(
  link: Link.function((request, [forward]) {
    final text = printNode(request.operation.document);
    final hasBadge = RegExp(r'\bbadge\b').hasMatch(text);
    asked?.add(hasBadge);
    final answer = hasBadge ? withBadge : withoutBadge;
    if (answer is Response) return Stream.value(answer);
    if (answer is Map<String, dynamic>) {
      return Stream.value(
        Response(data: answer, response: const <String, dynamic>{}),
      );
    }
    return Stream.error(Exception('offline (test)'));
  }),
  cache: GraphQLCache(
    partialDataPolicy: PartialDataCachePolicy.accept,
    possibleTypes: kPossibleTypes,
  ),
);

void main() {
  group('hmHomeSectionFromJson', () {
    Map<String, dynamic> section(Object? badge) => {
      'id': 5,
      'type': 'PICKED_FOR_YOU',
      'title': 'Picked For You',
      'badge': badge,
    };

    test('reads the badge the admin typed', () {
      expect(hmHomeSectionFromJson(section('AI ENGINE'))!.badge, 'AI ENGINE');
      expect(hmHomeSectionFromJson(section('محرك ذكي'))!.badge, 'محرك ذكي');
    });

    test('null, blank or missing means no badge', () {
      expect(hmHomeSectionFromJson(section(null))!.badge, isNull);
      expect(hmHomeSectionFromJson(section('   '))!.badge, isNull);
      expect(
        hmHomeSectionFromJson({'id': 5, 'type': 'PICKED_FOR_YOU'})!.badge,
        isNull,
      );
    });
  });

  group('the Home request', () {
    test('asks for the badge of every section', () {
      expect(
        HmHomeRepository.documentFor(HmAudience.guest),
        contains('subtitle badge limit'),
      );
    });

    test('can be written without it', () {
      final document = HmHomeRepository.documentFor(HmAudience.guest, badge: false);
      expect(document, isNot(contains('badge')));
      expect(document, contains('subtitle limit'));
    });

    test('a server that has the badge answers the first request', () async {
      final asked = <bool>[];
      final repository = HmHomeRepository(
        _client(withBadge: _home(), asked: asked),
      );
      final home = await repository.fetchHome(HmAudience.guest);
      expect(asked, [true]);
      expect(home.sections.single.limit, 16);
    });

    test('a HubApp older than the badge is asked again without it: a missing '
        'pill never turns the Home down', () async {
      final asked = <bool>[];
      final repository = HmHomeRepository(
        _client(
          withBadge: Response(
            errors: const [
              GraphQLError(
                message: 'Cannot query field "badge" on type "HmHomeSection".',
              ),
            ],
            response: const <String, dynamic>{},
          ),
          withoutBadge: _home(),
          asked: asked,
        ),
      );

      final home = await repository.fetchHome(HmAudience.guest);

      expect(asked, [true, false]);
      expect(home.sections.single.title, 'Picked For You');
      expect(home.sections.single.badge, isNull);
    });

    test('a server without the Home itself is still HubAppMissing', () async {
      final repository = HmHomeRepository(
        _client(
          withBadge: Response(
            errors: const [
              GraphQLError(
                message: 'Cannot query field "hmAppHome" on type "Query".',
              ),
            ],
            response: const <String, dynamic>{},
          ),
        ),
      );
      await expectLater(
        repository.fetchHome(HmAudience.guest),
        throwsA(isA<HubAppMissing>()),
      );
    });
  });
}
