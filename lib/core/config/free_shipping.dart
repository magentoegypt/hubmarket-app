import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hubapp/hubapp_providers.dart';

/// The free-shipping threshold the cart, the added-to-cart sheet (14c) and
/// checkout (17) count down to, in the store currency — or null when the
/// backend doesn't publish one, in which case the bars hide and the cart's
/// delivery line reads "calculated at checkout".
///
/// It is the storefront's own figure, `hmAppConfig.shipping.free_over`: Hub
/// Market grants free shipping through a cart price rule (base subtotal of
/// at least the threshold), not through the Free Shipping carrier, and the
/// website's mini-cart counts down to that rule's number. The backend reads it
/// from the rules, so the business changes it in admin without a release —
/// never hardcode a threshold in the app.
///
/// Build 1 (no Hub Market App API) has no such figure: core `StoreConfig`
/// carries none, so the provider answers null without a request.
final freeShippingThresholdProvider = FutureProvider<double?>((ref) async {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) return null;
  return ref.watch(hmAppConfigProvider)?.shipping.freeOver;
});
