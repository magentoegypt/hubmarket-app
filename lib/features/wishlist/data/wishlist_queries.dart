/// Hand-written Magento 2.4.8 wishlist operations (customer-scoped).
abstract final class WishlistQueries {
  /// The items are asked of the deprecated `Wishlist.items`, not `items_v2`, on
  /// purpose (QA TC105: the wishlist differed between Arabic and English).
  ///
  /// Magento stamps every wishlist item with the store view it was added in.
  /// Core's `items_v2` resolver (`WishlistItems`) then filters on the store view
  /// of the request, the `Store` header, so a product saved under `ar` is missing
  /// from the list under `en` and the other way round, while `items_count` counts
  /// the website's every store view and went on showing the right number. `items`
  /// (`WishlistItemsResolver`) filters on every store view: the whole wishlist
  /// whichever language the app is in, its products named and priced in that
  /// language. It has no paging, so it answers all of the items at once.
  ///
  /// `test/features/wishlist/wishlist_store_views_test.dart` fails on `items_v2`.
  static const String _wishlistFields = r'''
fragment WishlistFields on Wishlist {
  id
  items_count
  items {
    id
    product {
      sku
      name
      url_key
      stock_status
      new_from_date
      new_to_date
      rating_summary
      review_count
      image { url }
      price_range {
        minimum_price {
          regular_price { value currency }
          final_price { value currency }
        }
      }
    }
  }
}
''';

  static String _doc(String operation) => '$operation\n$_wishlistFields';

  static final String getWishlist = _doc(r'''
query Wishlist {
  customer {
    wishlists { ...WishlistFields }
  }
}''');

  static final String addToWishlist = _doc(r'''
mutation AddToWishlist($wishlistId: ID!, $items: [WishlistItemInput!]!) {
  addProductsToWishlist(wishlistId: $wishlistId, wishlistItems: $items) {
    wishlist { ...WishlistFields }
    user_errors { code message }
  }
}''');

  static final String removeFromWishlist = _doc(r'''
mutation RemoveFromWishlist($wishlistId: ID!, $itemIds: [ID!]!) {
  removeProductsFromWishlist(wishlistId: $wishlistId, wishlistItemsIds: $itemIds) {
    wishlist { ...WishlistFields }
    user_errors { code message }
  }
}''');
}
