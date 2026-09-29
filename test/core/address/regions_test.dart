import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/address/regions.dart';

import '../../support/fakes.dart';

/// A client answering `country(id:)` with [regions] (null = the store defines
/// none for the country, as Hub Market does for AE).
GraphQLClient _countryClient(List<Map<String, dynamic>>? regions) =>
    GraphQLClient(
      link: Link.function(
        (request, [forward]) => Stream<Response>.value(
          Response(
            data: <String, dynamic>{
              '__typename': 'Query',
              'country': <String, dynamic>{
                '__typename': 'Country',
                'id': 'AE',
                'available_regions': regions == null
                    ? null
                    : [
                        for (final r in regions)
                          <String, dynamic>{'__typename': 'Region', ...r},
                      ],
              },
            },
            response: const <String, dynamic>{},
            context: const Context(),
          ),
        ),
      ),
      cache: GraphQLCache(),
    );

void main() {
  group('RegionsRepository.fetchRegions', () {
    test('a store without UAE regions gets the named emirates', () async {
      final repo = RegionsRepository(_countryClient(null));

      final regions = await repo.fetchRegions('AE');

      expect(regions.map((r) => r.name), contains('Dubai'));
      expect(regions, hasLength(7));
      // None of them may be posted as a region_id: Magento 2.4.8 rejects a
      // region_id the country doesn't have.
      expect(regions.any((r) => r.isMagentoRegion), isFalse);
    });

    test("a store with UAE regions gets its own ids", () async {
      final repo = RegionsRepository(
        _countryClient([
          {'id': 1149, 'code': 'DU', 'name': 'Dubai'},
          {'id': 1148, 'code': 'AZ', 'name': 'Abu Dhabi'},
        ]),
      );

      final regions = await repo.fetchRegions('AE');

      expect(regions.map((r) => r.id), [1149, 1148]);
      expect(regions.every((r) => r.isMagentoRegion), isTrue);
    });

    test('a failed lookup still offers the named emirates', () async {
      // fakeGraphQLClient() errors on every request — a WAF/HTML or network
      // failure of country(id:"AE"). The picker must not come up empty.
      final repo = RegionsRepository(fakeGraphQLClient());

      final regions = await repo.fetchRegions('AE');

      expect(regions, hasLength(7));
      expect(regions.any((r) => r.isMagentoRegion), isFalse);
    });

    test('returns empty for a non-AE country when the live query fails', () async {
      final repo = RegionsRepository(fakeGraphQLClient());
      expect(await repo.fetchRegions('US'), isEmpty);
    });
  });

  group('uaeFallbackRegions', () {
    test('has all 7 emirates with unique, local-only ids', () {
      expect(uaeFallbackRegions.length, 7);
      expect(uaeFallbackRegions.map((r) => r.id).toSet().length, 7);
      expect(uaeFallbackRegions.every((r) => !r.isMagentoRegion), isTrue);
      expect(uaeFallbackRegions.map((r) => r.name).toSet(), {
        'Abu Dhabi',
        'Ajman',
        'Dubai',
        'Fujairah',
        'Ras Al Khaimah',
        'Sharjah',
        'Umm Al Quwain',
      });
    });
  });

  group('regionInput', () {
    const live = [RegionOption(id: 1149, code: 'DU', name: 'Dubai')];

    test("a store region goes out as its region_id", () {
      expect(regionInput(regionId: 1149, regions: live), {'region_id': 1149});
    });

    test('a named emirate goes out as free-text region', () {
      final dubai = uaeFallbackRegions.firstWhere((r) => r.name == 'Dubai');
      expect(
        regionInput(regionId: dubai.id, regions: uaeFallbackRegions),
        {'region': 'Dubai'},
      );
    });

    test('falls back to typed text, then to nothing', () {
      expect(
        regionInput(regionId: null, regions: const [], fallbackName: ' Dubai '),
        {'region': 'Dubai'},
      );
      expect(regionInput(regionId: null, regions: const []), isEmpty);
    });
  });
}
