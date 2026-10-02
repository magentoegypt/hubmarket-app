import 'package:flutter_riverpod/flutter_riverpod.dart';

// Separate from address/auth providers so catalog transport can invalidate its
// cache on a destination change without recreating the customer/cart clients.
final deliveryHeadersProvider = StateProvider<Map<String, String>>((ref) => {});
