import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp_providers.dart';
import '../../../core/store/store_controller.dart';
import '../domain/brand.dart';
import 'brands_repository.dart';

/// Storefront brands (MGS › Shop by Brand), in admin order.
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

/// How many sellers carry a brand (by option id) — "from 2 stores" on its
/// page; null without the Hub Market App API or when it can't be counted.
final brandSellerCountProvider = FutureProvider.autoDispose.family<int?, int>((
  ref,
  optionId,
) async {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) return null;
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  try {
    return await ref.watch(brandsRepositoryProvider).fetchSellerCount(optionId);
  } on Object {
    return null;
  }
});

/// Catalogue products per brand option id — "12 products" on the brands
/// directory; empty without the Hub Market App API or the facet.
final brandProductCountsProvider = FutureProvider.autoDispose<Map<int, int>>((
  ref,
) async {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) {
    return const <int, int>{};
  }
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(brandsRepositoryProvider).fetchProductCounts();
});
