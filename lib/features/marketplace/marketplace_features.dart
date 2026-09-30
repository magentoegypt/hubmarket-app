import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hubapp/hubapp.dart';
import '../../core/store/store_controller.dart';

/// Which HubApp marketplace features the app may use (contract
/// `lib/core/graphql/hubapp.graphql`). Everything off is today's server: no
/// seller rows, no grouping by store, bundles on the plain product page.
class MarketplaceFeatures {
  const MarketplaceFeatures({
    this.sellers = false,
    this.bundles = false,
    this.packages = false,
    this.listingSellers = false,
    this.storeExtras = false,
  });

  /// `hm_seller` on products, cart lines and order lines (HubAppVendors).
  final bool sellers;

  /// `hmAddBundleToCart`, with `new_bundle` answering as a core
  /// `BundleProduct` (HubAppBundle).
  final bool bundles;

  /// `CustomerOrder.hm_packages`: an order split by store, with each store's
  /// status, shipments and totals (HubAppOrders).
  final bool packages;

  /// `hm_seller` on listing cards (the seller line): only while the server
  /// lists the `vendors` capability. Listings are shared with Build 1, and a
  /// server with HubApp but without HubAppVendors would turn the whole
  /// listing down — the Home too — for this one field.
  final bool listingSellers;

  /// The store pages' fields that came with the `vendors` capability: the
  /// Reviews tab, contact, location and sales, each card's primary category
  /// and facet value, and the Stores chips' counts.
  final bool storeExtras;

  static const MarketplaceFeatures none = MarketplaceFeatures();
  static const MarketplaceFeatures all = MarketplaceFeatures(
    sellers: true,
    bundles: true,
    packages: true,
    listingSellers: true,
    storeExtras: true,
  );

  @override
  bool operator ==(Object other) =>
      other is MarketplaceFeatures &&
      other.sellers == sellers &&
      other.bundles == bundles &&
      other.packages == packages &&
      other.listingSellers == listingSellers &&
      other.storeExtras == storeExtras;

  @override
  int get hashCode =>
      Object.hash(sellers, bundles, packages, listingSellers, storeExtras);

  @override
  String toString() =>
      'MarketplaceFeatures(sellers: $sellers, bundles: $bundles, '
      'packages: $packages, listingSellers: $listingSellers, '
      'storeExtras: $storeExtras)';
}

/// Satellites the server turned down at run time ("Cannot query field
/// hm_seller") although `hmAppConfig` answered: HubAppVendors, HubAppBundle
/// and HubAppOrders can each be off on their own. Reset by a store switch,
/// which probes again.
typedef MarketplaceMissingState = ({bool sellers, bool bundles, bool packages});

class MarketplaceMissing extends Notifier<MarketplaceMissingState> {
  @override
  MarketplaceMissingState build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    return (sellers: false, bundles: false, packages: false);
  }

  void sellersMissing() {
    if (!state.sellers) {
      state = (sellers: true, bundles: state.bundles, packages: state.packages);
    }
  }

  void bundlesMissing() {
    if (!state.bundles) {
      state = (sellers: state.sellers, bundles: true, packages: state.packages);
    }
  }

  void packagesMissing() {
    if (!state.packages) {
      state = (sellers: state.sellers, bundles: state.bundles, packages: true);
    }
  }
}

final marketplaceMissingProvider =
    NotifierProvider<MarketplaceMissing, MarketplaceMissingState>(
      MarketplaceMissing.new,
    );

/// The marketplace features in use now: on once the HubApp probe says the
/// module is there ([HubAppStatus.available]), minus any satellite the server
/// turned down since. `unknown` (still probing, or offline) is Build 1.
///
/// When the server lists its satellites (`hmAppConfig.capabilities`), a
/// satellite it doesn't list is off from the start rather than after a
/// refused request; the fields that came with the list (listing sellers, the
/// store page extras) are on only when it lists `vendors`.
final marketplaceFeaturesProvider = Provider<MarketplaceFeatures>((ref) {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) {
    return MarketplaceFeatures.none;
  }
  final missing = ref.watch(marketplaceMissingProvider);
  final capabilities = ref.watch(hmAppConfigProvider)?.capabilities;
  final vendors =
      capabilities?.contains(HubAppCapability.vendors) ?? !missing.sellers;
  final bundle =
      capabilities?.contains(HubAppCapability.bundle) ?? !missing.bundles;
  final orders =
      capabilities?.contains(HubAppCapability.orders) ?? !missing.packages;
  final listed = capabilities != null && vendors && !missing.sellers;
  return MarketplaceFeatures(
    sellers: vendors && !missing.sellers,
    bundles: bundle && !missing.bundles,
    packages: orders && !missing.packages,
    listingSellers: listed,
    storeExtras: listed,
  );
});

/// What a repository asks before it sends a HubApp selection, and tells when
/// the server turned one down. It reads at request time, so building a
/// repository never starts the HubApp probe and a change of availability
/// needs no rebuild.
abstract interface class MarketplaceGate {
  MarketplaceFeatures get features;

  /// The server answered "Cannot query field" for `hm_seller`.
  void sellersMissing();

  /// The server answered "Cannot query field" for `hmAddBundleToCart`.
  void bundlesMissing();

  /// The server answered "Cannot query field" for `hm_packages`.
  void packagesMissing();
}

/// A gate with fixed [features] — today's behaviour by default; tests.
class FixedMarketplaceGate implements MarketplaceGate {
  const FixedMarketplaceGate([this.features = MarketplaceFeatures.none]);

  @override
  final MarketplaceFeatures features;

  @override
  void sellersMissing() {}

  @override
  void bundlesMissing() {}

  @override
  void packagesMissing() {}
}

class _ProviderGate implements MarketplaceGate {
  const _ProviderGate(this._ref);

  final Ref _ref;

  @override
  MarketplaceFeatures get features => _ref.read(marketplaceFeaturesProvider);

  @override
  void sellersMissing() =>
      _ref.read(marketplaceMissingProvider.notifier).sellersMissing();

  @override
  void bundlesMissing() =>
      _ref.read(marketplaceMissingProvider.notifier).bundlesMissing();

  @override
  void packagesMissing() =>
      _ref.read(marketplaceMissingProvider.notifier).packagesMissing();
}

/// The gate the repositories are built with.
final marketplaceGateProvider = Provider<MarketplaceGate>(_ProviderGate.new);
