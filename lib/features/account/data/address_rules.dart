import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/address/regions.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';

const String _optionalZipQuery = r'''
query OptionalZipCountries {
  storeConfig { optional_zip_countries }
}
''';

/// Whether a store whose "Zip/Postal Code is Optional for" list is
/// [optionalZipCountries] (comma-separated ISO codes) requires a postcode for
/// [country]. Magento's rule: every country outside the list needs one — so a
/// missing list means required.
bool postcodeRequiredFor(String? optionalZipCountries, String country) {
  if (optionalZipCountries == null) return true;
  return !optionalZipCountries
      .split(',')
      .map((c) => c.trim().toUpperCase())
      .contains(country.toUpperCase());
}

/// Whether the store requires a postcode on [addressCountryCode] addresses.
///
/// Magento validates every address against `storeConfig.optional_zip_countries`:
/// for a country outside it, both `setShippingAddressesOnCart` and
/// `createCustomerAddress` fail with '"postcode" is required'. The UAE has no
/// postcodes and the design has no field for one, so the forms only add it
/// when the store demands it. Hub Market's list is `HK,IE,MO,PA,GB`, so today
/// it does — adding AE to that list in admin removes the field again without a
/// release.
///
/// When the setting can't be read, the field is shown: an unnecessary postcode
/// costs a few keystrokes, a missing one leaves the shopper stuck on an error
/// they have no field to fix.
final postcodeRequiredProvider = FutureProvider<bool>((ref) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(
        document: gql(_optionalZipQuery),
        // Store configuration — effectively static per store view.
        fetchPolicy: FetchPolicy.cacheFirst,
      ),
    );
    if (result.hasException) return true;
    final list =
        (result.data?['storeConfig']
                as Map<String, dynamic>?)?['optional_zip_countries']
            as String?;
    return postcodeRequiredFor(list, addressCountryCode);
  } catch (_) {
    return true;
  }
});
