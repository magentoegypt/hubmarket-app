import 'package:flutter/foundation.dart';

import 'aggregation.dart';
import 'product.dart';
import 'search_facets.dart';
import 'search_highlight.dart';

/// Which backend answered a search.
enum SearchEngine {
  /// The storefront's Algolia indices — the website's own search.
  algolia,

  /// Magento GraphQL `products(search:)`, the fallback when Algolia can't
  /// answer. Hub Market answers it from OpenSearch, so its ranking can differ.
  catalog,
}

/// How search results are ordered: by relevance (the primary index) or by an
/// attribute, as a sort replica does.
@immutable
class SearchSort {
  const SearchSort(this.attribute, {this.descending = false});

  static const SearchSort relevance = SearchSort('');

  /// `price`, `created_at`, `name`, …; empty for relevance.
  final String attribute;
  final bool descending;

  bool get isRelevance => attribute.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is SearchSort &&
      other.attribute == attribute &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(attribute, descending);

  @override
  String toString() => isRelevance
      ? 'SearchSort.relevance'
      : 'SearchSort($attribute ${descending ? 'desc' : 'asc'})';
}

/// One entry of the results' Sort sheet: a sort, with the backend's label for
/// it when the app has no wording of its own.
@immutable
class SearchSortOption {
  const SearchSortOption(this.sort, {this.label = ''});

  final SearchSort sort;
  final String label;
}

/// The shopper's filters on a search's results.
@immutable
class SearchFilters {
  const SearchFilters({
    this.attributes = const <String, Set<String>>{},
    this.priceFrom,
    this.priceTo,
    this.minRating,
  });

  static const SearchFilters none = SearchFilters();

  /// Selected values per facet attribute (`color` → {Blue, Red}). Values of
  /// one attribute are alternatives; attributes combine.
  final Map<String, Set<String>> attributes;
  final double? priceFrom;
  final double? priceTo;

  /// "N★ & above", in whole stars.
  final int? minRating;

  bool get hasPrice => priceFrom != null || priceTo != null;

  /// How many filters are on — the Filter action's badge.
  int get count =>
      attributes.values.fold(0, (sum, values) => sum + values.length) +
      (hasPrice ? 1 : 0) +
      (minRating != null ? 1 : 0);

  bool get isEmpty => count == 0;
}

/// A product the type-ahead lists (Figma 09): the product, where the search
/// matched its name, and the category it names ("in Home Furniture").
@immutable
class SearchProductHit {
  const SearchProductHit({
    required this.product,
    this.nameMatches = const <TextSlice>[],
    this.categoryName,
  });

  final Product product;
  final List<TextSlice> nameMatches;
  final String? categoryName;
}

/// A CMS page the type-ahead offers (Figma 09 "Pages").
@immutable
class SearchPageHit {
  const SearchPageHit({required this.title, required this.url});

  final String title;

  /// The page's storefront URL, e.g. `https://…/en/customer-service`.
  final String url;
}

/// The type-ahead's answer for one query.
@immutable
class TypeAheadResult {
  const TypeAheadResult({
    required this.engine,
    this.products = const <SearchProductHit>[],
    this.totalCount = 0,
    this.resultCategories = const <SearchCategory>[],
    this.categoryChips = const <SearchCategory>[],
    this.pages = const <SearchPageHit>[],
  });

  final SearchEngine engine;
  final List<SearchProductHit> products;

  /// All matching products — "View all N results".
  final int totalCount;

  /// The categories the matches fall into, best first: the "See products in
  /// … or in A, B" links.
  final List<SearchCategory> resultCategories;

  /// The pinned bar's Categories chips: categories whose names match (the
  /// categories index) on Algolia, the result's top categories otherwise.
  final List<SearchCategory> categoryChips;
  final List<SearchPageHit> pages;

  bool get isEmpty =>
      products.isEmpty && categoryChips.isEmpty && pages.isEmpty;
}

/// One page of a search's full results (Figma 09c), with what the Filter and
/// Sort sheets and the Categories tab offer.
@immutable
class SearchResultPage {
  const SearchResultPage({
    required this.engine,
    required this.products,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    this.facets = const <Aggregation>[],
    this.categories = const <SearchCategory>[],
    this.sorts = const <SearchSortOption>[],
    this.sort = SearchSort.relevance,
    this.filters = SearchFilters.none,
    this.ratingFilter = false,
  });

  final SearchEngine engine;
  final List<Product> products;
  final int totalCount;

  /// 1-based.
  final int currentPage;
  final int totalPages;

  /// The Filter sheet's sections. A `price` entry carries the bounds of the
  /// price slider in its option values.
  final List<Aggregation> facets;

  /// The categories the results fall into — the Categories tab.
  final List<SearchCategory> categories;

  /// Relevance first, then what the engine can sort by.
  final List<SearchSortOption> sorts;

  /// The sort and filters the page was fetched with — reset when the fallback
  /// engine couldn't apply the ones asked for.
  final SearchSort sort;
  final SearchFilters filters;

  /// Whether "N★ & above" can filter these results.
  final bool ratingFilter;
}
