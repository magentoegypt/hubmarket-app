import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The free-shipping threshold the cart and the product page count down to —
/// Magento's Free Shipping "Minimum Order Amount", in the store currency — or
/// null when the backend doesn't publish one, in which case both bars hide and
/// the cart's delivery line reads "calculated at checkout".
///
/// Hub Market publishes none: core `StoreConfig` has no field for
/// `carriers/freeshipping/free_shipping_subtotal` (Zoonze read it from a custom
/// `free_shipping_subtotal` field that this backend doesn't have), so this
/// reports "not configured" without a request. When the backend exposes the
/// value, fetch it here — never hardcode a threshold in the app; the business
/// changes it in admin without a release.
final freeShippingThresholdProvider = FutureProvider<double?>((ref) async => null);
