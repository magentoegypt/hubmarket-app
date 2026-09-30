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
  });

  /// `hm_seller` on products, cart lines and order lines (HubAppVendors).
  final bool sellers;

  /// `hmAddBundleToCart`, with `new_bundle` answering as a core
  /// `BundleProduct` (HubAppBundle).
  final bool bundles;

  /// `CustomerOrder.hm_packages`: an order split by store, with each store's
  /// status, shipments and totals (HubAppOrders).
  final bool packages;

  static const MarketplaceFeatures none = MarketplaceFeatures();
  static const MarketplaceFeatures all = MarketplaceFeatures(
    sellers: true,
    bundles: true,
    packages: true,
  );

  @override
  bool operator ==(Object other) =>
      other is MarketplaceFeatures &&
      other.sellers == sellers &&
      other.bundles == bundles &&
      other.packages == packages;

  @override
  int get hashCode => Object.hash(sellers, bundles, packages);

  @override
  String toString() =>
      'MarketplaceFeatures(sellers: $sellers, bundles: $bundles, '
      'packages: $packages)';
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
final marketplaceFeaturesProvider = Provider<MarketplaceFeatures>((ref) {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) {
    return MarketplaceFeatures.none;
  }
  final missing = ref.watch(marketplaceMissingProvider);
  return MarketplaceFeatures(
    sellers: !missing.sellers,
    bundles: !missing.bundles,
    packages: !missing.packages,
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
