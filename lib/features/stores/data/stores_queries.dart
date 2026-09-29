import '../../../core/hubapp/hubapp.dart';
import '../domain/store.dart';

/// GraphQL documents of the seller directory and store pages, served by the
/// Hub Market App backend (`MagentoEgypt_HubAppVendors`; contract
/// `lib/core/graphql/hubapp.graphql`). Public reads: they go as GET through
/// `publicGraphqlClientProvider`, so they stay compact.
///
/// No variable has an `Hm*` type: while the module is missing, Magento answers
/// one with HTTP 500 instead of "Cannot query field" (see `runHubAppQuery`).
/// The filter is an inline input object over scalar variables — the backend
/// ignores a null field — and the sort is inlined per request ([storeList]).
///
/// A seller's products are not here: they are core `products` filtered by
/// `vendor_id` (see `StoreProductsRepository`).
abstract final class StoresQueries {
  /// The shared card fragments the documents spread.
  static const String _cardFragments =
      '${HmFragments.storeCard}\n${HmFragments.link}';

  /// The list document, sorted [StoreSort.featured]; [storeList] swaps the
  /// sort in.
  static const String storeListTemplate =
      r'''
query HmStores($pageSize: Int!, $currentPage: Int!, $featured: Boolean, $categoryId: Int, $name: String) {
  hmStores(filter: {featured: $featured, category_id: $categoryId, name: $name}, sort: FEATURED, pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page page_size total_pages }
    items { ...HmStoreCardFields }
  }
}
''' +
      _cardFragments;

  /// Figma 12's list and featured banner, and search's store matches.
  /// `pageSize` is 1–50: the backend rejects more.
  static String storeList(StoreSort sort) => sort == StoreSort.featured
      ? storeListTemplate
      : storeListTemplate.replaceFirst('sort: FEATURED', 'sort: ${sort.wire}');

  /// Figma 13 / 13b: one seller's page. Null for a code that isn't an
  /// approved seller.
  static const String storePage =
      r'''
query HmStore($code: String!) {
  hmStore(code: $code) {
    banner_url
    short_description
    about_html
    shipping_policy_html
    refund_policy_html
    card { ...HmStoreCardFields }
  }
}
''' +
      _cardFragments;
}
