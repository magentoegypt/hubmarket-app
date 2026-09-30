import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp_providers.dart';
import '../../../core/store/store_controller.dart';
import '../domain/brand.dart';
import 'brands_repository.dart';

/// Storefront brands (MGS › Shop by Brand), in admin order, each with how
/// many products its page lists and from how many sellers (`hmBrands`
/// `product_count` / `seller_count`, counted by the backend).
///
/// Served by the Hub Market App API (`hmBrands`). Without it — Build 1 — the
/// list is empty and every brand surface shows its neutral empty state:
/// nothing is invented. Brand pages filter products on the `mgs_brand`
/// option id (see catalog_repository).
final brandsProvider = FutureProvider.autoDispose<List<Brand>>((ref) async {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) {
    return const <Brand>[];
  }
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final brands = await ref.watch(brandsRepositoryProvider).fetchBrands();
  // Kept while the session lasts once read: the directory, the Home strip and
  // storefront brand links all look brands up here.
  ref.keepAlive();
  return brands;
});
