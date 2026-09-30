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

/// The seller facet's counts by facet value, or empty without one. Values
/// are kept as the index has them: [searchVendorsFrom] compares them exactly
/// with [HmStoreCard.facetValue].
Map<String, int> sellerFacetCounts(List<Aggregation> facets) {
  final facet = facets
      .where((f) => f.attributeCode == kSellerFacet)
      .firstOrNull;
  return <String, int>{
    for (final option in facet?.options ?? const <AggregationOption>[])
      if (option.count > 0 &&
          (option.value.trim().isNotEmpty || option.label.trim().isNotEmpty))
        (option.value.isNotEmpty ? option.value : option.label):
            option.count,
  };
}

/// The sellers a search found, best first: those whose name matches the
/// query (the shopper typed a store's name), then the sellers of the matching
/// products by how many they sell.
///
/// The seller facet counts products by the value AlgoliaVendor indexes for
/// their seller, so each value is looked up in [directory] (every approved
/// seller): exactly, by the card's [HmStoreCard.facetValue] — the backend's
/// own record of that value — and, for cards from a server that doesn't send
/// it, by display name (the same text in the same language today, compared
/// loosely). A value the directory doesn't know is dropped: the app could not
/// open that store.
List<SearchVendor> searchVendorsFrom({
  required List<HmStoreCard> nameMatches,
  List<HmStoreCard> directory = const <HmStoreCard>[],
  Map<String, int> sellerCounts = const <String, int>{},
}) {
  String key(String name) => name.trim().toLowerCase();
  final byFacet = <String, HmStoreCard>{
    for (final card in nameMatches)
      if (card.facetValue case final value?) value: card,
    for (final card in directory)
      if (card.facetValue case final value?) value: card,
  };
  final byName = <String, HmStoreCard>{
    for (final card in nameMatches)
      if (card.facetValue == null) key(card.name): card,
    for (final card in directory)
      if (card.facetValue == null) key(card.name): card,
  };
  final byCode = <String, HmStoreCard>{
    for (final card in directory) card.code: card,
    for (final card in nameMatches) card.code: card,
  };
  final counts = <String, int>{};
  for (final MapEntry(key: value, value: count) in sellerCounts.entries) {
    final card = byFacet[value] ?? byName[key(value)];
    if (card != null) counts[card.code] = (counts[card.code] ?? 0) + count;
  }

  final vendors = <SearchVendor>[];
  final listed = <String>{};
  for (final card in nameMatches) {
    if (listed.add(card.code)) {
      vendors.add(
        SearchVendor(
          store: card,
          matchCount: counts[card.code],
          nameMatch: true,
        ),
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
