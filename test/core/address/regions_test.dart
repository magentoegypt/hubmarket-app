import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/address/regions.dart';

import '../../support/fakes.dart';

void main() {
  group('RegionsRepository.fetchRegions', () {
    test('falls back to the 7 UAE emirates when the live query fails', () async {
      // fakeGraphQLClient() errors on every request — simulates a WAF/HTML or
      // network failure of country(id:"AE"). AE must still resolve to a valid
      // region set so (guest) checkout can post a region_id.
      final repo = RegionsRepository(fakeGraphQLClient());

      final regions = await repo.fetchRegions('AE');

      expect(regions.length, 7);
      expect(
        regions.map((r) => r.id).toSet(),
        {1148, 1149, 1150, 1151, 1152, 1153, 1154},
      );
      // The id↔emirate mapping matters — Magento validates region_id against the
      // country. Spot-check the value the checkout sends for Dubai.
      expect(regions.any((r) => r.name == 'Dubai' && r.id == 1149), isTrue);
    });

    test('returns empty for a non-AE country when the live query fails', () async {
      final repo = RegionsRepository(fakeGraphQLClient());
      expect(await repo.fetchRegions('US'), isEmpty);
    });
  });

  group('uaeFallbackRegions', () {
    test('has all 7 emirates with the live region_ids and unique ids', () {
      expect(uaeFallbackRegions.length, 7);
      expect(uaeFallbackRegions.map((r) => r.id).toSet().length, 7);
      expect(
        uaeFallbackRegions.map((r) => r.id).toSet(),
        {1148, 1149, 1150, 1151, 1152, 1153, 1154},
      );
      // id↔name pairs confirmed against the live hub-market.magento2.click schema.
      final byName = {for (final r in uaeFallbackRegions) r.name: r.id};
      expect(byName['Abu Dhabi'], 1148);
      expect(byName['Dubai'], 1149);
      expect(byName['Sharjah'], 1150);
      expect(byName['Ajman'], 1151);
      expect(byName['Umm Al Quwain'], 1152);
      expect(byName['Ras Al Khaimah'], 1153);
      expect(byName['Fujairah'], 1154);
    });
  });
}
