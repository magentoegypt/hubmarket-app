import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/graphql_failure_mapper.dart';
import '../graphql/graphql_client.dart';

/// An emirate the address forms offer: a Magento system region of the store,
/// or — when the store defines none for the country — a named choice from
/// [uaeFallbackRegions] that is submitted as free text.
class RegionOption {
  const RegionOption({required this.id, required this.code, required this.name});

  /// The store's `region_id` — or, for [uaeFallbackRegions], a negative local
  /// id that only keys the picker and is never sent (see [isMagentoRegion]).
  final int id;
  final String code;
  final String name;

  /// Whether [id] is a real `region_id` of the connected store. Only those may
  /// be posted: Magento 2.4.8 rejects any other `region_id` outright ("The
  /// specified region is not a part of the selected country or region"), even
  /// for a country whose region is optional. Otherwise post [name] as
  /// `region`, which a country without regions accepts as free text.
  bool get isMagentoRegion => id > 0;
}

/// UAE-only storefront — the fixed address country. Region lists and the
/// address `country_code` both derive from this.
const String addressCountryCode = 'AE';

/// The seven emirates, offered when the store defines no regions for the UAE —
/// Hub Market defines none (`country(id: "AE") { available_regions }` is null)
/// — or when that lookup fails. The ids are local (negative), so the form
/// still gets its picker but submits the emirate's name as `region` instead of
/// a `region_id` the store doesn't have. English names: the store has no
/// localized regions to take them from.
const List<RegionOption> uaeFallbackRegions = [
  RegionOption(id: -1, code: 'AZ', name: 'Abu Dhabi'),
  RegionOption(id: -2, code: 'AJ', name: 'Ajman'),
  RegionOption(id: -3, code: 'DU', name: 'Dubai'),
  RegionOption(id: -4, code: 'FU', name: 'Fujairah'),
  RegionOption(id: -5, code: 'RK', name: 'Ras Al Khaimah'),
  RegionOption(id: -6, code: 'SH', name: 'Sharjah'),
  RegionOption(id: -7, code: 'UQ', name: 'Umm Al Quwain'),
];

/// The address-input fields for the emirate [regionId] picked from [regions]
/// (or the free-text [fallbackName] when the picker wasn't available):
/// `{region_id}` for a real store region, `{region: <name>}` otherwise, or
/// nothing when neither is known. Shared by checkout (`CartAddressInput`) and
/// the address book (`CustomerAddressRegionInput`), which name the same fields.
Map<String, dynamic> regionInput({
  required int? regionId,
  required List<RegionOption> regions,
  String fallbackName = '',
}) {
  RegionOption? picked;
  for (final r in regions) {
    if (r.id == regionId) {
      picked = r;
      break;
    }
  }
  if (picked != null && picked.isMagentoRegion) {
    return <String, dynamic>{'region_id': picked.id};
  }
  final name = (picked?.name ?? fallbackName).trim();
  return name.isEmpty ? const <String, dynamic>{} : <String, dynamic>{'region': name};
}

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
      // The store defines no regions for the country (Hub Market, for AE) —
      // fall through to the named emirates, submitted as free text.
    } on Object {
      // Live fetch failed (network / WAF-HTML / parse). Degrade to the named
      // emirates rather than blocking checkout; they never post a region_id,
      // so they can't carry an id the store doesn't know.
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
