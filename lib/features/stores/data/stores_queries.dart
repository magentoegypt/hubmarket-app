import '../../../core/hubapp/hubapp.dart';
import '../../marketplace/data/seller_selections.dart';
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
/// The P3.1 fields (each card's primary category and Algolia facet value, the
/// page's contact, location and sales, the Reviews tab and the chips' counts)
/// go out only while the server lists the `vendors` capability
/// (`MarketplaceFeatures.storeExtras`): `extras: true` documents.
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
  /// `pageSize` is 1–50: the backend rejects more. With [extras], each card
  /// also carries its primary category and facet value.
  static String storeList(StoreSort sort, {bool extras = false}) {
    final document = sort == StoreSort.featured
        ? storeListTemplate
        : storeListTemplate.replaceFirst('sort: FEATURED', 'sort: ${sort.wire}');
    return extras ? _withCardExtras(document) : document;
  }

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

  /// [storePage] with the P3.1 fields: the contact and location the store
  /// page publishes, its sales count, and the card extras.
  static final String storePageWithExtras = _withCardExtras(
    storePage.replaceFirst(
      'card { ...HmStoreCardFields }',
      '...HmStorePageExtras card { ...HmStoreCardFields }',
    ),
    fragments: storePageExtras,
  );

  /// `...HmStorePageExtras` on `HmStore`.
  static const String storePageExtras =
      r'''fragment HmStorePageExtras on HmStore{contact{phone} location sales_count}''';

  /// Figma 13's Reviews tab: the seller's rating and a page of the reviews
  /// this store view shows. Null for a code that isn't an approved seller.
  static const String storeReviews = r'''
query HmStoreReviews($code: String!, $pageSize: Int!, $currentPage: Int!) {
  hmStoreReviews(code: $code, pageSize: $pageSize, currentPage: $currentPage) {
    summary { rating review_count }
    total_count
    page_info { current_page page_size total_pages }
    items {
      id nickname title text rating created_at
      product { name url_key thumbnail_url }
    }
  }
}
''';

  /// Figma 12's chips with their seller counts.
  static const String storeCategories = r'''
query HmStoreCategories {
  hmStoreCategories {
    total_count
    items { id uid name count }
  }
}
''';

  /// [document] with `...HmStoreCardExtras` beside each `...HmStoreCardFields`
  /// and the fragments it needs appended.
  static String _withCardExtras(String document, {String fragments = ''}) =>
      SellerSelections.beside(
        document,
        anchor: 'HmStoreCardFields',
        spread: 'HmStoreCardExtras',
        fragments: '${HmFragments.storeCardExtras}\n$fragments',
      );
}
