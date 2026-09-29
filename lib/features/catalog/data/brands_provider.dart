import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/brand.dart';

/// Storefront brands (Shop by Brand), sorted by position then title.
///
/// Hub Market manages brands in MGS › Shop by Brand, but that module has no
/// GraphQL yet, so Build 1 returns an empty list and every brand surface shows
/// its neutral empty state — nothing is invented. Build 2 adds a brands
/// resolver in the Hub Market App backend module; brand landing pages then
/// filter products on the `mgs_brand` option id (see catalog_repository).
final brandsProvider = FutureProvider.autoDispose<List<Brand>>(
  (ref) async => const <Brand>[],
);
