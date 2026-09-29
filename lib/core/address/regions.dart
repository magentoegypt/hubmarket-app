import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/graphql_failure_mapper.dart';
import '../graphql/graphql_client.dart';

/// A Magento system region (e.g. a UAE emirate). Magento requires a valid
/// `region_id` on an address when the country has system regions (AE does), so
/// address forms post this id rather than free-text `region`.
class RegionOption {
  const RegionOption({required this.id, required this.code, required this.name});

  final int id;
  final String code;
  final String name;
}

/// UAE-only storefront — the fixed address country. Region lists and the
/// address `country_code` both derive from this.
const String addressCountryCode = 'AE';

/// The seven UAE emirates as Magento system regions, with the live `region_id`s
/// (1148–1154) confirmed against hub-market.magento2.click. Used as a fallback when the live
/// `country(id:"AE")` query fails or returns empty, so the emirate picker always
/// offers a valid `region_id`. Magento rejects an AE address that carries
/// neither `region_id` nor a resolvable `region` ("Region is required."), which
/// otherwise blocks (guest) checkout at the "Continue" step. Order matches the
/// live query (alphabetical by name); Arabic labels come from the live query
/// when it succeeds — this English fallback only appears if that call fails.
const List<RegionOption> uaeFallbackRegions = [
  RegionOption(id: 1148, code: 'AZ', name: 'Abu Dhabi'),
  RegionOption(id: 1151, code: 'AJ', name: 'Ajman'),
  RegionOption(id: 1149, code: 'DU', name: 'Dubai'),
  RegionOption(id: 1154, code: 'FU', name: 'Fujairah'),
  RegionOption(id: 1153, code: 'RK', name: 'Ras Al Khaimah'),
  RegionOption(id: 1150, code: 'SH', name: 'Sharjah'),
  RegionOption(id: 1152, code: 'UQ', name: 'Umm Al Quwain'),
];

/// Fetches a country's system regions from the live schema
/// (`country(id:){ available_regions }`). Cross-cutting (checkout + account),
/// so it lives in core rather than a single feature.
class RegionsRepository {
  RegionsRepository(this._client);

  final GraphQLClient _client;

  static const String _query = r'''
query CountryRegions($id: String!) {
  country(id: $id) {
    id
    available_regions { id code name }
  }
}
''';

  Future<List<RegionOption>> fetchRegions(String countryCode) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(_query),
          variables: {'id': countryCode},
          // Region lists are effectively static — cache across the session.
          fetchPolicy: FetchPolicy.cacheFirst,
        ),
      );
      if (result.hasException) throw mapOperationException(result.exception!);
      final regions =
          (result.data?['country']
                  as Map<String, dynamic>?)?['available_regions']
              as List<dynamic>?;
      final parsed = (regions ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((r) => r['id'] != null)
          .map(
            (r) => RegionOption(
              id: (r['id'] as num).toInt(),
              code: (r['code'] as String?) ?? '',
              name: (r['name'] as String?) ?? '',
            ),
          )
          .toList();
      if (parsed.isNotEmpty) return parsed;
      // Server returned no regions — fall through to the static fallback so an
      // AE address can still carry a valid region_id.
    } on Object {
      // Live fetch failed (network / WAF-HTML / parse). For AE we still have a
      // known-good region set, so degrade to it rather than blocking checkout.
    }
    if (countryCode == addressCountryCode) return uaeFallbackRegions;
    return const [];
  }
}

final regionsRepositoryProvider = Provider<RegionsRepository>(
  (ref) => RegionsRepository(ref.watch(graphqlClientProvider)),
);

/// Regions for the storefront country (AE → the seven emirates). Cached for the
/// session and shared by every address form.
final regionsProvider = FutureProvider<List<RegionOption>>(
  (ref) => ref.watch(regionsRepositoryProvider).fetchRegions(addressCountryCode),
);
