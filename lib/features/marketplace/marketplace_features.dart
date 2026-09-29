import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hubapp/hubapp.dart';
import '../../core/store/store_controller.dart';

/// Which HubApp marketplace features the app may use (contract
/// `lib/core/graphql/hubapp.graphql`). Everything off is today's server: no
/// seller rows, no grouping by store, bundles on the plain product page.
class MarketplaceFeatures {
  const MarketplaceFeatures({this.sellers = false, this.bundles = false});

  /// `hm_seller` on products, cart lines and order lines (HubAppVendors).
  final bool sellers;

  /// `hmAddBundleToCart`, with `new_bundle` answering as a core
  /// `BundleProduct` (HubAppBundle).
  final bool bundles;

  static const MarketplaceFeatures none = MarketplaceFeatures();
  static const MarketplaceFeatures all = MarketplaceFeatures(
    sellers: true,
    bundles: true,
  );

  @override
  bool operator ==(Object other) =>
      other is MarketplaceFeatures &&
      other.sellers == sellers &&
      other.bundles == bundles;

  @override
  int get hashCode => Object.hash(sellers, bundles);

  @override
  String toString() => 'MarketplaceFeatures(sellers: $sellers, bundles: $bundles)';
}

/// Satellites the server turned down at run time ("Cannot query field
/// hm_seller") although `hmAppConfig` answered: HubAppVendors and HubAppBundle
/// can each be off on their own. Reset by a store switch, which probes again.
class MarketplaceMissing extends Notifier<({bool sellers, bool bundles})> {
  @override
  ({bool sellers, bool bundles}) build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    return (sellers: false, bundles: false);
  }

  void sellersMissing() {
    if (!state.sellers) state = (sellers: true, bundles: state.bundles);
  }

  void bundlesMissing() {
    if (!state.bundles) state = (sellers: state.sellers, bundles: true);
  }
}

final marketplaceMissingProvider =
    NotifierProvider<MarketplaceMissing, ({bool sellers, bool bundles})>(
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
}

/// The gate the repositories are built with.
final marketplaceGateProvider = Provider<MarketplaceGate>(_ProviderGate.new);
