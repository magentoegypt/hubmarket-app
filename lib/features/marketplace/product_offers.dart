import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/store_controller.dart';

/// Whether the server turned down other sellers' offers (`hm_offer_count`,
/// `hm_other_offers`: HubAppVendors P3.1) although it serves `hm_seller`
/// (P2). The product page then reads the seller and a bundle's options
/// without them, instead of asking each time. Reset by a store switch, as the
/// other marketplace features are.
class ProductOffersMissing extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    return false;
  }

  void offersMissing() {
    if (!state) state = true;
  }
}

final productOffersMissingProvider =
    NotifierProvider<ProductOffersMissing, bool>(ProductOffersMissing.new);
