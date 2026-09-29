import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp.dart';
import '../../catalog/domain/aggregation.dart';
import '../../catalog/presentation/search_controller.dart';
import 'stores_providers.dart';

/// The attribute of the storefront's Algolia seller facet: each product
/// record carries its seller's display name there (`AlgoliaVendor`
/// `AddSellerData`), in the store view's language.
const String kSellerFacet = 'seller';

/// A seller a search found (Figma 09c's Vendors tab and vendor card).
@immutable
class SearchVendor {
  const SearchVendor({
    required this.store,
    this.matchCount,
    this.nameMatch = false,
  });

  final HmStoreCard store;

  /// How many of the search's products the seller sells, from the seller
  /// facet; null when the engine has no such facet.
  final int? matchCount;

  /// The seller's own name or code contains the query.
  final bool nameMatch;
}

/// The seller facet's counts by display name, or empty without one.
Map<String, int> sellerFacetCounts(List<Aggregation> facets) {
  final facet = facets
      .where((f) => f.attributeCode == kSellerFacet)
      .firstOrNull;
  return <String, int>{
    for (final option in facet?.options ?? const <AggregationOption>[])
      if (option.count > 0 &&
          (option.value.trim().isNotEmpty || option.label.trim().isNotEmpty))
        (option.value.trim().isNotEmpty ? option.value : option.label).trim():
            option.count,
  };
}

/// The sellers a search found, best first: those whose name matches the
/// query (the shopper typed a store's name), then the sellers of the matching
/// products by how many they sell.
///
/// The seller facet names sellers, so each name is looked up in [directory]
/// (every approved seller) — both are the storefront's display name in the
/// same language. A name the directory doesn't know is dropped: the app
/// could not open that store.
List<SearchVendor> searchVendorsFrom({
  required List<HmStoreCard> nameMatches,
  List<HmStoreCard> directory = const <HmStoreCard>[],
  Map<String, int> sellerCounts = const <String, int>{},
}) {
  String key(String name) => name.trim().toLowerCase();
  final byName = <String, HmStoreCard>{
    for (final card in nameMatches) key(card.name): card,
    for (final card in directory) key(card.name): card,
  };
  final byCode = <String, HmStoreCard>{
    for (final card in directory) card.code: card,
    for (final card in nameMatches) card.code: card,
  };
  final counts = <String, int>{};
  for (final MapEntry(key: name, value: count) in sellerCounts.entries) {
    final card = byName[key(name)];
    if (card != null) counts[card.code] = (counts[card.code] ?? 0) + count;
  }

  final vendors = <SearchVendor>[];
  final listed = <String>{};
  for (final card in nameMatches) {
    if (listed.add(card.code)) {
      vendors.add(
        SearchVendor(store: card, matchCount: counts[card.code], nameMatch: true),
      );
    }
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final MapEntry(key: code, value: count) in ranked) {
    if (listed.add(code)) {
      vendors.add(SearchVendor(store: byCode[code]!, matchCount: count));
    }
  }
  return List.unmodifiable(vendors);
}

/// The sellers one submitted search found (see [searchVendorsFrom]). Either
/// source failing only leaves its sellers out: vendors never stand in the way
/// of the products.
final searchVendorsProvider = FutureProvider.autoDispose
    .family<List<SearchVendor>, SearchRequest>((ref, request) async {
      final query = request.query.trim();
      if (query.isEmpty) return const <SearchVendor>[];
      final counts = sellerFacetCounts(
        ref.watch(searchResultsProvider(request).select((s) => s.facets)),
      );

      List<HmStoreCard> nameMatches;
      try {
        nameMatches = await ref.watch(storeNameMatchesProvider(query).future);
      } on Object {
        nameMatches = const <HmStoreCard>[];
      }
      var directory = const <HmStoreCard>[];
      if (counts.isNotEmpty) {
        try {
          directory = await ref.watch(storeDirectoryProvider.future);
        } on Object {
          directory = const <HmStoreCard>[];
        }
      }
      return searchVendorsFrom(
        nameMatches: nameMatches,
        directory: directory,
        sellerCounts: counts,
      );
    });
